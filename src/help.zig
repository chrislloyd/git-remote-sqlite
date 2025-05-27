const std = @import("std");
const cmd = @import("cmd.zig");

// ---

pub fn run(allocator: std.mem.Allocator, process: cmd.Process) !void {
    _ = allocator;
    _ = process.argv;
    
    try process.stdout.writeAll(
        \\Usage: git-remote-sqlite <command> [options]
        \\
        \\Commands:
        \\  config <database> [key] [value]   Configure repository settings
        \\    --list                 List all configurations
        \\    --get <key>            Get a specific configuration
        \\    --unset <key>          Remove a configuration
        \\
        \\When symlinked as git-remote-sqlite, it functions as a Git remote helper.
        \\
    );
}
