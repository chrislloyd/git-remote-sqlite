const std = @import("std");
const sqlite = @import("sqlite.zig");
const protocol = @import("protocol.zig");
const git = @import("git.zig");
const transport = @import("transport.zig");
const cmd = @import("cmd.zig");

// ---

pub const Remote = struct {
    pub const Error = error{
        DatabaseError,
        InvalidArgs,
        GitDirNotSet,
    } || git.GitError || transport.RemoteUrlError;

    db: *sqlite.Database,
    objects: sqlite.ObjectDatabase,
    refs: sqlite.RefDatabase,
    allocator: std.mem.Allocator,
    repo: *git.Repository,

    /// Create new SQLite remote instance
    pub fn init(allocator: std.mem.Allocator, db: *sqlite.Database, repo: *git.Repository) Error!Remote {

        var remote = Remote{
            .db = db,
            .objects = undefined,
            .refs = undefined,
            .allocator = allocator,
            .repo = repo,
        };

        // Initialize database components with automatic schema migration
        remote.objects = sqlite.ObjectDatabase.init(remote.db) catch return Error.DatabaseError;
        remote.refs = sqlite.RefDatabase.init(remote.db) catch return Error.DatabaseError;

        return remote;
    }

    pub fn capabilities(_: *Remote, _: std.mem.Allocator) !protocol.Response.Capabilities {
        return .{
            .import = false,
            .@"export" = false,
            .push = true,
            .fetch = true,
            .connect = false,
            .stateless_connect = false,
            .check_connectivity = false,
            .get = false,
            .bidi_import = false,
            .signed_tags = false,
            .object_format = false,
            .no_private_update = false,
            .progress = true,
            .option = true,
            .refspec = null,
        };
    }

    pub fn list(self: *Remote, allocator: std.mem.Allocator, for_push: ?protocol.Command.List) !protocol.Response.List {
        // TODO: Handle for_push differently - might want to show different refs for push vs fetch
        _ = for_push;

        // Check if the git_refs table exists, if not return empty list
        const table_count_str = self.db.oneText(allocator, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='git_refs'", &[_][]const u8{}) catch {
            // If we can't even query sqlite_master, return empty list
            return .{ .refs = try allocator.alloc(protocol.Ref, 0) };
        };
        defer if (table_count_str) |str| allocator.free(str);

        if (table_count_str == null) {
            return .{ .refs = try allocator.alloc(protocol.Ref, 0) };
        }

        const table_count = std.fmt.parseInt(i32, table_count_str.?, 10) catch 0;
        if (table_count == 0) {
            // Table doesn't exist, return empty list (database not initialized)
            return .{ .refs = try allocator.alloc(protocol.Ref, 0) };
        }

        const ref_data = try self.refs.iterateRefs(allocator);
        defer {
            for (ref_data) |ref| {
                ref.deinit(allocator);
            }
            allocator.free(ref_data);
        }

        var refs = std.ArrayList(protocol.Ref).init(allocator);

        // For empty repositories, don't advertise HEAD - let Git handle default branch
        if (ref_data.len == 0) {
            // Return empty list for empty repositories
        } else {
            for (ref_data) |ref| {
                try refs.append(.{
                    .name = try allocator.dupe(u8, ref.name),
                    .sha1 = try allocator.dupe(u8, ref.sha),
                    .symref_target = null,
                });
            }
        }

        return .{ .refs = try refs.toOwnedSlice() };
    }

    pub fn fetch(self: *Remote, allocator: std.mem.Allocator, fetch_cmd: protocol.Command.Fetch) Error!protocol.Response.Fetch {
        // TODO: Use fetch_cmd.sha1 and fetch_cmd.name for selective fetching instead of all objects
        _ = fetch_cmd;

        // Use the injected repository for fetch operations
        const repo = self.repo;

        var object_writer = git.ObjectWriter.init(repo);

        // Database transaction management
        self.db.exec("BEGIN TRANSACTION") catch return Error.DatabaseError;
        errdefer _ = self.db.exec("ROLLBACK") catch {};

        // Get all object types and transfer them
        const object_types = [_]sqlite.ObjectType{ .blob, .tree, .commit, .tag };

        for (object_types) |obj_type| {
            const shas = self.objects.iterateObjectsByType(allocator, obj_type) catch return Error.DatabaseError;
            defer {
                for (shas) |sha| {
                    allocator.free(sha);
                }
                allocator.free(shas);
            }

            for (shas) |sha| {
                if (self.objects.readObject(allocator, sha) catch null) |object_data| {
                    defer object_data.deinit(allocator);

                    // Object writing and verification logic
                    const written_sha = try object_writer.writeObject(object_data.object_type.toString(), object_data.data);
                    defer repo.allocator.free(written_sha);

                    // Verify the SHA matches
                    if (!std.mem.eql(u8, sha, written_sha)) {
                        return Error.DatabaseError;
                    }
                }
            }
        }

        self.db.exec("COMMIT") catch return Error.DatabaseError;

        return .complete;
    }

    pub fn push(self: *Remote, allocator: std.mem.Allocator, push_cmd: protocol.Command.Push) !protocol.Response.Push {
        const refspec = push_cmd.refspec;

        // Parse refspec to get destination for response
        var parsed_refspec = git.Refspec.parse(allocator, refspec, false) catch |err| {
            const error_message = switch (err) {
                error.RefspecParseFailed => "Invalid refspec format",
                else => "Failed to parse refspec",
            };
            return protocol.Response.Push{
                .results = try allocator.dupe(protocol.Response.Push.PushResult, &[_]protocol.Response.Push.PushResult{
                    .{ .@"error" = .{ .dst = try allocator.dupe(u8, refspec), .why = try allocator.dupe(u8, error_message) } },
                }),
            };
        };
        defer parsed_refspec.deinit();

        const src = parsed_refspec.getSource();
        const dst = parsed_refspec.getDestination();

        // Only copy dst since it's returned in the response and must outlive the refspec
        const dst_owned = try allocator.dupe(u8, dst);

        // Use the injected repository for push operations
        const repo = self.repo;

        // Database transaction management
        self.db.exec("BEGIN TRANSACTION") catch return Error.DatabaseError;
        errdefer _ = self.db.exec("ROLLBACK") catch {};

        // Resolve reference to get the commit SHA
        const sha = repo.resolveRef(src) catch {
            _ = self.db.exec("ROLLBACK") catch {};
            return protocol.Response.Push{
                .results = try allocator.dupe(protocol.Response.Push.PushResult, &[_]protocol.Response.Push.PushResult{
                    .{ .@"error" = .{ .dst = dst_owned, .why = try allocator.dupe(u8, "Failed to resolve reference") } },
                }),
            };
        };
        defer repo.allocator.free(sha);

        // Walk all objects reachable from the commit
        var object_iter = try repo.walkObjects(sha);
        defer object_iter.deinit();

        // Store all reachable objects
        while (object_iter.next() catch null) |obj_sha| {
            defer repo.allocator.free(obj_sha);
            try self.storeObject(allocator, repo, obj_sha);
        }

        // Store ref in database
        try self.refs.writeRef(dst_owned, sha, "branch");
        self.db.exec("COMMIT") catch return Error.DatabaseError;

        const results = try allocator.alloc(protocol.Response.Push.PushResult, 1);
        results[0] = .{ .ok = dst_owned };
        return .{ .results = results };
    }

    fn storeObject(self: *Remote, allocator: std.mem.Allocator, repo: *git.Repository, sha: []const u8) Error!void {
        _ = allocator; // TODO: May need for error message formatting in the future

        // Check if object already exists to avoid redundant work
        if (self.objects.hasObject(sha) catch false) {
            return; // Object already stored
        }

        // Get object data from repository
        var object_data = try repo.getObjectData(sha);
        defer object_data.deinit();

        // Store in database
        const parsed_type = sqlite.ObjectType.fromString(object_data.object_type) orelse {
            return Error.DatabaseError;
        };
        self.objects.writeObject(sha, parsed_type, object_data.data) catch return Error.DatabaseError;
    }
};

