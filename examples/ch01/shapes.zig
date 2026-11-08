//! raylib's basic shapes and text. x grows to the right and y grows DOWN.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "shapes");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    const title = "y grows down";
    const title_width = rl.MeasureText(title, 20);
    std.debug.print("MeasureText(\"{s}\", 20) = {d} px\n", .{ title, title_width });

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.RAYWHITE);

        // The axes: (0,0) is the top-left pixel of the window.
        rl.DrawLine(10, 10, 200, 10, rl.RED); // +x
        rl.DrawLine(10, 10, 10, 200, rl.BLUE); // +y
        rl.DrawText("(0,0)", 16, 16, 10, rl.DARKGRAY);
        rl.DrawText("+x", 205, 4, 10, rl.RED);
        rl.DrawText("+y", 6, 205, 10, rl.BLUE);

        // Filled and outlined rectangles: x, y of the top-left corner, then size.
        rl.DrawRectangle(60, 60, 120, 80, rl.SKYBLUE);
        rl.DrawRectangleLines(60, 160, 120, 80, rl.DARKBLUE);

        // A circle takes its center; a triangle takes points in
        // counter-clockwise order on screen.
        rl.DrawCircle(300, 100, 40, rl.ORANGE);
        rl.DrawTriangle(
            .{ .x = 300, .y = 160 },
            .{ .x = 260, .y = 240 },
            .{ .x = 340, .y = 240 },
            rl.LIME,
        );

        // Center text by measuring it first.
        rl.DrawText(title, @divTrunc(640 - title_width, 2), 300, 20, rl.BLACK);
        rl.DrawText("y = 300", 520, 300, 20, rl.GRAY);
        rl.DrawText("y = 60", 520, 60, 20, rl.GRAY);
    }
}
