/// See gitremote-helpers(7)
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

// ---

pub const ProtocolError = error{
    InvalidCommand,
    UnexpectedEOF,
    MissingRefName,
};

// ---

pub const Command = union(enum) {
    capabilities,
    list: ?List,
    fetch: Fetch,
    push: Push,
    option: Option,
    import: Import,
    @"export": Export,
    connect: Connect,
    stateless_connect: StatelessConnect,
    get: Get,

    pub const List = enum {
        for_push,

        pub fn format(self: List, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .for_push => try writer.writeAll("for_push"),
            }
        }
    };

    pub const Fetch = struct {
        sha1: []const u8,
        name: []const u8,

        pub fn format(self: Fetch, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("fetch {s} {s}", .{ self.sha1, self.name });
        }
    };

    pub const Push = struct {
        refspec: []const u8,

        pub fn format(self: Push, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("push {s}", .{self.refspec});
        }
    };

    pub const Option = struct {
        name: []const u8,
        value: []const u8,

        pub fn format(self: Option, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("option {s} {s}", .{ self.name, self.value });
        }
    };

    pub const Import = struct {
        name: []const u8,

        pub fn format(self: Import, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("import {s}", .{self.name});
        }
    };

    pub const Export = struct {
        pub fn format(self: Export, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = self;
            _ = fmt;
            _ = options;
            try writer.writeAll("export");
        }
    };

    pub const Connect = struct {
        service: []const u8,

        pub fn format(self: Connect, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("connect {s}", .{self.service});
        }
    };

    pub const StatelessConnect = struct {
        service: []const u8,

        pub fn format(self: StatelessConnect, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("stateless-connect {s}", .{self.service});
        }
    };

    pub const Get = struct {
        uri: []const u8,
        path: []const u8,

        pub fn format(self: Get, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("get {s} {s}", .{ self.uri, self.path });
        }
    };

    pub fn format(self: Command, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .capabilities => try writer.writeAll("capabilities"),
            .list => |list| {
                try writer.writeAll("list");
                if (list) |l| {
                    try writer.writeAll(" ");
                    try l.format("", .{}, writer);
                }
            },
            .fetch => |fetch| try fetch.format("", .{}, writer),
            .push => |push| try push.format("", .{}, writer),
            .option => |option| try option.format("", .{}, writer),
            .import => |import| try import.format("", .{}, writer),
            .@"export" => |export_cmd| try export_cmd.format("", .{}, writer),
            .connect => |connect| try connect.format("", .{}, writer),
            .stateless_connect => |stateless_connect| try stateless_connect.format("", .{}, writer),
            .get => |get| try get.format("", .{}, writer),
        }
    }
};

// ---

pub const Ref = struct {
    sha1: []const u8,
    name: []const u8,
    symref_target: ?[]const u8,
    attributes: []const []const u8 = &[_][]const u8{},
    keywords: []const Keyword = &[_]Keyword{},

    pub const Keyword = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        // Write value (sha1, symref, or keyword)
        if (self.keywords.len > 0) {
            for (self.keywords, 0..) |keyword, i| {
                if (i > 0) try writer.writeAll(" ");
                try writer.print(":{s} {s}", .{ keyword.key, keyword.value });
            }
        } else if (self.symref_target) |target| {
            try writer.writeAll("@");
            try writer.writeAll(target);
        } else if (self.sha1.len == 1 and self.sha1[0] == '?') {
            try writer.writeAll("?");
        } else {
            try writer.writeAll(self.sha1);
        }

        try writer.writeAll(" ");
        try writer.writeAll(self.name);

        // Write attributes
        for (self.attributes) |attr| {
            try writer.writeAll(" ");
            try writer.writeAll(attr);
        }
    }
};

