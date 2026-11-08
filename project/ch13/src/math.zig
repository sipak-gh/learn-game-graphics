//! Vectors and matrices for delve. A vector is a `@Vector` of f32, so `+`,
//! `-`, `*` and `/` work lane by lane, and the compiler can use SIMD
//! instructions.
const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

/// `v` with every lane multiplied by `s`.
pub fn scale(v: anytype, s: f32) @TypeOf(v) {
    return v * @as(@TypeOf(v), @splat(s));
}

/// The dot product: |a| |b| cos(angle between a and b).
pub fn dot(a: anytype, b: @TypeOf(a)) f32 {
    return @reduce(.Add, a * b);
}

pub fn length(v: anytype) f32 {
    return @sqrt(dot(v, v));
}

/// `v` scaled to length 1. The zero vector has no direction; it is
/// returned unchanged.
pub fn normalize(v: anytype) @TypeOf(v) {
    const len = length(v);
    if (len == 0) return v;
    return scale(v, 1 / len);
}

/// The point a fraction `t` of the way from `a` to `b`.
pub fn lerp(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return a + scale(b - a, t);
}

/// The cross product: perpendicular to both `a` and `b`, with length
/// |a| |b| sin(angle). Right-handed: cross(x, y) = z.
pub fn cross(a: Vec3, b: Vec3) Vec3 {
    // (a.y b.z - a.z b.y, a.z b.x - a.x b.z, a.x b.y - a.y b.x), written
    // with lane shuffles: yzx and zxy are the lanes rotated by one and two.
    const yzx: @Vector(3, i32) = .{ 1, 2, 0 };
    const zxy: @Vector(3, i32) = .{ 2, 0, 1 };
    const a_yzx = @shuffle(f32, a, undefined, yzx);
    const a_zxy = @shuffle(f32, a, undefined, zxy);
    const b_yzx = @shuffle(f32, b, undefined, yzx);
    const b_zxy = @shuffle(f32, b, undefined, zxy);
    return a_yzx * b_zxy - a_zxy * b_yzx;
}

/// The 2D cross product (the z of the 3D cross product): positive when
/// `b` is clockwise from `a` on a y-down screen.
pub fn cross2(a: Vec2, b: Vec2) f32 {
    return a[0] * b[1] - a[1] * b[0];
}

/// `v` turned a quarter turn: from +x to +y, clockwise on a y-down screen.
pub fn perp(v: Vec2) Vec2 {
    return .{ -v[1], v[0] };
}

/// The unit vector at `angle` radians from +x, turning toward +y.
pub fn fromAngle(angle: f32) Vec2 {
    return .{ @cos(angle), @sin(angle) };
}

/// `v` rotated by `angle` radians, turning from +x toward +y.
pub fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ c * v[0] - s * v[1], s * v[0] + c * v[1] };
}

/// The homogeneous form of `v`: a point when w = 1, a direction when w = 0.
pub fn vec4(v: Vec3, w: f32) Vec4 {
    return .{ v[0], v[1], v[2], w };
}

/// The first three lanes of `v`.
pub fn xyz(v: Vec4) Vec3 {
    return .{ v[0], v[1], v[2] };
}

