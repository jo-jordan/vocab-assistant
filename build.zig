const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vocab_assistant = b.addModule("vocab_assistant", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "vocab-assistant",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "vocab_assistant", .module = vocab_assistant },
            },
        }),
    });
    exe.root_module.linkSystemLibrary("sqlite3", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the vocab assistant");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const lib_tests = b.addTest(.{
        .root_module = vocab_assistant,
    });
    lib_tests.root_module.link_libc = true;
    lib_tests.root_module.linkSystemLibrary("sqlite3", .{});
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.root_module.linkSystemLibrary("sqlite3", .{});
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run project tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
