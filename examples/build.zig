//! Builds and runs one example program:
//!
//!   zig build run -Dexample=ch01/window
//!   zig build run -Dexample=ch01/window -- --frames 60 --screenshot window.png
//!
//! Every example may import raylib as "rl" and the small headless-run helper
//! in demo.zig as "demo". Examples that need neither also run with `zig run`.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run_step = b.step("run", "Run the example named by -Dexample");

    const name = b.option([]const u8, "example", "Example to build, such as ch01/window") orelse {
        run_step.dependOn(&b.addFail("choose an example: zig build run -Dexample=ch01/window").step);
        return;
    };

    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    const rl = b.addTranslateC(.{
        .root_source_file = raylib_dep.path("src/raylib.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    const demo = b.createModule(.{
        .root_source_file = b.path("demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "rl", .module = rl }},
    });

    const exe = b.addExecutable(.{
        .name = std.fs.path.basename(name),
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rl", .module = rl },
                .{ .name = "demo", .module = demo },
            },
        }),
    });
    exe.root_module.linkLibrary(raylib_dep.artifact("raylib"));
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run_step.dependOn(&run.step);
}
