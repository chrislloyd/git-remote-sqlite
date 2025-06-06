const std = @import("std");
const assert = std.debug.assert;
const protocol = @import("protocol.zig");

// ---

pub const RemoteUrlError = error{
    InvalidUrl,
    InvalidPath,
    UnsupportedProtocol,
};

pub const RemoteUrl = struct {
    protocol: []const u8,
    path: []const u8,
};

/// Parse and validate sqlite:// URL, preventing path traversal attacks
pub fn parseUrl(allocator: std.mem.Allocator, url: []const u8) RemoteUrlError!RemoteUrl {
    // Basic length validation
    if (url.len == 0 or url.len > 2048) {
        return RemoteUrlError.InvalidUrl;
    }
    assert(url.len > 0 and url.len <= 2048);

    // Check for null bytes which could cause issues in C code
    if (std.mem.indexOf(u8, url, "\x00") != null) {
        return RemoteUrlError.InvalidUrl;
    }

    // Use standard library parsing
    const parsed = std.Uri.parse(url) catch return RemoteUrlError.InvalidUrl;

    // Validate protocol is exactly "sqlite"
    if (!std.mem.eql(u8, parsed.scheme, "sqlite")) {
        return RemoteUrlError.UnsupportedProtocol;
    }

    // Extract the database path - support two formats:
    // 1. sqlite://db.sqlite (host contains the database filename)
    // 2. sqlite:///path/to/db.sqlite (path contains the database path)
    const path = blk: {
        if (parsed.host) |host_component| {
            if (!parsed.path.isEmpty()) {
                // Reject URLs like sqlite://host/path - ambiguous format
                return RemoteUrlError.InvalidUrl;
            }
            // Host-style: sqlite://test.db
            break :blk host_component.toRawMaybeAlloc(allocator) catch return RemoteUrlError.InvalidPath;
        } else {
            // Path-style: sqlite:///path/to/test.db
            const raw_path = parsed.path.toRawMaybeAlloc(allocator) catch return RemoteUrlError.InvalidPath;
            break :blk raw_path;
        }
    };

    // Basic validation for database paths
    if (path.len == 0 or path.len > 1024 or std.mem.eql(u8, path, "/")) {
        return RemoteUrlError.InvalidPath;
    }

    // Use Zig's built-in path resolution to handle .. components safely
    // This will normalize the path and detect any attempts to escape
    var resolved_components = std.ArrayList([]const u8).init(allocator);
    defer resolved_components.deinit();

    var path_iter = std.fs.path.componentIterator(path) catch return RemoteUrlError.InvalidPath;
    while (path_iter.next()) |component| {
        if (std.mem.eql(u8, component.name, "..")) {
            // Don't allow escaping the current directory context
            if (resolved_components.items.len == 0) {
                return RemoteUrlError.InvalidPath;
            }
            _ = resolved_components.pop();
        } else if (std.mem.eql(u8, component.name, ".")) {
            // Skip current directory references
            continue;
        } else {
            // Reject suspicious components
            if (std.mem.indexOf(u8, component.name, "\x00") != null) {
                return RemoteUrlError.InvalidPath;
            }
            resolved_components.append(component.name) catch return RemoteUrlError.InvalidPath;
        }
    }

    return RemoteUrl{
        .protocol = parsed.scheme,
        .path = path,
    };
}

// ---

