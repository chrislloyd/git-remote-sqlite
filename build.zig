const std = @import("std");
const builtin = @import("builtin");

comptime {
    const expected_zig_version = std.SemanticVersion{
        .major = 0,
        .minor = 14,
        .patch = 0,
    };
    const actual_zig_version = builtin.zig_version;
    if (actual_zig_version.order(expected_zig_version).compare(.lt)) {
        @compileError(std.fmt.comptimePrint(
            "unsupported zig version: expected {}, found {}",
            .{ expected_zig_version, actual_zig_version },
        ));
    }
}

pub fn build(b: *std.Build) void {
    const steps = .{
        .run = b.step("run", "Run git-remote-sqlite"),
        .@"test" = b.step("test", "Run tests"),
        .test_unit = b.step("test:unit", "Run unit tests"),
        .test_integration = b.step("test:integration", "Run integration tests"),
        .release = b.step("release", "Build release archives for all platforms"),
        .repo_db = b.step("repo-db", "Create SQLite database of this repository"),
    };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    build_git_remote_sqlite(b, .{
        .run = steps.run,
        .install = b.getInstallStep(),
    }, .{ .target = target, .optimize = optimize });

    build_test(b, .{ .@"test" = steps.@"test", .test_unit = steps.test_unit, .test_integration = steps.test_integration }, .{ .target = target, .optimize = optimize });

    build_release(b, steps.release, .{ .target = target });
    
    build_repo_database(b, steps.repo_db);
    
    // Add repo database to release step
    steps.release.dependOn(steps.repo_db);
}

fn build_git_remote_sqlite(b: *std.Build, steps: struct {
    run: *std.Build.Step,
    install: *std.Build.Step,
}, options: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) void {
    // Create a module for our main entry point
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    // Create an executable from our module
    const exe = b.addExecutable(.{
        .name = "git-remote-sqlite",
        .root_module = main_mod,
    });

    // Add system library linkage
    exe.linkSystemLibrary("sqlite3");
    exe.linkSystemLibrary("git2");
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    // const run_step = b.step("run", "Run the app");
    steps.run.dependOn(&run_cmd.step);
}

fn build_test(b: *std.Build, steps: struct {
    @"test": *std.Build.Step,
    test_unit: *std.Build.Step,
    test_integration: *std.Build.Step,
}, options: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) void {
    const unit_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const unit = b.addTest(.{
        .root_module = unit_mod,
    });
    unit.linkSystemLibrary("sqlite3");
    unit.linkSystemLibrary("git2");
    unit.linkLibC();

    const run_unit = b.addRunArtifact(unit);
    steps.test_unit.dependOn(&run_unit.step);

    // Integration tests - run the e2e script
    const integration_cmd = b.addSystemCommand(&[_][]const u8{ "bash", "src/e2e.sh", b.getInstallPath(.bin, "git-remote-sqlite") });
    integration_cmd.step.dependOn(b.getInstallStep()); // Ensure binary is built first
    steps.test_integration.dependOn(&integration_cmd.step);

    // Main test step runs both unit and integration tests
    steps.@"test".dependOn(&run_unit.step);
    steps.@"test".dependOn(&integration_cmd.step);
}

fn build_release(b: *std.Build, release_step: *std.Build.Step, options: struct {
    target: std.Build.ResolvedTarget,
}) void {
    // Use the target passed from build()
    const release_target = options.target;
    
    // Determine target triple name based on the actual target
    const triple = blk: {
        const arch = release_target.result.cpu.arch;
        const os = release_target.result.os.tag;
        
        if (arch == .x86_64 and os == .linux) break :blk "x86_64-linux";
        if (arch == .x86_64 and os == .macos) break :blk "x86_64-macos";
        if (arch == .aarch64 and os == .macos) break :blk "aarch64-macos";
        
        // Fallback for other platforms
        break :blk b.fmt("{s}-{s}", .{ @tagName(arch), @tagName(os) });
    };
    
    const release_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = release_target,
        .optimize = .ReleaseSafe,
    });
    const release_exe = b.addExecutable(.{
        .name = "git-remote-sqlite",
        .root_module = release_mod,
    });
    release_exe.linkSystemLibrary("sqlite3");
    release_exe.linkSystemLibrary("git2");
    release_exe.linkLibC();

    // Install to zig-out/bin/{target}/git-remote-sqlite
    const install = b.addInstallArtifact(release_exe, .{
        .dest_dir = .{ .override = .{ .custom = b.fmt("bin/{s}", .{triple}) } },
    });
    
    // Create tar.gz archive
    const tar_cmd = b.addSystemCommand(&[_][]const u8{
        "tar", "-czf",
        b.fmt("{s}/git-remote-sqlite-{s}.tar.gz", .{ b.install_path, triple }),
        "-C", b.fmt("{s}/bin/{s}", .{ b.install_path, triple }),
        "git-remote-sqlite",
    });
    tar_cmd.step.dependOn(&install.step);
    
    release_step.dependOn(&tar_cmd.step);
}

fn build_repo_database(b: *std.Build, repo_db_step: *std.Build.Step) void {
    // Ensure the binary is built first
    repo_db_step.dependOn(b.getInstallStep());
    
    const db_filename = "git-remote-sqlite.db";
    const db_path = b.fmt("{s}/{s}", .{ b.install_path, db_filename });
    
    // Remove existing database if it exists
    const rm_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-f", db_path });
    
    // Script to create the database
    const script = b.fmt(
        \\#!/bin/bash
        \\set -euo pipefail
        \\
        \\# Remove existing database
        \\rm -f {s}
        \\
        \\# Create temp directory
        \\TEMP_DIR=$(mktemp -d)
        \\trap "rm -rf $TEMP_DIR" EXIT
        \\
        \\# Initialize bare repo in temp dir
        \\cd "$TEMP_DIR"
        \\git init --bare
        \\
        \\# Configure the SQLite remote
        \\git remote add sqlite "sqlite://{s}"
        \\
        \\# Push current repo to temp bare repo
        \\cd {s}
        \\git push --mirror "file://$TEMP_DIR"
        \\
        \\# Push from temp repo to SQLite
        \\cd "$TEMP_DIR"
        \\export PATH="{s}/bin:$PATH"
        \\git push --mirror sqlite
        \\
        \\# Verify the database was created
        \\if [ -f "{s}" ]; then
        \\    echo "Repository database created: {s}"
        \\    echo "Database size: $(du -h {s} | cut -f1)"
        \\    echo "Objects: $(sqlite3 {s} 'SELECT COUNT(*) FROM git_objects')"
        \\    echo "Refs: $(sqlite3 {s} 'SELECT COUNT(*) FROM git_refs')"
        \\else
        \\    echo "ERROR: Database was not created"
        \\    exit 1
        \\fi
    , .{ db_path, db_path, b.build_root.path orelse ".", b.install_path, db_path, db_path, db_path, db_path, db_path });
    
    // Write and execute the script
    const script_path = b.fmt("{s}/create-repo-db.sh", .{b.cache_root.path orelse "."});
    const write_script = b.addWriteFile(script_path, script);
    
    const create_db = b.addSystemCommand(&[_][]const u8{ "bash", script_path });
    create_db.step.dependOn(&write_script.step);
    create_db.step.dependOn(&rm_cmd.step);
    
    repo_db_step.dependOn(&create_db.step);
}
