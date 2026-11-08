//! Turning normals. A slope and its normal go through a transform M. The
//! slope's direction turns with M; the normal must turn with the inverse
//! transpose of M, or it stops being perpendicular to the surface.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn normalize(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(@sqrt(dot(v, v))));
}

/// A 3x3 matrix as three columns: enough for directions, which ignore
/// translation.
const Mat3 = struct {
    cols: [3]Vec3,

    fn apply(m: Mat3, v: Vec3) Vec3 {
        return m.cols[0] * @as(Vec3, @splat(v[0])) + m.cols[1] * @as(Vec3, @splat(v[1])) +
            m.cols[2] * @as(Vec3, @splat(v[2]));
    }

    fn mul(a: Mat3, b: Mat3) Mat3 {
        return .{ .cols = .{ a.apply(b.cols[0]), a.apply(b.cols[1]), a.apply(b.cols[2]) } };
    }

    /// The inverse transpose times the determinant: its columns are cross
    /// products of M's columns. Normals are normalized after turning, so
    /// the factor does not matter, and no division is needed.
    fn cofactor(m: Mat3) Mat3 {
        const a, const b, const c = m.cols;
        return .{ .cols = .{ cross(b, c), cross(c, a), cross(a, b) } };
    }
};

fn degreesBetween(a: Vec3, b: Vec3) f32 {
    return std.math.radiansToDegrees(std.math.acos(dot(normalize(a), normalize(b))));
}

fn check(name: []const u8, m: Mat3) void {
    // A slope rising along x at 45 degrees, and its normal.
    const along: Vec3 = .{ 1, 1, 0 };
    const normal = normalize(.{ -1, 1, 0 });
    const new_along = m.apply(along);
    std.debug.print("{s}\n", .{name});
    std.debug.print("  normal turned with M:          {d:>6.2} deg to the surface\n", .{degreesBetween(m.apply(normal), new_along)});
    const n = normalize(m.cofactor().apply(normal));
    std.debug.print("  with the inverse transpose:    {d:>6.2} deg, normal ({d:.3}, {d:.3}, {d:.3})\n", .{
        degreesBetween(n, new_along), n[0], n[1], n[2],
    });
}

pub fn main() void {
    const stretch: Mat3 = .{ .cols = .{ .{ 4, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } } };
    check("stretch x by 4", stretch);

    const a = std.math.degreesToRadians(30.0);
    const rotate: Mat3 = .{ .cols = .{ .{ @cos(a), @sin(a), 0 }, .{ -@sin(a), @cos(a), 0 }, .{ 0, 0, 1 } } };
    check("rotate 30 deg about z", rotate);
    check("stretch, then rotate", rotate.mul(stretch));

    const uniform: Mat3 = .{ .cols = .{ .{ 3, 0, 0 }, .{ 0, 3, 0 }, .{ 0, 0, 3 } } };
    check("scale by 3 in every direction", uniform);
}
