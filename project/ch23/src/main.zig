const std = @import("std");
const App = @import("app.zig").App;
const Canvas = @import("canvas.zig").Canvas;
const Options = @import("options.zig").Options;
const usage = @import("options.zig").usage;
const image = @import("image.zig");
const platform = @import("platform.zig");
const Input = @import("input.zig").Input;
const combine = @import("input.zig").combine;
const map_zig = @import("map.zig");
const demo_zig = @import("demo.zig");

/// The size of the software framebuffer, in pixels.
const width = 640;
const height = 400;

/// The simulation advances in fixed steps of 1/60 s, whatever the frame rate.
const tick: f32 = 1.0 / 60.0;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const opts = Options.parse(args[1..]) catch |err| {
        std.debug.print("delve: {t}\n{s}", .{ err, usage });
        return 2;
    };
    if (opts.help) {
        std.debug.print("{s}", .{usage});
        return 0;
    }

    // --demo names a built-in demo or a file. It may say which map it
    // was recorded on.
    var demo: ?demo_zig.Demo = null;
    defer if (demo) |*d| d.deinit(gpa);
    if (opts.demo) |name| {
        const text = demo_zig.builtin.get(name) orelse
            std.Io.Dir.cwd().readFileAlloc(init.io, name, init.arena.allocator(), .limited(16 << 20)) catch |err| {
            std.debug.print("delve: cannot read demo {s}: {t}\n", .{ name, err });
            return 1;
        };
        var line: usize = undefined;
        demo = demo_zig.Demo.parse(gpa, text, &line) catch |err| {
            std.debug.print("{s}:{d}: error: {t}\n", .{ name, line, err });
            return 1;
        };
    }

    // --map names a built-in map or a file.
    const map_name = opts.map orelse if (demo) |d| d.map orelse "cellar" else "cellar";
    const map_text = map_zig.builtin.get(map_name) orelse
        std.Io.Dir.cwd().readFileAlloc(init.io, map_name, init.arena.allocator(), .limited(1 << 20)) catch |err| {
        std.debug.print("delve: cannot read map {s}: {t}\n", .{ map_name, err });
        return 1;
    };
    var where: map_zig.Map.Location = .{};
    const map = map_zig.Map.parseAt(gpa, map_text, &where) catch |err| {
        // The format compilers use, so editors can jump to the spot.
        std.debug.print("{s}:{d}:{d}: error: {t}\n", .{ map_name, where.line, where.column, err });
        return 1;
    };

    var canvas = try Canvas.init(gpa, width, height);
    defer canvas.deinit(gpa);
    var app: App = try .init(gpa, map, width, height);
    defer app.deinit(gpa);
    if (demo) |d| if (d.start) |start| {
        app.player.pos = start.pos;
        app.player.yaw = start.yaw;
        app.player.pitch = start.pitch;
    };
    if (opts.pos) |pos| app.player.pos = pos;
    if (opts.yaw) |deg| app.player.yaw = std.math.degreesToRadians(deg);
    if (opts.pitch) |deg| app.player.pitch = std.math.degreesToRadians(deg);
    if (opts.view) |view| app.view = view;
    if (opts.shading) |shading| app.shading = shading;
    if (opts.filter) |filter| app.filter = filter;
    if (opts.culling) |culling| app.culling = culling;

    var ticker: Ticker = .{
        .pending = .{ .pressed = opts.press },
        .playback = if (demo) |d| .{ .runs = d.runs } else null,
    };
    var recorder: demo_zig.Recorder = .{};
    defer recorder.deinit(gpa);
    // The recording starts where the player is now.
    const start: demo_zig.Start = .{ .pos = app.player.pos, .yaw = app.player.yaw, .pitch = app.player.pitch };
    if (opts.record != null) ticker.recorder = &recorder;

    if (opts.headless) {
        // No window: step and render a fixed number of frames, by default
        // one, or as many as the demo has ticks.
        const frames = opts.frames orelse if (demo) |d| d.tickCount() else 1;
        for (0..frames) |_| {
            ticker.pending.accumulate(opts.hold);
            try ticker.step(gpa, &app);
            app.render(canvas);
        }
    } else {
        try runWindowed(gpa, init.io, &app, canvas, opts, &ticker);
    }

    if (opts.out) |path| try image.save(gpa, init.io, path, canvas);
    if (opts.record) |path| {
        var text: std.Io.Writer.Allocating = .init(gpa);
        defer text.deinit();
        const recorded: demo_zig.Demo = .{ .map = map_name, .start = start, .runs = recorder.runs.items };
        try recorded.write(&text.writer);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = text.written() });
    }
    return 0;
}

/// Where each tick's input comes from: the keyboard and mouse (gathered in
/// `pending`), or a demo while it lasts. With `--record`, every tick's
/// input is also written down.
const Ticker = struct {
    pending: Input,
    playback: ?demo_zig.Playback = null,
    recorder: ?*demo_zig.Recorder = null,

    fn step(t: *Ticker, gpa: std.mem.Allocator, app: *App) !void {
        var input = t.pending.take();
        // --hold and --press still add to a demo's input.
        if (t.playback) |*p| if (p.next()) |recorded| {
            input = combine(recorded, input);
        };
        if (t.recorder) |r| try r.add(gpa, input);
        app.update(input, tick);
    }
};

fn runWindowed(gpa: std.mem.Allocator, io: std.Io, app: *App, canvas: Canvas, opts: Options, ticker: *Ticker) !void {
    var window = platform.Window.open("delve", canvas, opts.scale);
    defer window.close();

    var frame: u32 = 0;
    var lag: f32 = 0;
    while (!window.shouldClose()) : (frame += 1) {
        ticker.pending.accumulate(combine(window.input(), opts.hold));
        if (opts.frames) |n| {
            if (frame == n) break;
            // Scripted runs take exactly one tick per frame, so they are
            // reproducible on any machine.
            try ticker.step(gpa, app);
        } else {
            // Real time: run as many ticks as the elapsed time asks for.
            lag += window.frameTime();
            while (lag >= tick) : (lag -= tick) try ticker.step(gpa, app);
        }
        const before = std.Io.Timestamp.now(io, .awake);
        app.render(canvas);
        // Shown on the next frame: this one is drawn already.
        const ns = before.durationTo(.now(io, .awake)).nanoseconds;
        app.render_ms = @as(f32, @floatFromInt(ns)) / 1e6;
        window.present(canvas);
    }
    if (opts.screenshot) |path| window.screenshot(path);
}

test {
    _ = @import("camera.zig");
    _ = @import("canvas.zig");
    _ = @import("clip.zig");
    _ = @import("demo.zig");
    _ = @import("draw.zig");
    _ = @import("font.zig");
    _ = @import("image.zig");
    _ = @import("input.zig");
    _ = @import("light.zig");
    _ = @import("map.zig");
    _ = @import("maze3d.zig");
    _ = @import("mesh.zig");
    _ = @import("math.zig");
    _ = @import("obj.zig");
    _ = @import("options.zig");
    _ = @import("player.zig");
    _ = @import("raster.zig");
    _ = @import("raycast.zig");
    _ = @import("render3d.zig");
    _ = @import("texture.zig");
    _ = @import("visibility.zig");
    _ = @import("world.zig");
}
