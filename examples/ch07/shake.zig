//! Screen shake: move the whole picture with a Camera2D offset that
//! wobbles and dies down. The outline is drawn outside the camera, so it
//! stays put and shows how far the scene moved.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

/// The same formula as quadfall's effects.zig: `t` ticks of shake left.
fn offset(t_left: u32) rl.Vector2 {
    const t: f32 = @floatFromInt(t_left);
    return .{ .x = @sin(t * 2.1) * t * 0.4, .y = @cos(t * 1.7) * t * 0.6 };
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "shake");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    var shake: u32 = 0;
    var tick: u32 = 0;
    while (demo.running()) : (tick += 1) {
        // A "hard drop" every 60 ticks starts 20 ticks of shake.
        shake -|= 1;
        if (tick % 60 == 0) shake = 20;
        const o = offset(shake);
        if (tick < 21 and tick % 4 == 0) std.debug.print("tick {d:>2}: shake {d:>2}, offset ({d:.1}, {d:.1})\n", .{ tick, shake, o.x, o.y });

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });
        {
            const camera: rl.Camera2D = .{ .offset = o, .target = .{}, .rotation = 0, .zoom = 1 };
            rl.BeginMode2D(camera);
            defer rl.EndMode2D();
            rl.DrawRectangle(220, 80, 200, 200, rl.MAROON);
            rl.DrawText("BOOM", 262, 160, 40, rl.RAYWHITE);
        }
        rl.DrawRectangleLines(220, 80, 200, 200, rl.GOLD);
    }
}