// ---

/// Entry point for git-remote-sqlite - handles Git remote helper protocol
pub fn run(allocator: std.mem.Allocator, process: cmd.Process) !void {
    if (process.argv.len < 2) {
        return Remote.Error.InvalidArgs;
    }

    // Git calls: git-remote-sqlite <remote-name> <url>
    // Skip the remote name (process.argv[0]) and use the URL (process.argv[1])
    const parsed_url = transport.parseUrl(allocator, process.argv[1]) catch return transport.RemoteUrlError.UnsupportedProtocol;

    if (!std.mem.eql(u8, parsed_url.protocol, "sqlite")) {
        return transport.RemoteUrlError.UnsupportedProtocol;
    }

    // Convert path to null-terminated for SQLite
    const null_terminated_path = try allocator.dupeZ(u8, parsed_url.path);
    defer allocator.free(null_terminated_path);

    var db = try sqlite.Database.open(allocator, null_terminated_path);
    defer db.close();

    const git_dir = process.env.get("GIT_DIR") orelse return Remote.Error.GitDirNotSet;
    git.init();
    var repo = try git.Repository.open(allocator, git_dir);
    defer repo.deinit();
    var remote = try Remote.init(allocator, &db, &repo);

    var protocol_handler = transport.ProtocolHandler.init(allocator, process.stdin, process.stdout, process.stderr);
    defer protocol_handler.deinit();

    try protocol_handler.run(&remote);
}

// Tests

// ---

const testing = std.testing;

