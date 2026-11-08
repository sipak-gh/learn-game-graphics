//! Simulates one second of a moving block at three frame rates.
//! Moving a fixed amount per frame depends on the frame rate;
//! moving speed * dt does not.
const std = @import("std");

const pixels_per_frame: f32 = 2; // looks like 120 px/s, but only at 60 FPS
const pixels_per_second: f32 = 120;

pub fn main() void {
    const rates = [_]u32{ 30, 60, 144 };
    std.debug.print("{s:>4}  {s:>15}  {s:>15}\n", .{ "fps", "2 px per frame", "120 px/s * dt" });
    for (rates) |fps| {
        const dt = 1.0 / @as(f32, @floatFromInt(fps));
        var per_frame: f32 = 0;
        var per_second: f32 = 0;
        for (0..fps) |_| { // one second of frames
            per_frame += pixels_per_frame;
            per_second += pixels_per_second * dt;
        }
        std.debug.print("{d:>4}  {d:>15.4}  {d:>15.4}\n", .{ fps, per_frame, per_second });
    }
}