/// A 4x4 matrix stored as four columns. A matrix transforms a column vector
/// on its right: `m.mulVec(v)`. In `a.mul(b)`, `b` is applied first.
pub const Mat4 = struct {
    cols: [4]Vec4,

    pub const identity: Mat4 = .{ .cols = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    } };

    /// Builds a matrix from rows, so code can be written the way matrices
    /// are printed in books.
    pub fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    /// The element in row `r`, column `c`.
    pub fn at(m: Mat4, r: usize, c: usize) f32 {
        // A vector lane needs a comptime-known index; an array element
        // does not, so coerce the column to an array first.
        const col: [4]f32 = m.cols[c];
        return col[r];
    }

    /// m v: the columns weighted by the components of v.
    pub fn mulVec(m: Mat4, v: Vec4) Vec4 {
        return scale(m.cols[0], v[0]) + scale(m.cols[1], v[1]) +
            scale(m.cols[2], v[2]) + scale(m.cols[3], v[3]);
    }

    /// The product a b: the transform that applies b, then a.
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }

    /// Transforms a point (w = 1): translation applies.
    pub fn transformPoint(m: Mat4, p: Vec3) Vec3 {
        return xyz(m.mulVec(vec4(p, 1)));
    }

    /// Transforms a direction (w = 0): translation does not apply.
    pub fn transformDir(m: Mat4, d: Vec3) Vec3 {
        return xyz(m.mulVec(vec4(d, 0)));
    }

    pub fn transpose(m: Mat4) Mat4 {
        var t: Mat4 = undefined;
        inline for (0..4) |r| t.cols[r] = .{ m.cols[0][r], m.cols[1][r], m.cols[2][r], m.cols[3][r] };
        return t;
    }

    pub fn translation(t: Vec3) Mat4 {
        var m = identity;
        m.cols[3] = vec4(t, 1);
        return m;
    }

    pub fn scaling(s: Vec3) Mat4 {
        return fromRows(.{
            .{ s[0], 0, 0, 0 },
            .{ 0, s[1], 0, 0 },
            .{ 0, 0, s[2], 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// Rotation by `angle` radians about the x axis: y turns toward z.
    pub fn rotationX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ 1, 0, 0, 0 },
            .{ 0, c, -s, 0 },
            .{ 0, s, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// Rotation by `angle` radians about the y axis: z turns toward x.
    pub fn rotationY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ c, 0, s, 0 },
            .{ 0, 1, 0, 0 },
            .{ -s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// Rotation by `angle` radians about the z axis: x turns toward y.
    pub fn rotationZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return fromRows(.{
            .{ c, -s, 0, 0 },
            .{ s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        });
    }

    /// The inverse matrix, by Gauss-Jordan elimination: row operations that
    /// turn `m` into the identity turn the identity into the inverse.
    /// Returns null if `m` has no inverse (it squashes space flat).
    pub fn inverse(m: Mat4) ?Mat4 {
        var a: [4][8]f32 = undefined; // [m | identity], row by row
        for (0..4) |r| {
            for (0..4) |c| {
                a[r][c] = m.at(r, c);
                a[r][c + 4] = if (r == c) 1 else 0;
            }
        }
        for (0..4) |col| {
            // Pick the row with the largest entry in this column (partial
            // pivoting) to keep rounding errors small.
            var pivot = col;
            for (col + 1..4) |r| {
                if (@abs(a[r][col]) > @abs(a[pivot][col])) pivot = r;
            }
            if (@abs(a[pivot][col]) < 1e-12) return null;
            std.mem.swap([8]f32, &a[col], &a[pivot]);
            const inv_pivot = 1 / a[col][col];
            for (&a[col]) |*x| x.* *= inv_pivot;
            for (0..4) |r| {
                if (r == col) continue;
                const factor = a[r][col];
                for (&a[r], a[col]) |*x, p| x.* -= factor * p;
            }
        }
        var rows: [4][4]f32 = undefined;
        for (&rows, a) |*row, full| row.* = full[4..8].*;
        return fromRows(rows);
    }

    /// For tests: true when every element differs by at most 1e-5.
    pub fn approxEq(a: Mat4, b: Mat4) bool {
        for (a.cols, b.cols) |x, y| {
            if (@reduce(.Or, @abs(x - y) > @as(Vec4, @splat(1e-5)))) return false;
        }
        return true;
    }
};

/// For tests: true when every lane of `a` and `b` differs by at most 1e-5.
pub fn approxEq(a: anytype, b: @TypeOf(a)) bool {
    return @reduce(.And, @abs(a - b) <= @as(@TypeOf(a), @splat(1e-5)));
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApprox = std.testing.expectApproxEqAbs;

test "dot, length, and normalize" {
    const v: Vec3 = .{ 3, 4, 12 };
    try expectApprox(169, dot(v, v), 1e-6);
    try expectApprox(13, length(v), 1e-6);
    try expectApprox(1, length(normalize(v)), 1e-6);
    try expect(approxEq(normalize(Vec2{ 0, 0 }), Vec2{ 0, 0 }));
    // Perpendicular vectors have a zero dot product.
    try expectApprox(0, dot(Vec2{ 2, 1 }, perp(Vec2{ 2, 1 })), 1e-6);
}

test "cross follows the right-hand rule" {
    const x: Vec3 = .{ 1, 0, 0 };
    const y: Vec3 = .{ 0, 1, 0 };
    const z: Vec3 = .{ 0, 0, 1 };
    try expect(approxEq(cross(x, y), z));
    try expect(approxEq(cross(y, z), x));
    try expect(approxEq(cross(y, x), -z));
    const a: Vec3 = .{ 1, 2, 3 };
    const b: Vec3 = .{ -4, 0.5, 2 };
    try expectApprox(0, dot(cross(a, b), a), 1e-5);
    try expectApprox(0, dot(cross(a, b), b), 1e-5);
}

test "rotation and angles" {
    try expect(approxEq(rotate(Vec2{ 1, 0 }, std.math.pi / 2.0), Vec2{ 0, 1 }));
    try expect(approxEq(fromAngle(std.math.pi), Vec2{ -1, 0 }));
    try expect(approxEq(perp(Vec2{ 1, 0 }), Vec2{ 0, 1 }));
    try expectApprox(1, cross2(Vec2{ 1, 0 }, Vec2{ 0, 1 }), 1e-6);
    try expect(approxEq(lerp(Vec2{ 0, 0 }, Vec2{ 10, -2 }, 0.25), Vec2{ 2.5, -0.5 }));
}

test "transforming points and directions" {
    const m = Mat4.translation(.{ 10, 0, 0 });
    try expect(approxEq(m.transformPoint(.{ 1, 2, 3 }), Vec3{ 11, 2, 3 }));
    try expect(approxEq(m.transformDir(.{ 1, 2, 3 }), Vec3{ 1, 2, 3 }));
    try expect(approxEq(Mat4.rotationZ(std.math.pi / 2.0).transformPoint(.{ 1, 0, 0 }), Vec3{ 0, 1, 0 }));
    try expect(approxEq(Mat4.rotationX(std.math.pi / 2.0).transformPoint(.{ 0, 1, 0 }), Vec3{ 0, 0, 1 }));
    try expect(approxEq(Mat4.rotationY(std.math.pi / 2.0).transformPoint(.{ 0, 0, 1 }), Vec3{ 1, 0, 0 }));
}

test "the order of a product matters" {
    const t = Mat4.translation(.{ 5, 0, 0 });
    const r = Mat4.rotationZ(std.math.pi / 2.0);
    // Rotate, then translate: (1,0) -> (0,1) -> (5,1).
    try expect(approxEq(t.mul(r).transformPoint(.{ 1, 0, 0 }), Vec3{ 5, 1, 0 }));
    // Translate, then rotate: (1,0) -> (6,0) -> (0,6).
    try expect(approxEq(r.mul(t).transformPoint(.{ 1, 0, 0 }), Vec3{ 0, 6, 0 }));
}

test "inverse undoes a transform" {
    const m = Mat4.translation(.{ 3, -2, 7 }).mul(Mat4.rotationY(0.7)).mul(Mat4.scaling(.{ 2, 3, 0.5 }));
    const inv = m.inverse().?;
    try expect(inv.mul(m).approxEq(Mat4.identity));
    try expect(m.mul(inv).approxEq(Mat4.identity));
    // A rotation's inverse is its transpose.
    const r = Mat4.rotationX(1.1).mul(Mat4.rotationZ(-0.4));
    try expect(r.inverse().?.approxEq(r.transpose()));
    // Scaling by zero flattens space: no inverse.
    try expectEqual(null, Mat4.scaling(.{ 1, 0, 1 }).inverse());
}
