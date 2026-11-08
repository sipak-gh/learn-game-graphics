//! Homogeneous coordinates: one 4x4 matrix moves points (w = 1) but leaves
//! directions (w = 0) alone.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// A 4x4 matrix as four columns: M v = sum of the columns weighted by v.
const Mat4 = struct {
    cols: [4]Vec4,

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var result: Vec4 = @splat(0);
        inline for (0..4) |i| result += m.cols[i] * @as(Vec4, @splat(v[i]));
        return result;
    }
};

pub fn main() void {
    // Translation by (10, 20, 30): the identity with the shift in the last
    // column. That column gets multiplied by w.
    const t: Mat4 = .{ .cols = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 10, 20, 30, 1 },
    } };

    const point: Vec4 = .{ 1, 2, 3, 1 };
    const direction: Vec4 = .{ 1, 2, 3, 0 };
    std.debug.print("point     {any} -> {any}\n", .{ point, t.mulVec(point) });
    std.debug.print("direction {any} -> {any}\n", .{ direction, t.mulVec(direction) });

    // The difference of two points is a direction: the w's cancel.
    const p: Vec4 = .{ 4, 4, 4, 1 };
    const q: Vec4 = .{ 1, 2, 3, 1 };
    std.debug.print("p - q = {any}\n", .{p - q});
    std.debug.print("T(p) - T(q) = {any} (unchanged by the move)\n", .{t.mulVec(p) - t.mulVec(q)});
    // The sum of two points has w = 2: neither a point nor a direction.
    // Their average (the midpoint) has w = 1 again.
    std.debug.print("p + q = {any}, (p + q) / 2 = {any}\n", .{ p + q, (p + q) / @as(Vec4, @splat(2)) });
}
