//! Floor casting on a 640x400 screen: the floor distance seen by each
//! pixel row below the horizon, and how far across the floor one pixel
//! step moves. Above 1 texel per pixel, nearest sampling skips texels.
const std = @import("std");

pub fn main() void {
    const w: f32 = 640;
    const h: f32 = 400;
    const plane_len: f32 = 0.8;
    std.debug.print("row  below  distance  floor units/pixel  texels/pixel\n", .{});
    for ([_]u32{ 200, 201, 202, 205, 210, 220, 240, 280, 320, 360, 399 }) |y| {
        // How far below the horizon this row's pixel center is.
        const below = @as(f32, @floatFromInt(y)) + 0.5 - h / 2;
        const d = (h / 2) / below;
        // The row covers the floor from pos + (dir - plane) d to
        // pos + (dir + plane) d: 2 * 0.8 * d units in 640 pixels.
        const step = 2 * plane_len * d / w;
        std.debug.print("{d:>3}  {d:>5.1}  {d:>8.3}  {d:>17.4}  {d:>12.2}\n", .{ y, below, d, step, step * 64 });
    }
}
