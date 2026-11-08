//! How big a pixel is on the floor texture, straight ahead at distance d.
//! The eye is 0.5 above the floor, the screen has 400 pixels per unit at
//! distance 1, and the floor texture repeats once per unit (u = x, v = z).
//! A floor point at distance d is 400 * 0.5 / d pixels below the center
//! of the screen, so:
//!   one pixel across moves  d / 400        units (grows with d),
//!   one pixel down moves    d^2 / 200      units (grows with d squared).
//! The level of detail takes the larger of the two, in texels, and log2.
const std = @import("std");

const size = 64; // texels per unit
const focal = 400.0; // pixels per unit at distance 1
const eye_height = 0.5;
const last_level = 6; // 64 -> 1x1 is 7 levels

pub fn main() void {
    const distances = [_]f32{ 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32 };
    std.debug.print("   d  across (texels)  down (texels)  ratio  lambda  mipmap  trilinear\n", .{});
    for (distances) |d| {
        const across = d / focal * size;
        const down = d * d / (focal * eye_height) * size;
        const lambda = @log2(@max(across, down));
        const clamped = std.math.clamp(lambda, 0, last_level);
        const level = @floor(clamped);
        std.debug.print("{d:>4}  {d:>15.3}  {d:>13.3}  {d:>5.1}  {d:>6.2}  {d:>6.0}  {d:.0} + {d:.2}\n", .{
            d, across, down, down / across, lambda, @round(clamped), level, clamped - level,
        });
    }
    std.debug.print("nearest and bilinear always read level 0.\n", .{});
}
