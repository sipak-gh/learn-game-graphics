//! Pixel values are not amounts of light. Screens and image files use
//! the sRGB curve: a byte value v stands for linear light decode(v), which
//! grows much faster than v. Lighting math on bytes is therefore off.
const std = @import("std");

/// sRGB byte to linear light, 0 to 1 (the exact sRGB curve).
fn decode(byte: u8) f32 {
    const c = @as(f32, @floatFromInt(byte)) / 255;
    return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

/// Linear light, 0 to 1, to the nearest sRGB byte.
fn encode(light: f32) u8 {
    const l = std.math.clamp(light, 0, 1);
    const c = if (l <= 0.0031308) l * 12.92 else 1.055 * std.math.pow(f32, l, 1.0 / 2.4) - 0.055;
    return @intFromFloat(@round(c * 255));
}

pub fn main() void {
    std.debug.print("sRGB  linear  (v/255)^2.2  back\n", .{});
    for ([_]u8{ 0, 10, 64, 128, 188, 192, 255 }) |v| {
        const approx = std.math.pow(f32, @as(f32, @floatFromInt(v)) / 255, 2.2);
        std.debug.print("{d:>4}  {d:>6.4}  {d:>11.4}  {d:>4}\n", .{ v, decode(v), approx, encode(decode(v)) });
    }

    std.debug.print("half the light of 255:          sRGB {d}\n", .{encode(0.5 * decode(255))});
    std.debug.print("byte 200 scaled by 0.5 = 100:   {d:.3} of the light\n", .{decode(100) / decode(200)});
    std.debug.print("ambient 0.25 on byte 255 = 64:  {d:.3} of the light\n", .{decode(64) / decode(255)});
    std.debug.print("two lights of 128, as bytes:    {d}\n", .{@min(255, 128 + 128)});
    std.debug.print("two lights of 128, linear:      sRGB {d}\n", .{encode(decode(128) + decode(128))});
}
