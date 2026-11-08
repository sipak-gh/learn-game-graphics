//! Lambert's cosine law: how much light a surface catches as the light
//! tilts away from its normal. Also: what that does to a gray wall.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

/// The share of a light that a surface facing `normal` catches from the
/// direction `to_light`. Both have length 1.
fn lambert(normal: Vec3, to_light: Vec3) f32 {
    return @max(0, dot(normal, to_light));
}

pub fn main() void {
    const up: Vec3 = .{ 0, 1, 0 };
    const gray = 180.0; // the wall's own color, 0-255
    const ambient = 0.25;
    std.debug.print("angle  cos      lambert  wall (ambient 0.25 + light)\n", .{});
    for ([_]f32{ 0, 15, 30, 45, 60, 75, 90, 120, 180 }) |deg| {
        const angle = std.math.degreesToRadians(deg);
        // A light direction tilted `deg` degrees from the normal.
        const to_light: Vec3 = .{ @sin(angle), @cos(angle), 0 };
        const l = lambert(up, to_light);
        const wall = @min(255, gray * (ambient + l));
        const bar: [40]u8 = @splat('#');
        const n: usize = @intFromFloat(wall / 255 * 40);
        std.debug.print("{d:>5}  {d:>6.3}  {d:>6.3}   {d:>3.0} {s}\n", .{ deg, @cos(angle), l, wall, bar[0..n] });
    }
}
