const std = @import("std");
const sqlite = @import("sqlite.zig");
const cmd = @import("cmd.zig");

pub const ConfigError = error{
    InvalidArgs,
    KeyNotFound,
    OutOfMemory,
    DatabaseError,
    AllocationError,
};

// ---

pub fn run(allocator: std.mem.Allocator, process: cmd.Process) !void {
    _ = process.stdin;

    if (process.argv.len < 1) {
        return ConfigError.InvalidArgs;
    }

    const db_path = process.argv[0];
    const null_terminated_path = try allocator.dupeZ(u8, db_path);
    defer allocator.free(null_terminated_path);

    var db = sqlite.Database.open(allocator, null_terminated_path) catch {
        return ConfigError.DatabaseError;
    };
    defer db.close();

    var config_store = sqlite.ConfigDatabase.init(&db) catch {
        return ConfigError.DatabaseError;
    };

    if (process.argv.len == 1) {
        const entries = try config_store.iterateConfig(allocator);
        defer {
            for (entries) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(entries);
        }

        for (entries) |entry| {
            try process.stdout.print("{s}={s}\n", .{ entry.key, entry.value });
        }

        return;
    }

    const subcommand = process.argv[1];
    if (std.mem.eql(u8, subcommand, "--list")) {
        const entries = try config_store.iterateConfig(allocator);
        defer {
            for (entries) |entry| {
                entry.deinit(allocator);
            }
            allocator.free(entries);
        }

        for (entries) |entry| {
            try process.stdout.print("{s}={s}\n", .{ entry.key, entry.value });
        }
    } else if (std.mem.eql(u8, subcommand, "--get")) {
        if (process.argv.len < 3) {
            return ConfigError.InvalidArgs;
        }
        const value = try config_store.readConfig(allocator, process.argv[2]);
        if (value) |v| {
            defer allocator.free(v);
            try process.stdout.print("{s}", .{v});
        } else {
            return ConfigError.KeyNotFound;
        }
    } else if (std.mem.eql(u8, subcommand, "--unset")) {
        if (process.argv.len < 3) {
            return ConfigError.InvalidArgs;
        }
        try config_store.unsetConfig(process.argv[2]);
    } else if (process.argv.len >= 3) {
        try config_store.writeConfig(process.argv[1], process.argv[2]);
    } else {
        return ConfigError.InvalidArgs;
    }
}
