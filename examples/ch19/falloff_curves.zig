//! How a point light fades with distance: the inverse square law, the
//! same with a 1 + that keeps it finite, a window that ends it at a
//! radius, and the product that delve uses.
const std = @import("std");

/// Half strength at this distance (before the window).
const half_distance = 1.5;
/// The light adds nothing from here on.
const radius = 5.0;

fn inverseSquare(d: f32) f32 {
    return 1 / (d * d);
}

fn soft(d: f32) f32 {
    const x = d / half_distance;
    return 1 / (1 + x * x);
}

fn window(d: f32) f32 {
    const x = d / radius;
    const w = @max(0, 1 - x * x);
    return w * w;
}

pub fn main() void {
    std.debug.print("   d    1/d^2   soft  window  product\n", .{});
    var i: usize = 0;
    while (i <= 12) : (i += 1) {
        const d = 0.5 * @as(f32, @floatFromInt(i));
        const product = soft(d) * window(d);
        const bar: [40]u8 = @splat('#');
        const n: usize = @intFromFloat(@round(product * 40));
        const gap = if (n == 0) "" else " ";
        std.debug.print("{d:>4.1}  {d:>6.3}  {d:>5.3}  {d:>6.3}  {d:>6.3}{s}{s}\n", .{
            d, inverseSquare(d), soft(d), window(d), product, gap, bar[0..n],
        });
    }
    // The window's slope at the radius: zero, so the light fades out
    // without a crease.
    const e = 0.001;
    std.debug.print("window slope just inside the radius: {d:.6}\n", .{(window(radius) - window(radius - e)) / e});
}
