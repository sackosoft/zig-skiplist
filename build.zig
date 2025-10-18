const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.addModule("skiplist", .{
        .root_source_file = b.path("src/Skiplist.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "skiplist",
        .linkage = .static,
        .root_module = root_module,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = lib.root_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
