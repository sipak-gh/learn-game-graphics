//! @Vector arithmetic: points, directions, and lane-wise operators.
const std = @import("std");

const Vec2 = @Vector(2, f32);
const Vec3 = @Vector(3, f32);

pub fn main() void {
    const p: Vec2 = .{ 2, 1 }; // a point: where something is
    const q: Vec2 = .{ 5, 5 };
    const d = q - p; // a direction: how to get from p to q

    std.debug.print("p = {any}, q = {any}\n", .{ p, q });
    std.debug.print("q - p = {any}\n", .{d});
    std.debug.print("p + d = {any} (back at q)\n", .{p + d});
    std.debug.print("p + d * 0.5 = {any} (half way)\n", .{p + d * @as(Vec2, @splat(0.5))});

    // Operators work lane by lane. `*` is NOT a dot product.
    const a: Vec3 = .{ 1, 2, 3 };
    const b: Vec3 = .{ 4, 5, 6 };
    std.debug.print("a * b = {any}\n", .{a * b});
    std.debug.print("@reduce(.Add, a * b) = {d}\n", .{@reduce(.Add, a * b)});
    const c: Vec3 = .{ 3, 0, 9 };
    std.debug.print("@min(a, c) = {any}, @max(a, c) = {any}\n", .{ @min(a, c), @max(a, c) });
    std.debug.print("@floor(.{{ 2.7, -0.5 }}) = {any}\n", .{@floor(Vec2{ 2.7, -0.5 })});

    // Lanes by index, and destructuring into named values.
    const x, const y, const z = a;
    std.debug.print("a[0] = {d}, x y z = {d} {d} {d}\n", .{ a[0], x, y, z });

    // A vector and an array of the same length coerce into each other.
    const arr: [3]f32 = a;
    const back: Vec3 = arr;
    std.debug.print("as array {any}, back {any}\n", .{ arr, back });

    // Comparisons give a vector of bools; @reduce turns it into one bool.
    const less = a < c;
    std.debug.print("a < c = {any}, all: {}, any: {}\n", .{ less, @reduce(.And, less), @reduce(.Or, less) });
}
