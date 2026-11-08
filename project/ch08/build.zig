const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addGame(b, target, optimize);
    b.installArtifact(exe);

    // `zig build run -- ARGS` builds, installs, and runs quadfall with ARGS.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run quadfall");
    run_step.dependOn(&run_cmd.step);

    // `zig build test` runs the tests of the plain-Zig parts: the core and
    // the command-line options. It never compiles raylib or opens a window.
    const test_step = b.step("test", "Run the game logic tests");
    const tested = [_][]const u8{ "src/core/root.zig", "src/options.zig" };
    for (tested) |path| {
        const tests = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        }) });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    // `zig build release` builds an optimized game for this machine and one
    // for 64-bit Windows, into zig-out/release/<arch>-<os>/.
    const release_step = b.step("release", "Build release games for this machine and Windows");
    const release_targets = [_]std.Target.Query{ .{}, .{ .cpu_arch = .x86_64, .os_tag = .windows } };
    for (release_targets) |query| {
        const t = b.resolveTargetQuery(query);
        const install = b.addInstallArtifact(addGame(b, t, .ReleaseSafe), .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("release/{t}-{t}", .{ t.result.cpu.arch, t.result.os.tag }) } },
        });
        release_step.dependOn(&install.step);
    }
}

/// The quadfall executable for one target: raylib, the "rl" bindings, the
/// core module, and the platform code in src/.
fn addGame(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    // raylib's own build.zig compiles its C sources into a static library.
    const raylib_dep = b.dependency("raylib", .{ .target = target, .optimize = optimize });
    const raylib = raylib_dep.artifact("raylib");

    // Translate raylib.h into a Zig module. The game imports it as "rl".
    const rl = b.addTranslateC(.{
        .root_source_file = raylib_dep.path("src/raylib.h"),
        .target = target,
        .optimize = optimize,
    });

    // The game logic. It gets no "rl" import, so it cannot use raylib.
    const core = b.createModule(.{
        .root_source_file = b.path("src/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "quadfall",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rl", .module = rl.createModule() },
                .{ .name = "core", .module = core },
            },
        }),
    });
    exe.root_module.linkLibrary(raylib);
    return exe;
}