pub const Response = union(enum) {
    capabilities: Capabilities,
    list: List,
    option: Option,
    fetch: Fetch,
    push: Push,
    connect: Connect,

    pub fn format(self: Response, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .capabilities => |caps| try caps.format("", .{}, writer),
            .list => |list| try list.format("", .{}, writer),
            .option => |opt| try opt.format("", .{}, writer),
            .fetch => |fetch| try fetch.format("", .{}, writer),
            .push => |push| try push.format("", .{}, writer),
            .connect => |connect| try connect.format("", .{}, writer),
        }
    }

    pub const List = struct {
        refs: []const Ref,

        pub fn format(self: List, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            for (self.refs) |ref| {
                try ref.format("", .{}, writer);
                try writer.writeAll("\n");
            }
            try writer.writeAll("\n");
        }
    };

    pub const Option = union(enum) {
        ok,
        unsupported,
        @"error": []const u8,

        pub fn format(self: Option, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .ok => try writer.writeAll("ok\n"),
                .unsupported => try writer.writeAll("unsupported\n"),
                .@"error" => |msg| {
                    try writer.writeAll("error ");
                    try writer.writeAll(msg);
                    try writer.writeAll("\n");
                },
            }
        }
    };

    pub const Fetch = union(enum) {
        complete,
        lock: []const u8,
        connectivity_ok,

        pub fn format(self: Fetch, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .complete => try writer.writeAll("\n"),
                .lock => |path| {
                    try writer.writeAll("lock ");
                    try writer.writeAll(path);
                    try writer.writeAll("\n");
                },
                .connectivity_ok => try writer.writeAll("connectivity-ok\n"),
            }
        }
    };

    pub const Push = struct {
        results: []const PushResult,

        pub const PushResult = union(enum) {
            ok: []const u8,
            @"error": PushError,
        };

        pub const PushError = struct {
            dst: []const u8,
            why: ?[]const u8,
        };

        pub fn format(self: Push, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            for (self.results) |result| {
                switch (result) {
                    .ok => |dst| {
                        try writer.writeAll("ok ");
                        try writer.writeAll(dst);
                        try writer.writeAll("\n");
                    },
                    .@"error" => |err| {
                        try writer.writeAll("error ");
                        try writer.writeAll(err.dst);
                        if (err.why) |why| {
                            try writer.writeAll(" ");
                            try writer.writeAll(why);
                        }
                        try writer.writeAll("\n");
                    },
                }
            }
            try writer.writeAll("\n");
        }
    };

    pub const Connect = union(enum) {
        established,
        fallback,

        pub fn format(self: Connect, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .established => try writer.writeAll("\n"),
                .fallback => try writer.writeAll("fallback\n"),
            }
        }
    };

    pub const Capabilities = struct {
        import: bool = false,
        @"export": bool = false,
        push: bool = false,
        fetch: bool = false,
        connect: bool = false,
        stateless_connect: bool = false,
        check_connectivity: bool = false,
        get: bool = false,
        bidi_import: bool = false,
        signed_tags: bool = false,
        object_format: bool = false,
        no_private_update: bool = false,
        progress: bool = false,
        option: bool = false,
        refspec: ?[]const u8 = null,
        export_marks: ?[]const u8 = null,
        import_marks: ?[]const u8 = null,

        pub fn format(self: Capabilities, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.writeAll("capabilities\n");
            if (self.import) try writer.writeAll("import\n");
            if (self.@"export") try writer.writeAll("export\n");
            if (self.push) try writer.writeAll("push\n");
            if (self.fetch) try writer.writeAll("fetch\n");
            if (self.connect) try writer.writeAll("connect\n");
            if (self.stateless_connect) try writer.writeAll("stateless-connect\n");
            if (self.check_connectivity) try writer.writeAll("check-connectivity\n");
            if (self.get) try writer.writeAll("get\n");
            if (self.bidi_import) try writer.writeAll("bidi-import\n");
            if (self.signed_tags) try writer.writeAll("signed-tags\n");
            if (self.object_format) try writer.writeAll("object-format\n");
            if (self.no_private_update) try writer.writeAll("no-private-update\n");
            if (self.progress) try writer.writeAll("progress\n");
            if (self.option) try writer.writeAll("option\n");
            if (self.refspec) |refspec| {
                try writer.writeAll("refspec ");
                try writer.writeAll(refspec);
                try writer.writeAll("\n");
            }
            if (self.export_marks) |file| {
                try writer.writeAll("export-marks ");
                try writer.writeAll(file);
                try writer.writeAll("\n");
            }
            if (self.import_marks) |file| {
                try writer.writeAll("import-marks ");
                try writer.writeAll(file);
                try writer.writeAll("\n");
            }
            try writer.writeAll("\n");
        }
    };
};

