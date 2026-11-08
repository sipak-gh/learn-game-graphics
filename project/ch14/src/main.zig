const std = @import("std");
const App = @import("app.zig").App;
const Canvas = @import("canvas.zig").Canvas;
const Options = @import("options.zig").Options;
const usage = @import("options.zig").usage;
const image = @import("image.zig");
const platform = @import("platform.zig");
const Input = @import("input.zig").Input;
const combine = @import("input.zig").combine;

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

    var canvas = try Canvas.init(gpa, width, height);
    defer canvas.deinit(gpa);
    var app: App = try .init(gpa, width);
    defer app.deinit(gpa);
    if (opts.pos) |pos| app.player.pos = pos;
    if (opts.yaw) |deg| app.player.yaw = std.math.degreesToRadians(deg);

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
    _ = @import("canvas.zig");
    _ = @import("draw.zig");
    _ = @import("font.zig");
    _ = @import("image.zig");
    _ = @import("input.zig");
    _ = @import("map.zig");
    _ = @import("math.zig");
    _ = @import("options.zig");
    _ = @import("player.zig");
    _ = @import("raycast.zig");
    _ = @import("texture.zig");
}
