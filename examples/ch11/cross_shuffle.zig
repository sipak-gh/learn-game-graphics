//! The cross product with two lane shuffles, its right-hand rule, and the
//! area of a triangle.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

/// (a.y b.z - a.z b.y, a.z b.x - a.x b.z, a.x b.y - a.y b.x)
fn cross(a: Vec3, b: Vec3) Vec3 {
    const yzx: @Vector(3, i32) = .{ 1, 2, 0 };
    const zxy: @Vector(3, i32) = .{ 2, 0, 1 };
    const a_yzx = @shuffle(f32, a, undefined, yzx);
    const a_zxy = @shuffle(f32, a, undefined, zxy);
    const b_yzx = @shuffle(f32, b, undefined, yzx);
    const b_zxy = @shuffle(f32, b, undefined, zxy);
    return a_yzx * b_zxy - a_zxy * b_yzx;
}

pub fn main() void {
    const x: Vec3 = .{ 1, 0, 0 };
    const y: Vec3 = .{ 0, 1, 0 };
    const z: Vec3 = .{ 0, 0, 1 };
    std.debug.print("shuffle yzx of (1,2,3) = {any}\n", .{@shuffle(f32, Vec3{ 1, 2, 3 }, undefined, @Vector(3, i32){ 1, 2, 0 })});
    std.debug.print("x cross y = {any}\n", .{cross(x, y)});
    std.debug.print("y cross z = {any}\n", .{cross(y, z)});
    std.debug.print("z cross x = {any}\n", .{cross(z, x)});
    std.debug.print("y cross x = {any}\n", .{cross(y, x)});
    std.debug.print("x cross x = {any}\n", .{cross(x, x)});

    const a: Vec3 = .{ 1, 2, 3 };
    const b: Vec3 = .{ -4, 0.5, 2 };
    const c = cross(a, b);
    std.debug.print("a cross b = {any}\n", .{c});
    std.debug.print("dot with a = {d}, dot with b = {d}\n", .{ dot(c, a), dot(c, b) });

    // Triangle area: half the length of the cross product of two edges.
    const p0: Vec3 = .{ 0, 0, 0 };
    const p1: Vec3 = .{ 4, 0, 0 };
    const p2: Vec3 = .{ 1, 3, 0 };
    const n = cross(p1 - p0, p2 - p0);
    std.debug.print("edges cross = {any}, area = {d}\n", .{ n, @sqrt(dot(n, n)) / 2 });
    // The same triangle tilted out of the xy plane: still works in 3D.
    const q2: Vec3 = .{ 1, 3, 4 };
    const m = cross(p1 - p0, q2 - p0);
    std.debug.print("tilted cross = {any}, area = {d}\n", .{ m, @sqrt(dot(m, m)) / 2 });
}
