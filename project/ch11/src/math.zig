//! Vectors for delve. A vector is a `@Vector` of f32, so `+`, `-`, `*` and
//! `/` work lane by lane, and the compiler can use SIMD instructions.
const std = @import("std");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);

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

/// For tests: true when every lane of `a` and `b` differs by at most 1e-5.
pub fn approxEq(a: anytype, b: @TypeOf(a)) bool {
    return @reduce(.And, @abs(a - b) <= @as(@TypeOf(a), @splat(1e-5)));
}

const expect = std.testing.expect;
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
