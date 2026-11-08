//! The dot product: angles between vectors, and "in front or behind".
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

fn length(v: Vec2) f32 {
    return @sqrt(dot(v, v));
}

/// The angle between `a` and `b` in degrees, from a.b = |a| |b| cos(angle).
fn angleDeg(a: Vec2, b: Vec2) f32 {
    const c = dot(a, b) / (length(a) * length(b));
    // Rounding can push c a hair past 1 (or -1); acos would return NaN.
    return std.math.radiansToDegrees(std.math.acos(std.math.clamp(c, -1, 1)));
}

pub fn main() void {
    const east: Vec2 = .{ 1, 0 };
    const pairs = [_][2]Vec2{
        .{ east, .{ 3, 0 } },
        .{ east, .{ 1, 1 } },
        .{ east, .{ 0, 2 } },
        .{ east, .{ -1, 1 } },
        .{ east, .{ -4, 0 } },
        .{ .{ 3, 4 }, .{ 4, 3 } },
    };
    for (pairs) |pair| {
        const a, const b = pair;
        std.debug.print("a ({d:>2},{d:>2})  b ({d:>2},{d:>2})  a.b {d:>5.1}  angle {d:>5.1}\n", .{
            a[0], a[1], b[0], b[1], dot(a, b), angleDeg(a, b),
        });
    }

    // Only the sign is needed to tell front from back: no square roots,
    // no acos. The player stands at (2, 2) and faces east.
    const eye: Vec2 = .{ 2, 2 };
    const facing = east;
    const things = [_]Vec2{ .{ 6, 3 }, .{ 2, 5 }, .{ 0, 1 } };
    for (things) |t| {
        const d = dot(facing, t - eye);
        const where = if (d > 0) "in front" else if (d < 0) "behind" else "level with us";
        std.debug.print("thing at {any}: dot {d:>4} -> {s}\n", .{ t, d, where });
    }
}
