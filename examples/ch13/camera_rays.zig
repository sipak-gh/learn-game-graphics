//! The camera rays of an 8-pixel-wide screen: each is the view direction
//! plus a part of the camera plane. Their lengths differ, but every one of
//! them reaches exactly 1 unit forward along the view direction.
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

pub fn main() void {
    const width = 8;
    const yaw: f32 = std.math.degreesToRadians(30.0);
    const dir: Vec2 = .{ @cos(yaw), @sin(yaw) };
    const plane: Vec2 = Vec2{ -dir[1], dir[0] } * @as(Vec2, @splat(0.8)); // perp(dir) * 0.8

    std.debug.print("dir = ({d:.3}, {d:.3})  plane = ({d:.3}, {d:.3})  dot(dir, plane) = {d:.3}\n\n", .{
        dir[0], dir[1], plane[0], plane[1], dot(dir, plane),
    });
    std.debug.print(" x  camera_x  ray                dot(ray,dir)  |ray|   angle\n", .{});
    for (0..width) |x| {
        const fx: f32 = @floatFromInt(x);
        const camera_x = 2 * (fx + 0.5) / width - 1;
        const ray = dir + plane * @as(Vec2, @splat(camera_x));
        const len = @sqrt(dot(ray, ray));
        // The angle between the ray and the view direction, in degrees.
        const angle = std.math.radiansToDegrees(std.math.atan2(
            dir[0] * ray[1] - dir[1] * ray[0],
            dot(dir, ray),
        ));
        std.debug.print("{d:>2}  {d:>7.3}  ({d:>6.3}, {d:>6.3})  {d:>11.3}  {d:>6.3}  {d:>6.1}\n", .{
            x, camera_x, ray[0], ray[1], dot(ray, dir), len, angle,
        });
    }
    std.debug.print("\nhorizontal field of view: 2 * atan(0.8) = {d:.2} degrees\n", .{
        std.math.radiansToDegrees(2 * std.math.atan(@as(f32, 0.8))),
    });
}
