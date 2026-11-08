//! GetFrameTime: how long the previous frame took, in seconds.
const std = @import("std");
const rl = @import("rl");

pub fn main() void {
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(320, 180, "frame time");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60); // EndDrawing now waits until 1/60 s has passed

    var frame: u32 = 0;
    while (!rl.WindowShouldClose() and frame < 10) : (frame += 1) {
        const dt = rl.GetFrameTime();
        std.debug.print("frame {d}: dt = {d:.3} ms, time = {d:.4} s\n", .{
            frame, dt * 1000, rl.GetTime(),
        });

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.BLACK);
    }
}
