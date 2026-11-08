//! Projecting sprites into camera space with two dot products, then onto
//! a 640x400 screen. The camera stands at (2, 2) facing east.
const std = @import("std");

const Vec2 = @Vector(2, f32);

fn dot(a: Vec2, b: Vec2) f32 {
    return @reduce(.Add, a * b);
}

pub fn main() void {
    const w: f32 = 640;
    const h: f32 = 400;
    const pos: Vec2 = .{ 2, 2 };
    const dir: Vec2 = .{ 1, 0 };
    const plane: Vec2 = .{ 0, 0.8 }; // perp(dir) * 0.8: the right side is +y (south)

    const sprites = [_]Vec2{ .{ 5, 2 }, .{ 4, 3 }, .{ 10, 0 }, .{ 1, 2.5 } };
    std.debug.print("sprite      depth   side  camera_x  center_x   size\n", .{});
    for (sprites) |s| {
        const rel = s - pos;
        const depth = dot(rel, dir); // how far in front of the camera
        const side = dot(rel, plane) / dot(plane, plane); // across the plane, in plane lengths
        std.debug.print("({d:>4.1},{d:>4.1})  {d:>5.2}  {d:>5.2}", .{ s[0], s[1], depth, side });
        if (depth < 0.1) {
            std.debug.print("  behind the camera: skipped\n", .{});
            continue;
        }
        const camera_x = side / depth; // the perspective divide
        const center_x = (camera_x + 1) / 2 * w;
        const size = h / depth; // 1 unit tall, like a wall
        std.debug.print("  {d:>8.3}  {d:>8.1}  {d:>5.1}\n", .{ camera_x, center_x, size });
    }

    // Check: the camera ray through the sprite's column points at it.
    const s: Vec2 = .{ 4, 3 };
    const camera_x = dot(s - pos, plane) / dot(plane, plane) / dot(s - pos, dir);
    const ray = dir + plane * @as(Vec2, @splat(camera_x));
    const t = dot(s - pos, dir); // the ray reaches depth t at pos + ray * t
    const p = pos + ray * @as(Vec2, @splat(t));
    std.debug.print("\nray at camera_x {d:.3} reaches ({d:.3}, {d:.3})\n", .{ camera_x, p[0], p[1] });
}
