//! A 2x2 matrix is "where the basis vectors go". Its columns are the
//! images of (1, 0) and (0, 1); every other point follows from those two.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// A 2x2 matrix as two columns.
const Mat2 = struct {
    cols: [2]Vec2,

    /// M v = v.x * (first column) + v.y * (second column).
    fn apply(m: Mat2, v: Vec2) Vec2 {
        return m.cols[0] * @as(Vec2, @splat(v[0])) + m.cols[1] * @as(Vec2, @splat(v[1]));
    }
};

fn show(name: []const u8, m: Mat2) void {
    std.debug.print("{s}:\n", .{name});
    // Print row by row: row r holds lane r of every column.
    inline for (0..2) |r| {
        std.debug.print("  | {d:>6.3} {d:>6.3} |\n", .{ m.cols[0][r], m.cols[1][r] });
    }
    const points = [_]Vec2{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 3, 2 } };
    for (points) |p| {
        const q = m.apply(p);
        std.debug.print("  ({d}, {d}) -> ({d:.3}, {d:.3})\n", .{ p[0], p[1], q[0], q[1] });
    }
}

pub fn main() void {
    // Send (1, 0) to (2, 0) and (0, 1) to (1, 1): a stretch plus a shear.
    show("stretch and shear", .{ .cols = .{ .{ 2, 0 }, .{ 1, 1 } } });

    // Scaling: each axis is stretched by its own factor.
    show("scale (3, 0.5)", .{ .cols = .{ .{ 3, 0 }, .{ 0, 0.5 } } });

    // Rotation by 30 degrees: (1, 0) goes to (cos, sin), and (0, 1), a
    // quarter turn ahead of it, goes to a quarter turn ahead of that.
    const a = std.math.degreesToRadians(30.0);
    show("rotate 30 deg", .{ .cols = .{ .{ @cos(a), @sin(a) }, .{ -@sin(a), @cos(a) } } });
}
