//! What GetMouseDelta reports in the first frames after DisableCursor.
//! Hiding the cursor moves it to the middle of the window, and the first
//! delta includes that jump even though nobody touched the mouse.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 400, "mouse delta");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);
    rl.DisableCursor();

    const sensitivity = 0.003; // radians per pixel, as in the project
    var yaw_raw: f32 = 0;
    var yaw_settled: f32 = 0;
    var settled = false;
    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.BLACK);

        const pos = rl.GetMousePosition();
        const delta = rl.GetMouseDelta();
        yaw_raw += delta.x * sensitivity;
        if (settled) yaw_settled += delta.x * sensitivity;
        settled = true;
        if (demo.frame <= 5) std.debug.print("frame {d}: position ({d:.0}, {d:.0})  delta ({d:.0}, {d:.0})\n", .{ demo.frame, pos.x, pos.y, delta.x, delta.y });
    }
    std.debug.print("yaw from every delta: {d:.1} degrees, skipping the first: {d:.1} degrees\n", .{ std.math.radiansToDegrees(yaw_raw), std.math.radiansToDegrees(yaw_settled) });
}
