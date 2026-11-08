//! Comparing computed floats: == is almost never what you want.
//! Run with `zig test`.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// True when every lane of `a` and `b` differs by at most 1e-5.
fn approxEq(a: anytype, b: @TypeOf(a)) bool {
    return @reduce(.And, @abs(a - b) <= @as(@TypeOf(a), @splat(1e-5)));
}

fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ c * v[0] - s * v[1], s * v[0] + c * v[1] };
}

test "0.1 + 0.2 is not 0.3 in f64" {
    // `var` keeps the sum a run-time f64; constants would be computed at
    // compile time with more precision.
    var a: f64 = 0.1;
    var b: f64 = 0.2;
    _ = .{ &a, &b };
    std.debug.print("\n0.1 + 0.2 = {d}\n", .{a + b});
    try std.testing.expect(a + b != 0.3);
    try std.testing.expectApproxEqAbs(0.3, a + b, 1e-12);
}

test "a quarter turn is not exactly (0, 1)" {
    var angle: f32 = std.math.pi / 2.0;
    _ = &angle;
    const v = rotate(.{ 1, 0 }, angle);
    std.debug.print("\nrotate((1, 0), 90 deg) = ({e}, {d})\n", .{ v[0], v[1] });
    try std.testing.expect(v[0] != 0);
    try std.testing.expect(approxEq(v, Vec2{ 0, 1 }));
}

test "approxEq works for any vector length" {
    try std.testing.expect(approxEq(@Vector(3, f32){ 1, 2, 3 }, .{ 1, 2, 3.000001 }));
    try std.testing.expect(!approxEq(@Vector(3, f32){ 1, 2, 3 }, .{ 1, 2, 3.001 }));
}