pub const ProtocolHandler = struct {
    in: std.io.AnyReader,
    out: std.io.AnyWriter,
    err: std.io.AnyWriter,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, in: std.io.AnyReader, out: std.io.AnyWriter, err: std.io.AnyWriter) ProtocolHandler {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .in = in,
            .out = out,
            .err = err,
        };
    }

    pub fn deinit(self: *ProtocolHandler) void {
        self.arena.deinit();
    }

    /// Run git remote helper protocol loop until EOF
    pub fn run(self: *ProtocolHandler, remote: anytype) error{FatalError}!void {
        defer _ = self.arena.reset(.free_all);

        while (true) {
            defer _ = self.arena.reset(.retain_capacity);

            const cmd = protocol.readCommand(self.arena.allocator(), self.in) catch |err| {
                return self.fatalError("Failed to read command: {}\n", .{err});
            } orelse break; // EOF - exit the loop

            const response = self.dispatch(remote, cmd) catch |err| switch (err) {
                error.FatalError => return error.FatalError,
                else => return self.fatalError("Command failed: {}\n", .{err}),
            };

            response.format("", .{}, self.out) catch |err| switch (err) {
                error.BrokenPipe => {
                    // Git may close the pipe after receiving all data it needs.
                    // This is expected behavior and not an error.
                    break;
                },
                else => return self.fatalError("Failed to write response: {}\n", .{err}),
            };
        }
    }

    fn dispatch(self: *ProtocolHandler, remote: anytype, cmd: protocol.Command) !protocol.Response {
        const allocator = self.arena.allocator();
        return switch (cmd) {
            .capabilities => .{ .capabilities = try remote.capabilities(allocator) },
            .list => |for_push| .{ .list = try remote.list(allocator, for_push) },
            .fetch => |fetch_cmd| .{ .fetch = try remote.fetch(allocator, fetch_cmd) },
            .push => |push_cmd| .{ .push = try remote.push(allocator, push_cmd) },
            .option => |opt| .{ .option = try self.option(opt) },
            .import, .@"export", .connect, .stateless_connect, .get => {
                return self.fatalError("Command '{}' not implemented\n", .{cmd});
            },
        };
    }

    pub fn option(self: *ProtocolHandler, opt: protocol.Command.Option) !protocol.Response.Option {
        _ = self;
        if (std.mem.eql(u8, opt.name, "verbosity")) {
            return .ok;
        } else if (std.mem.eql(u8, opt.name, "progress")) {
            return .unsupported;
        } else if (std.mem.eql(u8, opt.name, "timeout")) {
            return .unsupported;
        } else if (std.mem.eql(u8, opt.name, "depth")) {
            return .unsupported;
        } else {
            return .ok;
        }
    }

    /// Write fatal error to stderr per git-remote-helpers(7) protocol
    fn fatalError(self: *ProtocolHandler, comptime fmt: []const u8, args: anytype) error{FatalError} {
        self.err.print(fmt, args) catch {};
        return error.FatalError;
    }
};

// ---

const testing = std.testing;

// URL parsing tests
test "valid URLs" {
    const allocator = testing.allocator;
    const valid_cases = [_]struct { url: []const u8, expected_path: []const u8 }{
        .{ .url = "sqlite://test.db", .expected_path = "test.db" },
        .{ .url = "sqlite:///tmp/test.db", .expected_path = "/tmp/test.db" },
        .{ .url = "sqlite:///data/app.db", .expected_path = "/data/app.db" },
        .{ .url = "sqlite:test.db", .expected_path = "test.db" },
    };

    for (valid_cases) |case| {
        const result = try parseUrl(allocator, case.url);
        try testing.expectEqualStrings("sqlite", result.protocol);
        try testing.expectEqualStrings(case.expected_path, result.path);
    }
}

test "rejects directory traversal" {
    const allocator = testing.allocator;
    const ambiguous_urls = [_][]const u8{
        "sqlite://../../../etc/passwd", // host + path = ambiguous
        "sqlite://data/../../../root/.ssh/id_rsa", // host + path = ambiguous
        "sqlite://test/../..", // host + path = ambiguous
    };

    const invalid_path_urls = [_][]const u8{
        "sqlite:///../../etc/passwd", // directory traversal in path
        "sqlite:../../etc/passwd", // directory traversal in path without leading /
    };

    for (ambiguous_urls) |url| {
        try testing.expectError(error.InvalidUrl, parseUrl(allocator, url));
    }

    for (invalid_path_urls) |url| {
        try testing.expectError(error.InvalidPath, parseUrl(allocator, url));
    }
}

test "rejects null bytes" {
    const allocator = testing.allocator;
    const null_url = "sqlite://test\x00.db";
    try testing.expectError(error.InvalidUrl, parseUrl(allocator, null_url));
}

