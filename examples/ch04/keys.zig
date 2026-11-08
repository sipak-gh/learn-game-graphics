//! Which arrow keys are down, pressed or released this frame. Run it with a
//! window and press the arrows; a headless run shows every key idle.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const Key = struct { name: [:0]const u8, code: c_int, presses: u32 = 0 };

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 240, "keys");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    var keys = [_]Key{
        .{ .name = "LEFT", .code = rl.KEY_LEFT },
        .{ .name = "RIGHT", .code = rl.KEY_RIGHT },
        .{ .name = "UP", .code = rl.KEY_UP },
        .{ .name = "DOWN", .code = rl.KEY_DOWN },
    };

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.BLACK);
        for (&keys, 0..) |*key, i| {
            const x: i32 = 40 + @as(i32, @intCast(i)) * 150;
            // Down: held now. Pressed: down now, up last frame. Released: the reverse.
            const down = rl.IsKeyDown(key.code);
            const pressed = rl.IsKeyPressed(key.code);
            const released = rl.IsKeyReleased(key.code);
            if (pressed) key.presses += 1;
            rl.DrawRectangle(x, 40, 120, 80, if (down) rl.GREEN else rl.DARKGRAY);
            rl.DrawText(key.name, x + 10, 70, 20, rl.BLACK);
            if (pressed) rl.DrawText("pressed", x, 140, 20, rl.YELLOW);
            if (released) rl.DrawText("released", x, 140, 20, rl.ORANGE);
            var buf: [32]u8 = undefined;
            const text = try std.mem.printSentinel(&buf, "{d} presses", .{key.presses}, 0);
            rl.DrawText(text, x, 180, 20, rl.LIGHTGRAY);
        }
    }
    for (keys) |key| std.debug.print("{s}: {d} presses\n", .{ key.name, key.presses });
}
