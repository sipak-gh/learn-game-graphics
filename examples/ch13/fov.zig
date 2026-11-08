//! Field of view and pixel shape for a few camera planes and screens.
//! Walls are drawn `height / d` pixels tall, so the vertical scale is
//! `height` pixels per unit (at distance 1). The plane maps its half-width
//! to half the screen, so the horizontal scale is `width / (2 * plane)`.
//! Pixels are square when the two scales agree: plane = width / (2 * height).
const std = @import("std");

fn degrees(radians: f32) f32 {
    return std.math.radiansToDegrees(radians);
}

pub fn main() void {
    const screens = [_][2]f32{ .{ 320, 200 }, .{ 640, 400 }, .{ 640, 480 } };
    const planes = [_]f32{ 0.66, 0.8, 1.0 };

    std.debug.print("screen   plane  h-fov  v-fov  px/unit across  px/unit up  stretch\n", .{});
    for (screens) |s| {
        const w = s[0];
        const h = s[1];
        for (planes) |p| {
            const across = w / (2 * p);
            const up = h; // wallHeight = h / d
            // The screen's half-height is h/2 pixels, which is (h/2)/up
            // units at distance 1: always 0.5 with this wall height.
            const vfov = 2 * std.math.atan((h / 2) / up);
            std.debug.print("{d}x{d}  {d:>5.2}  {d:>5.1}  {d:>5.1}  {d:>14.1}  {d:>10.1}  {d:>7.3}{s}\n", .{
                w,      h,  p,           degrees(2 * std.math.atan(p)),                    degrees(vfov),
                across, up, up / across, if (@abs(across - up) < 0.01) "  square" else "",
            });
        }
    }
    std.debug.print("\nsquare-pixel plane for 640x400: {d:.3}, for 640x480: {d:.3}\n", .{
        640.0 / (2.0 * 400.0), 640.0 / (2.0 * 480.0),
    });
}