test "rejects malformed URLs" {
    const allocator = testing.allocator;
    const invalid_url_cases = [_][]const u8{
        "",
        "sqlite://data/app.db", // ambiguous host+path format
    };

    const unsupported_protocol_cases = [_][]const u8{
        "notasqliteurl://test.db",
        "http://test.db", // wrong protocol
        "ftp://test.db", // wrong protocol
    };

    const invalid_path_cases = [_][]const u8{
        "sqlite:",
        "sqlite:/",
    };

    for (invalid_url_cases) |url| {
        try testing.expectError(error.InvalidUrl, parseUrl(allocator, url));
    }

    for (unsupported_protocol_cases) |url| {
        try testing.expectError(error.UnsupportedProtocol, parseUrl(allocator, url));
    }

    for (invalid_path_cases) |url| {
        try testing.expectError(error.InvalidPath, parseUrl(allocator, url));
    }
}

test "rejects oversized URLs" {
    const allocator = testing.allocator;

    // Create oversized URL
    const long_url = try std.fmt.allocPrint(allocator, "sqlite://{s}", .{"x" ** 2100});
    defer allocator.free(long_url);

    try testing.expectError(error.InvalidUrl, parseUrl(allocator, long_url));
}

// Protocol handler tests
test "ProtocolHandler init and deinit" {
    var input_data = TestReader.init("");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    var err_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();
    defer err_data.deinit();

    var test_output = TestWriter.init(&output_data);
    var test_err = TestWriter.init(&err_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        input_data.reader(),
        test_output.writer(),
        test_err.writer(),
    );
    defer handler.deinit();

    try testing.expect(handler.arena.child_allocator.ptr == testing.allocator.ptr);
}