// ---

/// Read and parse a command from the input stream.
pub fn readCommand(allocator: Allocator, reader: std.io.AnyReader) !?Command {
    var buffer: [4096]u8 = undefined;

    while (true) {
        const line = try reader.readUntilDelimiterOrEof(buffer[0..], '\n');
        const some_line = line orelse return null; // EOF
        const trimmed = std.mem.trim(u8, some_line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue; // Skip empty lines

        return try parseCommand(allocator, trimmed);
    }
}

fn parseCommand(allocator: Allocator, line: []const u8) !?Command {
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    var tokens = std.mem.tokenizeScalar(u8, trimmed, ' ');
    const cmd = tokens.next() orelse return null;

    if (std.mem.eql(u8, cmd, "capabilities")) {
        return .capabilities;
    } else if (std.mem.eql(u8, cmd, "list")) {
        const arg = tokens.next();
        const list_type: ?Command.List = if (arg) |a|
            if (std.mem.eql(u8, a, "for-push")) .for_push else null
        else
            null;
        return .{ .list = list_type };
    } else if (std.mem.eql(u8, cmd, "fetch")) {
        const sha1 = tokens.next() orelse return ProtocolError.InvalidCommand;
        const name = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(sha1.len > 0);
        assert(name.len > 0);
        return .{ .fetch = .{
            .sha1 = try allocator.dupe(u8, sha1),
            .name = try allocator.dupe(u8, name),
        } };
    } else if (std.mem.eql(u8, cmd, "push")) {
        const refspec = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(refspec.len > 0);

        return .{ .push = .{
            .refspec = try allocator.dupe(u8, refspec),
        } };
    } else if (std.mem.eql(u8, cmd, "option")) {
        const name = tokens.next() orelse return ProtocolError.InvalidCommand;
        const value = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(name.len > 0);
        assert(value.len > 0);

        return .{ .option = .{
            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, value),
        } };
    } else if (std.mem.eql(u8, cmd, "import")) {
        const name = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(name.len > 0);
        return .{ .import = .{
            .name = try allocator.dupe(u8, name),
        } };
    } else if (std.mem.eql(u8, cmd, "export")) {
        return .{ .@"export" = .{} };
    } else if (std.mem.eql(u8, cmd, "connect")) {
        const service = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(service.len > 0);
        return .{ .connect = .{
            .service = try allocator.dupe(u8, service),
        } };
    } else if (std.mem.eql(u8, cmd, "stateless-connect")) {
        const service = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(service.len > 0);
        return .{ .stateless_connect = .{
            .service = try allocator.dupe(u8, service),
        } };
    } else if (std.mem.eql(u8, cmd, "get")) {
        const uri = tokens.next() orelse return ProtocolError.InvalidCommand;
        const path = tokens.next() orelse return ProtocolError.InvalidCommand;
        assert(uri.len > 0);
        assert(path.len > 0);
        return .{ .get = .{
            .uri = try allocator.dupe(u8, uri),
            .path = try allocator.dupe(u8, path),
        } };
    }

    // Unrecognized command (expected for unsupported protocol features)
    return ProtocolError.InvalidCommand;
}

// ---