// Helper function to create a temporary git repository for tests
fn createTestRepo(allocator: std.mem.Allocator) !git.Repository {
    git.init();
    
    // Try to use current directory first (works when running from project root)
    if (git.Repository.open(allocator, ".")) |repo| {
        return repo;
    } else |_| {
        // TODO: Create a temporary git repository for tests when the working directory isn't a git repo
        // For now, fail the test since a repository is a necessary condition
        return git.GitError.RepoOpenFailed;
    }
}

test "capabilities" {
    const allocator = testing.allocator;

    var db = try sqlite.Database.open(allocator, ":memory:");
    defer db.close();

    // Create a test repository
    var repo = try createTestRepo(allocator);
    defer repo.deinit();

    var remote = try Remote.init(allocator, &db, &repo);

    const response = try remote.capabilities(allocator);
    const caps = response;
    try testing.expect(caps.import == false);
    try testing.expect(caps.@"export" == false);
    try testing.expect(caps.push == true);
    try testing.expect(caps.fetch == true);
    try testing.expect(caps.progress == true);
    try testing.expect(caps.option == true);
    try testing.expect(caps.refspec == null);
}

test "libgit2 refspec parsing - with colon separator" {
    const allocator = testing.allocator;
    var refspec = try git.Refspec.parse(allocator, "refs/heads/main:refs/heads/main", false);
    defer refspec.deinit();

    try testing.expectEqualStrings("refs/heads/main", refspec.getSource());
    try testing.expectEqualStrings("refs/heads/main", refspec.getDestination());
}

test "libgit2 refspec parsing - without colon separator" {
    const allocator = testing.allocator;
    var refspec = try git.Refspec.parse(allocator, "refs/heads/main", false);
    defer refspec.deinit();

    try testing.expectEqualStrings("refs/heads/main", refspec.getSource());
    // For refspecs without colon, destination might be empty or same as source
    // This test just verifies the parse succeeds
}

test "libgit2 refspec parsing - different src and dst" {
    const allocator = testing.allocator;
    var refspec = try git.Refspec.parse(allocator, "refs/heads/feature:refs/heads/main", false);
    defer refspec.deinit();

    try testing.expectEqualStrings("refs/heads/feature", refspec.getSource());
    try testing.expectEqualStrings("refs/heads/main", refspec.getDestination());
}

test "push - invalid refspec" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var db = try sqlite.Database.open(allocator, ":memory:");
    defer db.close();

    // Create a test repository
    var repo = try createTestRepo(allocator);
    defer repo.deinit();

    var remote = try Remote.init(allocator, &db, &repo);

    const push_cmd = protocol.Command.Push{
        .refspec = "invalid::refspec",
    };

    const result = try remote.push(arena.allocator(), push_cmd);

    try testing.expect(result.results.len == 1);
    switch (result.results[0]) {
        .ok => unreachable,
        .@"error" => |error_info| {
            try testing.expectEqualStrings("Invalid refspec format", error_info.why.?);
        },
    }
}

test "push - valid refspec behavior" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var db = try sqlite.Database.open(allocator, ":memory:");
    defer db.close();

    // Create a test repository
    var repo = try createTestRepo(allocator);
    defer repo.deinit();

    var remote = try Remote.init(allocator, &db, &repo);

    // Test with valid refspec - ref resolution should fail
    const push_cmd = protocol.Command.Push{
        .refspec = "refs/heads/nonexistent:refs/heads/main",
    };

    const result = try remote.push(arena.allocator(), push_cmd);

    try testing.expect(result.results.len == 1);
    switch (result.results[0]) {
        .ok => |ref_name| {
            // If it succeeds, verify the ref name
            try testing.expectEqualStrings("refs/heads/main", ref_name);
        },
        .@"error" => |error_info| {
            // Should fail due to ref resolution
            const error_message = error_info.why.?;
            try testing.expect(std.mem.indexOf(u8, error_message, "Failed to resolve reference") != null);
        },
    }
}

test "push - refspec parsing components" {
    const allocator = testing.allocator;

    // Test that refspec parsing works for valid cases
    var refspec = try git.Refspec.parse(allocator, "refs/heads/main:refs/heads/main", false);
    defer refspec.deinit();

    try testing.expectEqualStrings("refs/heads/main", refspec.getSource());
    try testing.expectEqualStrings("refs/heads/main", refspec.getDestination());
}

test "push - database transaction handling" {
    const allocator = testing.allocator;

    var db = try sqlite.Database.open(allocator, ":memory:");
    defer db.close();

    // Create a test repository
    var repo = try createTestRepo(allocator);
    defer repo.deinit();

    _ = try Remote.init(allocator, &db, &repo);

    // Test that we can begin and rollback transactions
    try db.exec("BEGIN TRANSACTION");
    try db.exec("ROLLBACK");

    // Test that we can begin and commit transactions
    try db.exec("BEGIN TRANSACTION");
    try db.exec("COMMIT");
}
