const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_module = b.addModule("benchmark", .{
        .root_source_file = b.path("benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    const skiplist_dep = b.dependency("skiplist", .{ .target = target, .optimize = optimize });
    main_module.addImport("skiplist", skiplist_dep.module("skiplist"));

    const exe = b.addExecutable(.{
        .name = "benchmark",
        .linkage = .static,
        .root_module = main_module,
    });

    b.installArtifact(exe);
}
