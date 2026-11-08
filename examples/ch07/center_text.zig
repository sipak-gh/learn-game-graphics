//! Centering text with MeasureText: the width in pixels of a string drawn
//! with raylib's default font at a given size.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const width = 640;
const height = 360;

/// Draws `text` so that its middle is at `cx`.
fn centered(text: [:0]const u8, cx: i32, y: i32, size: i32, color: rl.Color) void {
    rl.DrawText(text, cx - @divTrunc(rl.MeasureText(text, size), 2), y, size, color);
}

const lines = [_]struct { text: [:0]const u8, size: i32 }{
    .{ .text = "QUADFALL", .size = 60 },
    .{ .text = "press Enter to start", .size = 30 },
    .{ .text = "HIGH SCORE 214", .size = 20 },
    .{ .text = "a falling-block game", .size = 10 },
};

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(width, height, "center_text");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    // MeasureText needs the font, so call it after InitWindow.
    for (lines) |line| {
        std.debug.print("{s:<22} size {d}: {d} px wide\n", .{ line.text, line.size, rl.MeasureText(line.text, line.size) });
    }

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });
        // The center line: every string is balanced around it.
        rl.DrawLine(width / 2, 0, width / 2, height, rl.DARKGRAY);
        var y: i32 = 40;
        for (lines) |line| {
            centered(line.text, width / 2, y, line.size, rl.RAYWHITE);
            y += line.size + 40;
        }
        // Left-aligned at the same x, for comparison.
        rl.DrawText("not centered", width / 2, height - 30, 20, rl.GOLD);
    }
}
