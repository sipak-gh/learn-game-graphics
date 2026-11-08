//! Winding: the order of a triangle's corners. By the right-hand rule,
//! cross(b - a, c - a) points toward the side from which a, b, c look
//! counter-clockwise. Swapping two corners flips it.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

/// Twice the signed area of a 2D triangle: positive if a, b, c turn
/// counter-clockwise when x goes right and y goes up.
fn area2(a: [2]f32, b: [2]f32, c: [2]f32) f32 {
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
}

pub fn main() void {
    // A triangle in the plane z = 0, looked at from +z (from the viewer).
    const a: Vec3 = .{ 0, 0, 0 };
    const b: Vec3 = .{ 2, 0, 0 };
    const c: Vec3 = .{ 0, 1, 0 };
    for ([_][3]Vec3{ .{ a, b, c }, .{ a, c, b } }, [_][]const u8{ "a b c", "a c b" }) |t, name| {
        const n = cross(t[1] - t[0], t[2] - t[0]);
        const ar = area2(.{ t[0][0], t[0][1] }, .{ t[1][0], t[1][1] }, .{ t[2][0], t[2][1] });
        std.debug.print("{s}: cross = {any}  signed area (y up) = {d:4.1}  -> {s} seen from +z\n", .{
            name, n, ar / 2, if (n[2] > 0) "counter-clockwise" else "clockwise",
        });
    }
    // On a screen y grows down: the same corners, mirrored top to bottom.
    const flip = [3][2]f32{ .{ 0, 0 }, .{ 2, 0 }, .{ 0, -1 } };
    std.debug.print("a b c with y flipped (screen rows): signed area = {d:4.1}\n", .{area2(flip[0], flip[1], flip[2]) / 2});
}
