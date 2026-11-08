//! How close may a wall come before the near plane cuts it open? The
//! visible part of the near plane is a rectangle `near` in front of the
//! eye, with half-sizes near * tan_h and near * tan_v. Its corners are the
//! points of it farthest from the eye: near * sqrt(1 + tan_h^2 + tan_v^2).
//! A player circle at least that big keeps every wall beyond the near plane.
const std = @import("std");

/// The distance from the eye to a corner of the near rectangle, per unit
/// of `near`.
fn cornerFactor(tan_h: f32, tan_v: f32) f32 {
    return @sqrt(1 + tan_h * tan_h + tan_v * tan_v);
}

pub fn main() void {
    const near = 0.05;
    const radius = 0.25;

    // delve: a vertical fov of 2 atan(0.5) (about 53 degrees) on a 640 x 400
    // screen, so tan_v = 0.5 and tan_h = 0.8.
    const k = cornerFactor(0.8, 0.5);
    std.debug.print("delve: corner at {d:.4} x near = {d:.4}; radius {d} leaves {d:.1}x\n", .{ k, near * k, radius, radius / (near * k) });
    std.debug.print("       the largest near plane radius {d} allows: {d:.3}\n\n", .{ radius, radius / k });

    // Horizontal fovs at a few aspect ratios.
    const aspects = [_]struct { name: []const u8, w: f32, h: f32 }{
        .{ .name = "4:3", .w = 4, .h = 3 },
        .{ .name = "16:10", .w = 16, .h = 10 },
        .{ .name = "16:9", .w = 16, .h = 9 },
        .{ .name = "21:9", .w = 21, .h = 9 },
    };
    const fovs = [_]f32{ 60, 75, 90, 105, 120 };
    std.debug.print("smallest safe radius at near = {d}, by horizontal fov:\n", .{near});
    std.debug.print("{s:>6}", .{"fov"});
    for (aspects) |a| std.debug.print("  {s:>6}", .{a.name});
    std.debug.print("\n", .{});
    for (fovs) |fov| {
        std.debug.print("{d:>6}", .{fov});
        const tan_h = @tan(std.math.degreesToRadians(fov) / 2);
        for (aspects) |a| {
            const tan_v = tan_h * a.h / a.w;
            std.debug.print("  {d:>6.4}", .{near * cornerFactor(tan_h, tan_v)});
        }
        std.debug.print("\n", .{});
    }
}
