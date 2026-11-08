//! How finely an f32 depth buffer can tell distances apart. The stored
//! depth is z/w = far/(far - near) * (1 - near/d) for a point at distance
//! d: it climbs steeply near the eye and is almost flat far away.
const std = @import("std");

const far = 64.0;

fn depth(near: f32, d: f32) f32 {
    return far / (far - near) * (1 - near / d);
}

/// The distance whose depth is z: the formula solved for d. In f64, so
/// that tiny gaps between two distances are not lost to rounding.
fn distance(near: f32, z: f32) f64 {
    const n: f64 = near;
    return n * far / (far - @as(f64, z) * (far - n));
}

pub fn main() void {
    for ([_]f32{ 0.05, 0.2 }) |near| {
        std.debug.print("near = {d}: depth 0.5 is {d:.3} away, depth 0.9 is {d:.3} away\n", .{
            near, distance(near, 0.5), distance(near, 0.9),
        });
        std.debug.print("  distance     depth  gap to the distance of the next f32\n", .{});
        for ([_]f32{ 0.25, 1, 10, 30, 60 }) |d| {
            const z = depth(near, d);
            const next = std.math.nextAfter(f32, z, 2);
            std.debug.print("  {d:>8} {d:>9.6} {e:>12.3}\n", .{ d, z, distance(near, next) - distance(near, z) });
        }
    }
}
