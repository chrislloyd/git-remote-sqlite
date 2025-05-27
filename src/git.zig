const std = @import("std");
const assert = std.debug.assert;

// ---

pub const c = @cImport({
    @cInclude("git2.h");
});

comptime {
    const expected_git2_version = std.SemanticVersion{
        .major = 1,
        .minor = 0,
        .patch = 0,
    };
    const actual_git2_version = std.SemanticVersion{
        .major = c.LIBGIT2_VER_MAJOR,
        .minor = c.LIBGIT2_VER_MINOR,
        .patch = c.LIBGIT2_VER_PATCH,
    };
    if (actual_git2_version.order(expected_git2_version).compare(.lt)) {
        @compileError(std.fmt.comptimePrint("unsupported git2 version: expected {}, found {}", .{ expected_git2_version, actual_git2_version }));
    }
}

// ---

pub const GitError = error{
    InitFailed,
    RepoOpenFailed,
    RefResolveFailed,
    ObjectLookupFailed,
    RevwalkFailed,
    ObjectReadFailed,
    InvalidObjectType,
    RefspecParseFailed,
    OutOfMemory,
};

// ---

fn initLibgit2() void {
    if (c.git_libgit2_init() < 0) {
        std.debug.panic("Failed to initialize libgit2", .{});
    }
}

var git2_init = std.once(initLibgit2);

pub fn init() void {
    git2_init.call();
}

// ---

