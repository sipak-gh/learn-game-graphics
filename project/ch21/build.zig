const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // A software renderer is slow without optimizations, so plain
    // `zig build --release` means `fast`.
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .fast });

    // raylib is only the platform layer: a window, input, and a texture
    // that shows our pixels. It is compiled from source as a dependency.
    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });

    // Zig 0.17 has no @cImport: translate raylib.h into a Zig module.
    const rl = b.addTranslateC(.{
        .root_source_file = raylib_dep.path("src/raylib.h"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "rl", .module = rl.createModule() }},
    });
    mod.linkLibrary(raylib_dep.artifact("raylib"));

    const exe = b.addExecutable(.{ .name = "delve", .root_module = mod });
    b.installArtifact(exe);

    // `zig build run -- ARGS` passes ARGS to delve.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run delve").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
