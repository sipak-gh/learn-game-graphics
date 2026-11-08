//! A box simulated at only 10 ticks per second, drawn at 60 frames per
//! second. Top: drawn where the last tick left it (it jumps). Bottom: drawn
//! between the last two ticks, `alpha` of the way (it glides). The marks
//! under each box are where it was drawn in the last 30 frames.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const tick_seconds = 1.0 / 10.0;
const speed = 40; // pixels per tick

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 300, "interpolation");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    var x: f32 = 20; // position after the last tick
    var prev_x: f32 = 20; // position after the tick before
    var lag: f32 = 0;
    var trail: [2][30]f32 = @splat(@splat(-100));
    var frame: usize = 0;
    while (demo.running()) : (frame += 1) {
        lag += demo.frameTime();
        while (lag >= tick_seconds) : (lag -= tick_seconds) {
            prev_x = x;
            x += speed;
            if (x > 580) { // wrap around
                x = 20;
                prev_x = 20;
            }
        }
        const alpha = lag / tick_seconds;
        const drawn = [2]f32{ x, prev_x + (x - prev_x) * alpha };
        for (&trail, drawn) |*t, d| t[frame % t.len] = d;

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });
        const labels = [2][:0]const u8{ "no interpolation", "interpolated (alpha = lag / tick)" };
        for (drawn, trail, labels, 0..) |d, t, text, i| {
            const y: i32 = 50 + @as(i32, @intCast(i)) * 130;
            rl.DrawText(text, 20, y - 30, 20, rl.LIGHTGRAY);
            for (t) |tx| rl.DrawRectangle(@intFromFloat(tx + 19), y + 50, 2, 16, rl.Fade(rl.SKYBLUE, 0.6));
            rl.DrawRectangle(@intFromFloat(d), y, 40, 40, rl.ORANGE);
        }
    }
}
