const std = @import("std");

comptime {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
    _ = @import("help.zig");
    _ = @import("main.zig");
    _ = @import("protocol.zig");
    _ = @import("remote.zig");
    _ = @import("sqlite.zig");
    _ = @import("transport.zig");
}