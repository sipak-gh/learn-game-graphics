const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "window");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.DARKBLUE);
        rl.DrawText("Hello, raylib!", 200, 160, 30, rl.RAYWHITE);
    }
    std.debug.print("ran {d} frames\n", .{demo.frame});
}
