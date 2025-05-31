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
    };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    build_git_remote_sqlite(b, .{
        .run = steps.run,
        .install = b.getInstallStep(),
    }, .{ .target = target, .optimize = optimize });

    build_test(b, .{ .@"test" = steps.@"test", .test_unit = steps.test_unit, .test_integration = steps.test_integration }, .{ .target = target, .optimize = optimize });
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
