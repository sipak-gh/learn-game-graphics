//! Animation from a tick counter: blinking and bobbing. The same tick
//! always gives the same picture, so a screenshot at frame N is repeatable.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

/// On for 30 ticks (half a second), off for 30.
fn blink(ticks: u32) bool {
    return ticks / 30 % 2 == 0;
}

/// Up to 8 px up or down; box `i` runs a little behind box `i - 1`.
fn bob(ticks: u32, i: usize) i32 {
    const phase = @as(f32, @floatFromInt(ticks)) / 20 - @as(f32, @floatFromInt(i)) * 0.6;
    return @intFromFloat(@sin(phase) * 8);
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "blink_bob");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    for ([_]u32{ 0, 29, 30, 59, 60 }) |t| std.debug.print("tick {d:>2}: blink {}\n", .{ t, blink(t) });
    std.debug.print("bob at tick 20:", .{});
    for (0..7) |i| std.debug.print(" {d}", .{bob(20, i)});
    std.debug.print("\n", .{});

    var ticks: u32 = 0;
    while (demo.running()) : (ticks += 1) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });
        for (0..7) |i| {
            const x = 75 + @as(i32, @intCast(i)) * 75;
            const hue = @as(f32, @floatFromInt(i)) * 50;
            rl.DrawRectangle(x, 120 + bob(ticks, i), 40, 40, rl.ColorFromHSV(hue, 0.7, 0.9));
        }
        if (blink(ticks)) rl.DrawText("press Enter to start", 170, 240, 30, rl.GOLD);
    }
    std.debug.print("drew {d} frames\n", .{ticks});
}
