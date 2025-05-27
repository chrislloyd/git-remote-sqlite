const std = @import("std");
const cli = @import("cli.zig");
const cmd = @import("cmd.zig");

// ---

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const process = cmd.Process{
        .argv = args,
        .stdin = std.io.getStdIn().reader().any(),
        .stdout = std.io.getStdOut().writer().any(),
        .stderr = std.io.getStdErr().writer().any(),
        .env = env,
    };

    try cli.run(allocator, process);
}