pub const RawRepository = struct {
    repo: *c.git_repository,

    pub fn open(path: [:0]const u8) GitError!RawRepository {
        var repo: ?*c.git_repository = null;
        if (c.git_repository_open(&repo, path.ptr) < 0) {
            return GitError.RepoOpenFailed;
        }
        return RawRepository{ .repo = repo.? };
    }

    pub fn deinit(self: *RawRepository) void {
        c.git_repository_free(self.repo);
    }

    pub fn getOdb(self: *RawRepository) GitError!*c.git_odb {
        var odb: ?*c.git_odb = null;
        if (c.git_repository_odb(&odb, self.repo) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return odb.?;
    }
};

pub const RawOid = struct {
    oid: c.git_oid,

    pub fn fromStr(oid_str: []const u8) GitError!RawOid {
        assert(oid_str.len == 40);
        var oid: c.git_oid = undefined;
        if (c.git_oid_fromstr(&oid, oid_str.ptr) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return RawOid{ .oid = oid };
    }

    pub fn toString(self: *const RawOid, buf: *[41]u8) void {
        _ = c.git_oid_tostr(buf, buf.len, &self.oid);
    }
};

pub const RawOdbObject = struct {
    obj: *c.git_odb_object,

    pub fn read(odb: *c.git_odb, oid: *const RawOid) GitError!RawOdbObject {
        var obj: ?*c.git_odb_object = null;
        if (c.git_odb_read(&obj, odb, &oid.oid) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return RawOdbObject{ .obj = obj.? };
    }

    pub fn deinit(self: *RawOdbObject) void {
        c.git_odb_object_free(self.obj);
    }

    pub fn getData(self: *const RawOdbObject) []const u8 {
        const data = c.git_odb_object_data(self.obj);
        const size = c.git_odb_object_size(self.obj);
        return @as([*]const u8, @ptrCast(data))[0..size];
    }

    pub fn getType(self: *const RawOdbObject) []const u8 {
        return switch (c.git_odb_object_type(self.obj)) {
            c.GIT_OBJECT_BLOB => "blob",
            c.GIT_OBJECT_TREE => "tree",
            c.GIT_OBJECT_COMMIT => "commit",
            c.GIT_OBJECT_TAG => "tag",
            else => "unknown",
        };
    }
};

pub const RawRevwalk = struct {
    walker: *c.git_revwalk,

    pub fn new(repo: *RawRepository) GitError!RawRevwalk {
        var walker: ?*c.git_revwalk = null;
        if (c.git_revwalk_new(&walker, repo.repo) < 0) {
            return GitError.RevwalkFailed;
        }
        return RawRevwalk{ .walker = walker.? };
    }

    pub fn deinit(self: *RawRevwalk) void {
        c.git_revwalk_free(self.walker);
    }

    pub fn push(self: *RawRevwalk, oid: *const RawOid) GitError!void {
        if (c.git_revwalk_push(self.walker, &oid.oid) < 0) {
            return GitError.RevwalkFailed;
        }
    }

    pub fn next(self: *RawRevwalk) ?RawOid {
        var oid: c.git_oid = undefined;
        if (c.git_revwalk_next(&oid, self.walker) == 0) {
            return RawOid{ .oid = oid };
        }
        return null;
    }
};

pub const RawCommit = struct {
    commit: *c.git_commit,

    pub fn lookup(repo: *RawRepository, oid: *const RawOid) GitError!RawCommit {
        var commit: ?*c.git_commit = null;
        if (c.git_commit_lookup(&commit, repo.repo, &oid.oid) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return RawCommit{ .commit = commit.? };
    }

    pub fn deinit(self: *RawCommit) void {
        c.git_commit_free(self.commit);
    }

    pub fn getTree(self: *RawCommit) GitError!RawTree {
        var tree: ?*c.git_tree = null;
        if (c.git_commit_tree(&tree, self.commit) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return RawTree{ .tree = tree.? };
    }
};

pub const RawTree = struct {
    tree: *c.git_tree,

    pub fn lookup(repo: *RawRepository, oid: *const RawOid) GitError!RawTree {
        var tree: ?*c.git_tree = null;
        if (c.git_tree_lookup(&tree, repo.repo, &oid.oid) < 0) {
            return GitError.ObjectLookupFailed;
        }
        return RawTree{ .tree = tree.? };
    }

    pub fn deinit(self: *RawTree) void {
        c.git_tree_free(self.tree);
    }

    pub fn getId(self: *const RawTree) RawOid {
        const oid = c.git_tree_id(self.tree);
        return RawOid{ .oid = oid.* };
    }

    pub fn entryCount(self: *const RawTree) usize {
        return c.git_tree_entrycount(self.tree);
    }

    pub fn getEntryByIndex(self: *const RawTree, index: usize) ?RawTreeEntry {
        if (c.git_tree_entry_byindex(self.tree, index)) |entry| {
            return RawTreeEntry{ .entry = entry };
        }
        return null;
    }
};

pub const RawTreeEntry = struct {
    entry: *const c.git_tree_entry,

    pub fn getId(self: *const RawTreeEntry) RawOid {
        const oid = c.git_tree_entry_id(self.entry);
        return RawOid{ .oid = oid.* };
    }

    pub fn getType(self: *const RawTreeEntry) c_int {
        return c.git_tree_entry_type(self.entry);
    }

    pub fn isTree(self: *const RawTreeEntry) bool {
        return self.getType() == c.GIT_OBJECT_TREE;
    }
};

pub const RawRefspec = struct {
    refspec: *c.git_refspec,

    pub fn parse(refspec_str: [:0]const u8, is_fetch: bool) GitError!RawRefspec {
        var refspec: ?*c.git_refspec = null;
        const direction = if (is_fetch) c.GIT_DIRECTION_FETCH else c.GIT_DIRECTION_PUSH;
        if (c.git_refspec_parse(&refspec, refspec_str.ptr, direction) < 0) {
            return GitError.RefspecParseFailed;
        }
        return RawRefspec{ .refspec = refspec.? };
    }

    pub fn deinit(self: *RawRefspec) void {
        c.git_refspec_free(self.refspec);
    }

    pub fn getSource(self: *const RawRefspec) []const u8 {
        const src_ptr = c.git_refspec_src(self.refspec);
        return std.mem.span(src_ptr);
    }

    pub fn getDestination(self: *const RawRefspec) []const u8 {
        const dst_ptr = c.git_refspec_dst(self.refspec);
        return std.mem.span(dst_ptr);
    }

    pub fn isForce(self: *const RawRefspec) bool {
        return c.git_refspec_force(self.refspec) != 0;
    }

    pub fn srcMatches(self: *const RawRefspec, ref_name: [:0]const u8) bool {
        return c.git_refspec_src_matches(self.refspec, ref_name.ptr) != 0;
    }

    pub fn dstMatches(self: *const RawRefspec, ref_name: [:0]const u8) bool {
        return c.git_refspec_dst_matches(self.refspec, ref_name.ptr) != 0;
    }
};

pub fn resolveRefRaw(repo: *RawRepository, ref_name: [:0]const u8) GitError!RawOid {
    var oid: c.git_oid = undefined;
    if (c.git_reference_name_to_id(&oid, repo.repo, ref_name.ptr) < 0) {
        return GitError.RefResolveFailed;
    }
    return RawOid{ .oid = oid };
}

pub fn writeObjectRaw(repo: *RawRepository, obj_type: []const u8, data: []const u8) GitError!RawOid {
    const odb = repo.getOdb() catch return GitError.ObjectReadFailed;
    defer c.git_odb_free(odb);

    const type_id = if (std.mem.eql(u8, obj_type, "commit"))
        c.GIT_OBJECT_COMMIT
    else if (std.mem.eql(u8, obj_type, "tree"))
        c.GIT_OBJECT_TREE
    else if (std.mem.eql(u8, obj_type, "blob"))
        c.GIT_OBJECT_BLOB
    else if (std.mem.eql(u8, obj_type, "tag"))
        c.GIT_OBJECT_TAG
    else
        return GitError.InvalidObjectType;

    var oid: c.git_oid = undefined;
    if (c.git_odb_write(&oid, odb, data.ptr, data.len, type_id) < 0) {
        return GitError.ObjectReadFailed;
    }

    return RawOid{ .oid = oid };
}

// ---

pub const Repository = struct {
    raw: RawRepository,
    allocator: std.mem.Allocator,

    pub fn open(allocator: std.mem.Allocator, path: []const u8) GitError!Repository {
        assert(path.len > 0);
        const null_path = allocator.dupeZ(u8, path) catch return GitError.RepoOpenFailed;
        defer allocator.free(null_path);

        const raw = try RawRepository.open(null_path);
        return Repository{
            .raw = raw,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Repository) void {
        self.raw.deinit();
    }

    pub fn resolveRef(self: *Repository, ref_name: []const u8) GitError![]const u8 {
        assert(ref_name.len > 0);
        const null_ref = self.allocator.dupeZ(u8, ref_name) catch return GitError.RefResolveFailed;
        defer self.allocator.free(null_ref);

        const oid = try resolveRefRaw(&self.raw, null_ref);
        var oid_str: [41]u8 = undefined;
        oid.toString(&oid_str);
        return self.allocator.dupe(u8, oid_str[0..40]) catch return GitError.RefResolveFailed;
    }

    pub fn getObjectData(self: *Repository, oid_str: []const u8) GitError!ObjectData {
        assert(oid_str.len == 40);
        const oid = try RawOid.fromStr(oid_str);
        const odb = try self.raw.getOdb();
        defer c.git_odb_free(odb);

        var raw_obj = try RawOdbObject.read(odb, &oid);
        defer raw_obj.deinit();

        const data = self.allocator.dupe(u8, raw_obj.getData()) catch return GitError.ObjectReadFailed;
        return ObjectData{
            .data = data,
            .object_type = raw_obj.getType(),
            .oid = oid_str,
            .allocator = self.allocator,
        };
    }

    pub fn walkObjects(self: *Repository, start_oid: []const u8) GitError!ObjectIterator {
        return ObjectIterator.init(self.allocator, &self.raw, start_oid);
    }
};

pub const ObjectData = struct {
    data: []const u8,
    object_type: []const u8,
    oid: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ObjectData) void {
        self.allocator.free(self.data);
    }
};

pub const ObjectWriter = struct {
    repo: *Repository,

    pub fn init(repo: *Repository) ObjectWriter {
        return ObjectWriter{ .repo = repo };
    }

    pub fn writeObject(self: *ObjectWriter, obj_type: []const u8, data: []const u8) GitError![]const u8 {
        const oid = try writeObjectRaw(&self.repo.raw, obj_type, data);
        var oid_str: [41]u8 = undefined;
        oid.toString(&oid_str);
        return self.repo.allocator.dupe(u8, oid_str[0..40]) catch return GitError.ObjectReadFailed;
    }
};

pub const Refspec = struct {
    raw: RawRefspec,
    allocator: std.mem.Allocator,

    pub fn parse(allocator: std.mem.Allocator, refspec_str: []const u8, is_fetch: bool) GitError!Refspec {
        assert(refspec_str.len > 0);
        const null_refspec = allocator.dupeZ(u8, refspec_str) catch return GitError.RefspecParseFailed;
        defer allocator.free(null_refspec);

        const raw = try RawRefspec.parse(null_refspec, is_fetch);
        return Refspec{
            .raw = raw,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Refspec) void {
        self.raw.deinit();
    }

    pub fn getSource(self: *const Refspec) []const u8 {
        return self.raw.getSource();
    }

    pub fn getDestination(self: *const Refspec) []const u8 {
        return self.raw.getDestination();
    }

    pub fn isForce(self: *const Refspec) bool {
        return self.raw.isForce();
    }

    pub fn srcMatches(self: *const Refspec, ref_name: []const u8) bool {
        assert(ref_name.len > 0);
        const null_ref = self.allocator.dupeZ(u8, ref_name) catch return false;
        defer self.allocator.free(null_ref);
        return self.raw.srcMatches(null_ref);
    }

    pub fn dstMatches(self: *const Refspec, ref_name: []const u8) bool {
        assert(ref_name.len > 0);
        const null_ref = self.allocator.dupeZ(u8, ref_name) catch return false;
        defer self.allocator.free(null_ref);
        return self.raw.dstMatches(null_ref);
    }
};

pub const ObjectIterator = struct {
    allocator: std.mem.Allocator,
    repo: *RawRepository,
    visited: std.StringHashMap(void),
    pending: std.ArrayList(PendingObject),
    revwalk: ?RawRevwalk,
    current_commit: ?RawOid,
    current_tree_stack: std.ArrayList(TreeContext),

    const PendingObject = struct {
        oid: RawOid,
        source: enum { commit, tree_root, tree_entry },
    };

    const TreeContext = struct {
        tree: RawTree,
        index: usize,
    };

    pub fn init(allocator: std.mem.Allocator, repo: *RawRepository, start_oid: []const u8) GitError!ObjectIterator {
        assert(start_oid.len == 40);
        const oid = try RawOid.fromStr(start_oid);
        var revwalk = try RawRevwalk.new(repo);
        try revwalk.push(&oid);

        return ObjectIterator{
            .allocator = allocator,
            .repo = repo,
            .visited = std.StringHashMap(void).init(allocator),
            .pending = std.ArrayList(PendingObject).init(allocator),
            .revwalk = revwalk,
            .current_commit = null,
            .current_tree_stack = std.ArrayList(TreeContext).init(allocator),
        };
    }

    pub fn deinit(self: *ObjectIterator) void {
        var iterator = self.visited.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.visited.deinit();
        self.pending.deinit();

        if (self.revwalk) |*rw| {
            rw.deinit();
        }

        for (self.current_tree_stack.items) |*ctx| {
            ctx.tree.deinit();
        }
        self.current_tree_stack.deinit();
    }

    pub fn next(self: *ObjectIterator) GitError!?[]const u8 {
        while (true) {
            if (self.pending.items.len > 0) {
                const pending = self.pending.pop() orelse unreachable;
                var oid_str: [41]u8 = undefined;
                pending.oid.toString(&oid_str);

                if (try self.addIfNew(oid_str[0..40])) {
                    switch (pending.source) {
                        .commit => try self.queueCommitObjects(&pending.oid),
                        .tree_root, .tree_entry => try self.queueTreeObjects(&pending.oid),
                    }
                    return self.allocator.dupe(u8, oid_str[0..40]) catch return GitError.RevwalkFailed;
                }
                continue;
            }

            if (self.current_tree_stack.items.len > 0) {
                if (try self.processCurrentTree()) {
                    continue;
                }
            }

            if (self.revwalk) |*rw| {
                if (rw.next()) |commit_oid| {
                    try self.pending.append(.{ .oid = commit_oid, .source = .commit });
                    continue;
                }
            }

            return null;
        }
    }

    fn addIfNew(self: *ObjectIterator, oid_str: []const u8) GitError!bool {
        if (self.visited.contains(oid_str)) {
            return false;
        }
        const owned_oid = self.allocator.dupe(u8, oid_str) catch return GitError.RevwalkFailed;
        self.visited.put(owned_oid, {}) catch {
            self.allocator.free(owned_oid);
            return GitError.RevwalkFailed;
        };
        return true;
    }

    fn queueCommitObjects(self: *ObjectIterator, commit_oid: *const RawOid) GitError!void {
        var commit = RawCommit.lookup(self.repo, commit_oid) catch return;
        defer commit.deinit();

        const tree = commit.getTree() catch return;
        const tree_oid = tree.getId();
        try self.pending.append(.{ .oid = tree_oid, .source = .tree_root });

        try self.current_tree_stack.append(.{ .tree = tree, .index = 0 });
    }

    fn queueTreeObjects(self: *ObjectIterator, tree_oid: *const RawOid) GitError!void {
        const tree = RawTree.lookup(self.repo, tree_oid) catch return;
        try self.current_tree_stack.append(.{ .tree = tree, .index = 0 });
    }

    fn processCurrentTree(self: *ObjectIterator) GitError!bool {
        while (self.current_tree_stack.items.len > 0) {
            const stack_top = &self.current_tree_stack.items[self.current_tree_stack.items.len - 1];
            const tree = &stack_top.tree;

            if (stack_top.index >= tree.entryCount()) {
                var ctx = self.current_tree_stack.pop() orelse unreachable;
                ctx.tree.deinit();
                continue;
            }

            if (tree.getEntryByIndex(stack_top.index)) |entry| {
                stack_top.index += 1;
                const entry_oid = entry.getId();

                if (entry.isTree()) {
                    try self.pending.append(.{ .oid = entry_oid, .source = .tree_entry });
                } else {
                    try self.pending.append(.{ .oid = entry_oid, .source = .tree_entry });
                }
                return true;
            }
            stack_top.index += 1;
        }
        return false;
    }
};

// ---

const testing = std.testing;

test "ObjectIterator deduplication" {
    const allocator = testing.allocator;

    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var iterator = visited.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }

    var iter = ObjectIterator{
        .allocator = allocator,
        .repo = undefined,
        .visited = visited,
        .pending = std.ArrayList(ObjectIterator.PendingObject).init(allocator),
        .revwalk = null,
        .current_commit = null,
        .current_tree_stack = std.ArrayList(ObjectIterator.TreeContext).init(allocator),
    };
    defer {
        iter.pending.deinit();
        iter.current_tree_stack.deinit();
    }

    const test_oid = "1234567890abcdef1234567890abcdef12345678";

    try testing.expect(try iter.addIfNew(test_oid));
    try testing.expect(iter.visited.count() == 1);

    try testing.expect(!(try iter.addIfNew(test_oid)));
    try testing.expect(iter.visited.count() == 1);

    const test_oid2 = "abcdef1234567890abcdef1234567890abcdef12";
    try testing.expect(try iter.addIfNew(test_oid2));
    try testing.expect(iter.visited.count() == 2);

    iter.deinit();
}