test "ProtocolHandler dispatch capabilities" {
    var output_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();

    var test_output = TestWriter.init(&output_data);
    var empty_reader = TestReader.init("");

    var handler = ProtocolHandler.init(
        testing.allocator,
        empty_reader.reader(),
        test_output.writer(),
        test_output.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    const response = try handler.dispatch(&mock_remote, .capabilities);

    try testing.expect(response == .capabilities);
    try testing.expect(response.capabilities.import == true);
    try testing.expect(response.capabilities.@"export" == true);
}

test "ProtocolHandler dispatch list" {
    var empty_reader = TestReader.init("");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();

    var test_output = TestWriter.init(&output_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        empty_reader.reader(),
        test_output.writer(),
        test_output.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    const response = try handler.dispatch(&mock_remote, .{ .list = null });

    try testing.expect(response == .list);
    try testing.expect(response.list.refs.len == 0);
}

test "ProtocolHandler dispatch fetch" {
    var empty_reader = TestReader.init("");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();

    var test_output = TestWriter.init(&output_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        empty_reader.reader(),
        test_output.writer(),
        test_output.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    const fetch_cmd = protocol.Command.Fetch{
        .sha1 = "abc123",
        .name = "refs/heads/main",
    };
    const response = try handler.dispatch(&mock_remote, .{ .fetch = fetch_cmd });

    try testing.expect(response == .fetch);
    try testing.expect(response.fetch == .complete);
}

test "ProtocolHandler handles options" {
    var empty_reader = TestReader.init("");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();

    var test_output = TestWriter.init(&output_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        empty_reader.reader(),
        test_output.writer(),
        test_output.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};

    const verbosity_result = try handler.dispatch(&mock_remote, .{ .option = .{ .name = "verbosity", .value = "1" } });
    try testing.expect(verbosity_result.option == .ok);

    const progress_result = try handler.dispatch(&mock_remote, .{ .option = .{ .name = "progress", .value = "true" } });
    try testing.expect(progress_result.option == .unsupported);

    const depth_result = try handler.dispatch(&mock_remote, .{ .option = .{ .name = "depth", .value = "1" } });
    try testing.expect(depth_result.option == .unsupported);

    const unknown_result = try handler.dispatch(&mock_remote, .{ .option = .{ .name = "unknown", .value = "value" } });
    try testing.expect(unknown_result.option == .ok);
}

test "ProtocolHandler handles empty input" {
    var input_data = TestReader.init("");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();

    var test_output = TestWriter.init(&output_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        input_data.reader(),
        test_output.writer(),
        test_output.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    try handler.run(&mock_remote);

    try testing.expectEqual(@as(usize, 0), output_data.items.len);
}

test "ProtocolHandler handles invalid commands" {
    var input_data = TestReader.init("invalid_command\n");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    var error_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();
    defer error_data.deinit();

    var test_output = TestWriter.init(&output_data);
    var test_error = TestWriter.init(&error_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        input_data.reader(),
        test_output.writer(),
        test_error.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    try testing.expectError(error.FatalError, handler.run(&mock_remote));

    // Should have written error message to stderr
    try testing.expect(error_data.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, error_data.items, "Failed to read command") != null);
}

test "ProtocolHandler handles unimplemented commands" {
    var input_data = TestReader.init("import refs/heads/main\n");
    var output_data = std.ArrayList(u8).init(testing.allocator);
    var error_data = std.ArrayList(u8).init(testing.allocator);
    defer output_data.deinit();
    defer error_data.deinit();

    var test_output = TestWriter.init(&output_data);
    var test_error = TestWriter.init(&error_data);

    var handler = ProtocolHandler.init(
        testing.allocator,
        input_data.reader(),
        test_output.writer(),
        test_error.writer(),
    );
    defer handler.deinit();

    var mock_remote = MockRemote{};
    try testing.expectError(error.FatalError, handler.run(&mock_remote));

    try testing.expect(error_data.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, error_data.items, "not implemented") != null);
}

// Test helpers for mocking remote implementations and I/O
const TestWriter = struct {
    data: *std.ArrayList(u8),

    fn init(data: *std.ArrayList(u8)) TestWriter {
        return .{ .data = data };
    }

    fn writer(self: *TestWriter) std.io.AnyWriter {
        return .{
            .context = @ptrCast(self),
            .writeFn = writeFn,
        };
    }

    fn writeFn(context: *const anyopaque, bytes: []const u8) anyerror!usize {
        const self: *TestWriter = @ptrCast(@alignCast(@constCast(context)));
        try self.data.appendSlice(bytes);
        return bytes.len;
    }
};

const TestReader = struct {
    data: []const u8,
    pos: usize = 0,

    fn init(data: []const u8) TestReader {
        return .{ .data = data };
    }

    fn reader(self: *TestReader) std.io.AnyReader {
        return .{
            .context = @ptrCast(self),
            .readFn = readFn,
        };
    }

    fn readFn(context: *const anyopaque, buffer: []u8) anyerror!usize {
        const self: *TestReader = @ptrCast(@alignCast(@constCast(context)));
        if (self.pos >= self.data.len) return 0;
        const available = self.data.len - self.pos;
        const to_read = @min(buffer.len, available);
        @memcpy(buffer[0..to_read], self.data[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return to_read;
    }
};

// Simple mock remote for testing
const MockRemote = struct {
    fn capabilities(_: *MockRemote, _: std.mem.Allocator) !protocol.Response.Capabilities {
        return .{
            .import = true,
            .@"export" = true,
            .push = true,
            .fetch = true,
            .connect = false,
            .progress = true,
            .refspec = null,
            .option = true,
        };
    }

    fn list(_: *MockRemote, _: std.mem.Allocator, _: ?protocol.Command.List) !protocol.Response.List {
        return .{ .refs = &[_]protocol.Ref{} };
    }

    fn fetch(_: *MockRemote, _: std.mem.Allocator, _: protocol.Command.Fetch) !protocol.Response.Fetch {
        return .complete;
    }

    fn push(_: *MockRemote, allocator: std.mem.Allocator, push_cmd: protocol.Command.Push) !protocol.Response.Push {
        const ref_name = try allocator.dupe(u8, push_cmd.refspec);
        const results = try allocator.alloc(protocol.Response.Push.PushResult, 1);
        results[0] = .{ .ok = ref_name };
        return .{ .results = results };
    }
};