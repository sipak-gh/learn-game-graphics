//! rl.Color: four bytes, red, green, blue and alpha (opacity).
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const background: rl.Color = .{ .r = 24, .g = 24, .b = 32, .a = 255 };
const teal: rl.Color = .{ .r = 0, .g = 160, .b = 160, .a = 255 };

fn swatch(x: i32, y: i32, color: rl.Color, label: [:0]const u8) void {
    rl.DrawRectangle(x, y, 80, 60, color);
    rl.DrawText(label, x, y + 66, 10, rl.LIGHTGRAY);
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "colors");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    const darker = rl.ColorBrightness(teal, -0.35);
    const lighter = rl.ColorBrightness(teal, 0.35);
    const faded = rl.Fade(teal, 0.5);
    std.debug.print("teal    {d:>3} {d:>3} {d:>3} {d:>3}\n", .{ teal.r, teal.g, teal.b, teal.a });
    std.debug.print("darker  {d:>3} {d:>3} {d:>3} {d:>3}\n", .{ darker.r, darker.g, darker.b, darker.a });
    std.debug.print("lighter {d:>3} {d:>3} {d:>3} {d:>3}\n", .{ lighter.r, lighter.g, lighter.b, lighter.a });
    std.debug.print("faded   {d:>3} {d:>3} {d:>3} {d:>3}\n", .{ faded.r, faded.g, faded.b, faded.a });

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(background);

        // Named colors from raylib.h.
        swatch(20, 20, rl.RED, "RED");
        swatch(120, 20, rl.ORANGE, "ORANGE");
        swatch(220, 20, rl.GOLD, "GOLD");
        swatch(320, 20, rl.LIME, "LIME");
        swatch(420, 20, rl.SKYBLUE, "SKYBLUE");
        swatch(520, 20, rl.PURPLE, "PURPLE");

        // Our own color and three variations of it.
        swatch(20, 140, teal, "teal (literal)");
        swatch(120, 140, darker, "ColorBrightness -0.35");
        swatch(270, 140, lighter, "ColorBrightness +0.35");
        swatch(420, 140, faded, "Fade 0.5");

        // Alpha blends with what is already drawn: half-transparent white
        // over a maroon bar and over the background.
        rl.DrawRectangle(20, 260, 600, 60, rl.MAROON);
        rl.DrawRectangle(320, 250, 300, 80, rl.Fade(rl.WHITE, 0.5));
    }
}
