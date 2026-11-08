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

    // --map names a built-in map or a file.
    const map_name = opts.map orelse "cellar";
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
    if (opts.pos) |pos| app.player.pos = pos;
    if (opts.yaw) |deg| app.player.yaw = std.math.degreesToRadians(deg);
    if (opts.pitch) |deg| app.player.pitch = std.math.degreesToRadians(deg);
    if (opts.view) |view| app.view = view;
    if (opts.shading) |shading| app.shading = shading;
    if (opts.filter) |filter| app.filter = filter;

    if (opts.headless) {
        // No window: step and render a fixed number of frames.
        var pending: Input = .{ .pressed = opts.press };
        for (0..opts.frames orelse 1) |_| {
            pending.accumulate(opts.hold);
            app.update(pending.take(), tick);
            app.render(canvas);
        }
    } else {
        runWindowed(&app, canvas, opts);
    }

    if (opts.out) |path| try image.save(gpa, init.io, path, canvas);
    return 0;
}

fn runWindowed(app: *App, canvas: Canvas, opts: Options) void {
    var window = platform.Window.open("delve", canvas, opts.scale);
    defer window.close();

    var frame: u32 = 0;
    var lag: f32 = 0;
    var pending: Input = .{ .pressed = opts.press };
    while (!window.shouldClose()) : (frame += 1) {
        pending.accumulate(combine(window.input(), opts.hold));
        if (opts.frames) |n| {
            if (frame == n) break;
            // Scripted runs take exactly one tick per frame, so they are
            // reproducible on any machine.
            app.update(pending.take(), tick);
        } else {
            // Real time: run as many ticks as the elapsed time asks for.
            lag += window.frameTime();
            while (lag >= tick) : (lag -= tick) app.update(pending.take(), tick);
        }
        app.render(canvas);
        window.present(canvas);
    }
    if (opts.screenshot) |path| window.screenshot(path);
}

test {
    _ = @import("camera.zig");
    _ = @import("canvas.zig");
    _ = @import("clip.zig");
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
    _ = @import("world.zig");
}
