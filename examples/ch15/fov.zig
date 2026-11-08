//! Vertical and horizontal field of view. The projection takes the vertical
//! one; the horizontal one follows from the aspect ratio, because the
//! screen at distance 1 is tan(vfov/2) tall (half) and aspect times as wide.
const std = @import("std");

fn deg(rad: f32) f32 {
    return std.math.radiansToDegrees(rad);
}

fn hfovOf(vfov: f32, aspect: f32) f32 {
    return 2 * std.math.atan(aspect * @tan(vfov / 2));
}

pub fn main() void {
    const aspect: f32 = 640.0 / 400.0;
    const vfov = 2 * std.math.atan(@as(f32, 0.5));
    std.debug.print("delve: vfov = 2 atan(0.5) = {d:.2} deg, aspect {d}\n", .{ deg(vfov), aspect });
    std.debug.print("  hfov = 2 atan(aspect tan(vfov/2)) = {d:.2} deg\n", .{deg(hfovOf(vfov, aspect))});
    std.debug.print("  ray caster: 2 atan(plane_scale 0.8) = {d:.2} deg\n\n", .{deg(2 * std.math.atan(@as(f32, 0.8)))});

    std.debug.print("vfov    f = 1/tan(vfov/2)   hfov at 16:10   hfov at 16:9\n", .{});
    for ([_]f32{ 53.13, 60, 90, 120 }) |v| {
        const r = std.math.degreesToRadians(v);
        std.debug.print("{d:6.2}  {d:8.4}             {d:6.2}          {d:6.2}\n", .{
            v, 1 / @tan(r / 2), deg(hfovOf(r, aspect)), deg(hfovOf(r, 16.0 / 9.0)),
        });
    }
}
