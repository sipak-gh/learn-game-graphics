//! A piece that should fall one row per second, simulated for one second
//! of real time on screens with different refresh rates.
const std = @import("std");

pub fn main() void {
    const rates = [_]u32{ 30, 60, 144 };

    std.debug.print("one tick per frame, 1/60 row per tick:\n", .{});
    for (rates) |fps| {
        // The rule assumes 60 frames per second; nothing checks that.
        var rows: f32 = 0;
        for (0..fps) |_| rows += 1.0 / 60.0;
        std.debug.print("  {d:>3} FPS: fell {d:.2} rows\n", .{ fps, rows });
    }

    std.debug.print("variable dt, speed * dt per frame:\n", .{});
    for (rates) |fps| {
        const dt: f32 = 1.0 / @as(f32, @floatFromInt(fps));
        var y: f32 = 0;
        for (0..fps) |_| y += 1.0 * dt;
        // The board moves in whole rows: did the piece reach row 1?
        const whole: i32 = @intFromFloat(@floor(y));
        std.debug.print("  {d:>3} FPS: y = {d:.9}, whole rows = {d}\n", .{ fps, y, whole });
    }
}
