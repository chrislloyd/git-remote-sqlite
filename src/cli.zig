const std = @import("std");
const config = @import("config.zig");
const remote = @import("remote.zig");
const help = @import("help.zig");
const cmd = @import("cmd.zig");

// ---

pub fn run(allocator: std.mem.Allocator, process: cmd.Process) !void {
    
    // Check if called as git-remote-sqlite (remote helper mode)
    const program_name = std.fs.path.basename(process.argv[0]);
    if (std.mem.endsWith(u8, program_name, "git-remote-sqlite") and process.argv.len >= 3) {
        if (std.mem.indexOf(u8, process.argv[2], "://") != null) {
            const remote_process = cmd.Process{
                .argv = process.argv[1..],
                .stdin = process.stdin,
                .stdout = process.stdout,
                .stderr = process.stderr,
                .env = process.env,
            };
            try remote.run(allocator, remote_process);
            return;
        }
    }

    // ---

    if (process.argv.len < 2) {
        try help.run(allocator, process);
        return;
    }

    const command_str = process.argv[1];
    
    if (std.mem.eql(u8, command_str, "config")) {
        const config_process = cmd.Process{
            .argv = process.argv[2..],
            .stdin = process.stdin,
            .stdout = process.stdout,
            .stderr = process.stderr,
            .env = process.env,
        };
        
        config.run(allocator, config_process) catch |err| {
            try process.stderr.print("Error: {}\n", .{err});
            std.process.exit(1);
        };
    } else {
        try help.run(allocator, process);
    }
}