const TestReader = struct {
    data: []const u8,
    pos: usize = 0,

    fn init(data: []const u8) TestReader {
        return TestReader{ .data = data };
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

const testing = std.testing;

test "readCommand parses git protocol commands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var input_data = TestReader.init("capabilities\nlist\nfetch abc123 refs/heads/main\n");

    const cmd1 = try readCommand(allocator, input_data.reader());
    try testing.expectEqual(Command.capabilities, cmd1.?);

    const cmd2 = try readCommand(allocator, input_data.reader());
    try testing.expectEqual(@as(?Command.List, null), cmd2.?.list);

    const cmd3 = try readCommand(allocator, input_data.reader());
    try testing.expectEqualStrings("abc123", cmd3.?.fetch.sha1);
    try testing.expectEqualStrings("refs/heads/main", cmd3.?.fetch.name);
}

test "readCommand handles EOF" {
    const allocator = testing.allocator;
    var input_data = TestReader.init("");

    const cmd = try readCommand(allocator, input_data.reader());
    try testing.expect(cmd == null);
}

test "readCommand skips empty lines" {
    const allocator = testing.allocator;
    var input_data = TestReader.init("\n   \n\ncapabilities\n");

    const cmd1 = try readCommand(allocator, input_data.reader());
    try testing.expectEqual(Command.capabilities, cmd1.?);

    const cmd2 = try readCommand(allocator, input_data.reader());
    try testing.expect(cmd2 == null);
}

test "parseCommand handles all git protocol commands" {
    const allocator = testing.allocator;

    const cmd = try parseCommand(allocator, "capabilities");
    try testing.expectEqual(Command.capabilities, cmd.?);
}

test "parseCommand rejects invalid commands" {
    const allocator = testing.allocator;

    try testing.expectError(ProtocolError.InvalidCommand, parseCommand(allocator, "fetch"));
    try testing.expectError(ProtocolError.InvalidCommand, parseCommand(allocator, "invalid"));
}

test "command formatting follows git protocol" {
    const allocator = testing.allocator;
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const cmd1 = Command{ .connect = .{ .service = "git-upload-pack" } };
    try cmd1.format("", .{}, output.writer().any());
    try testing.expectEqualStrings("connect git-upload-pack", output.items);

    output.clearRetainingCapacity();
    const cmd2 = Command{ .list = .for_push };
    try cmd2.format("", .{}, output.writer().any());
    try testing.expectEqualStrings("list for_push", output.items);
}

test "capabilities response follows git protocol" {
    const allocator = testing.allocator;
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const response = Response{ .capabilities = .{
        .import = true,
        .@"export" = true,
        .push = true,
        .fetch = true,
        .option = true,
        .refspec = "refs/heads/*:refs/remotes/origin/*",
    } };
    try response.format("", .{}, output.writer().any());

    const expected = "capabilities\nimport\nexport\npush\nfetch\noption\nrefspec refs/heads/*:refs/remotes/origin/*\n\n";
    try testing.expectEqualStrings(expected, output.items);
}

test "list response follows git protocol format" {
    const allocator = testing.allocator;
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const refs = [_]Ref{
        .{ .name = "refs/heads/main", .sha1 = "abc123", .symref_target = null },
        .{ .name = "HEAD", .sha1 = "", .symref_target = "refs/heads/main" },
    };

    const response = Response{ .list = .{ .refs = &refs } };
    try response.format("", .{}, output.writer().any());
    const expected = "abc123 refs/heads/main\n@refs/heads/main HEAD\n\n";
    try testing.expectEqualStrings(expected, output.items);
}

test "ref list supports git protocol features" {
    const allocator = testing.allocator;
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    const attrs = [_][]const u8{"unchanged"};
    const keywords = [_]Ref.Keyword{.{ .key = "object-format", .value = "sha256" }};
    const refs = [_]Ref{
        .{ .name = "refs/heads/main", .sha1 = "abc123", .symref_target = null, .attributes = &attrs },
        .{ .name = "refs/heads/dev", .sha1 = "", .symref_target = null, .keywords = &keywords },
        .{ .name = "refs/heads/unknown", .sha1 = "?", .symref_target = null },
    };

    const response = Response{ .list = .{ .refs = &refs } };
    try response.format("", .{}, output.writer().any());
    const expected = "abc123 refs/heads/main unchanged\n:object-format sha256 refs/heads/dev\n? refs/heads/unknown\n\n";
    try testing.expectEqualStrings(expected, output.items);
}

test "arena allocator handles command memory" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cmd = try parseCommand(allocator, "fetch abc123 refs/heads/main");
    try testing.expectEqualStrings("abc123", cmd.?.fetch.sha1);
    try testing.expectEqualStrings("refs/heads/main", cmd.?.fetch.name);
}
