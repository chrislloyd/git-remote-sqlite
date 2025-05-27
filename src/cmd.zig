const std = @import("std");

pub const Process = struct {
    argv: []const []const u8,
    stdin: std.io.AnyReader,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    env: std.process.EnvMap,
};
