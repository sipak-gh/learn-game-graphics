//! The cube view's model matrix is R(t) T(-0.5): read right to left, first
//! move the unit cube so its center is at the origin, then turn it. The
//! other order, T(-0.5) R(t), turns the cube about its corner (0, 0, 0)
//! and only then moves it, so its center swings around.
const std = @import("std");

const Vec3 = @Vector(3, f32);

/// The two transforms as functions on points (a matrix product applies the
/// rightmost matrix first, so these spell out each order).
fn rotateY(p: Vec3, a: f32) Vec3 {
    return .{ p[0] * @cos(a) + p[2] * @sin(a), p[1], -p[0] * @sin(a) + p[2] * @cos(a) };
}

fn translate(p: Vec3) Vec3 {
    return p - Vec3{ 0.5, 0.5, 0.5 };
}

fn show(name: []const u8, p: Vec3) void {
    const q = @round(p * @as(Vec3, @splat(1000))) / @as(Vec3, @splat(1000)) + @as(Vec3, @splat(0));
    std.debug.print("  {s} ({d:6.3}, {d:6.3}, {d:6.3})", .{ name, q[0], q[1], q[2] });
}

pub fn main() void {
    const center: Vec3 = .{ 0.5, 0.5, 0.5 };
    const corner: Vec3 = .{ 1, 1, 1 };
    std.debug.print("R(t) T(-0.5): translate first, then rotate\n", .{});
    for ([_]f32{ 0, 90, 180 }) |deg| {
        const a = std.math.degreesToRadians(deg);
        std.debug.print("t = {d:>3}:", .{deg});
        show("center", rotateY(translate(center), a));
        show("corner", rotateY(translate(corner), a));
        std.debug.print("\n", .{});
    }
    std.debug.print("T(-0.5) R(t): rotate first, then translate\n", .{});
    for ([_]f32{ 0, 90, 180 }) |deg| {
        const a = std.math.degreesToRadians(deg);
        std.debug.print("t = {d:>3}:", .{deg});
        show("center", translate(rotateY(center, a)));
        show("corner", translate(rotateY(corner, a)));
        std.debug.print("\n", .{});
    }
}
