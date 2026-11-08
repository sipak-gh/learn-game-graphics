//! A sphere on a floor, lit by one warm point light and ambient light, the
//! way delve lights its walls: Lambert times a windowed falloff. No
//! rasterizer: each pixel's ray is intersected with the sphere and the
//! floor directly. Writes sphere.ppm.
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn dot(a: Vec3, b: Vec3) f32 {
    return @reduce(.Add, a * b);
}

fn splat(s: f32) Vec3 {
    return @splat(s);
}

fn normalize(v: Vec3) Vec3 {
    return v / splat(@sqrt(dot(v, v)));
}

const center: Vec3 = .{ 0, 0, -3.5 };
const radius = 1.0;
const floor_y = -1.0;

const ambient: Vec3 = .{ 0.25, 0.25, 0.3 };
const light_pos: Vec3 = .{ 1.6, 1.2, -2.2 };
const light_color: Vec3 = .{ 2.8, 2.0, 1.1 };
const light_radius = 5.0;
const background: Vec3 = .{ 16, 16, 24 };

/// The light falling on a point facing `normal`: ambient plus Lambert
/// times delve's falloff.
fn lightAt(pos: Vec3, normal: Vec3) Vec3 {
    const to_light = light_pos - pos;
    const d = @sqrt(dot(to_light, to_light));
    const lambert = @max(0, dot(normal, to_light) / d);
    const w = @max(0, 1 - (d / light_radius) * (d / light_radius));
    const h = d / 1.5;
    return ambient + light_color * splat(lambert * w * w / (1 + h * h));
}

/// The nearest t > 0 where the ray t * dir from the eye (at the origin)
/// meets the sphere: |t dir - center|^2 = radius^2, a quadratic in t.
fn hitSphere(dir: Vec3) ?f32 {
    const a = dot(dir, dir);
    const b = dot(dir, center);
    const c = dot(center, center) - radius * radius;
    const disc = b * b - a * c;
    if (disc < 0) return null;
    const t = (b - @sqrt(disc)) / a;
    return if (t > 0) t else null;
}

pub fn main(init: std.process.Init) !void {
    const w = 320;
    const h = 200;
    var pixels: [w * h][3]u8 = undefined;
    for (0..h) |y| {
        for (0..w) |x| {
            // The camera looks down -z; a vertical field of view of 53.13
            // degrees puts the screen's top edge at y = 0.5 at distance 1.
            const sx = ((@as(f32, @floatFromInt(x)) + 0.5) - w / 2.0) / h;
            const sy = (h / 2.0 - (@as(f32, @floatFromInt(y)) + 0.5)) / h;
            const dir: Vec3 = .{ sx, sy, -1 };
            var rgb = background;
            if (hitSphere(dir)) |t| {
                const p = dir * splat(t);
                // The normal of a sphere points away from its center.
                const n = (p - center) / splat(radius);
                rgb = Vec3{ 138, 138, 150 } * lightAt(p, n);
            } else if (dir[1] < 0) {
                // The floor, y = floor_y: t = floor_y / dir.y.
                const p = dir * splat(floor_y / dir[1]);
                rgb = Vec3{ 88, 80, 72 } * lightAt(p, .{ 0, 1, 0 });
            }
            const clamped = @round(std.math.clamp(rgb, splat(0), splat(255)));
            pixels[y * w + x] = .{ @intFromFloat(clamped[0]), @intFromFloat(clamped[1]), @intFromFloat(clamped[2]) };
        }
    }

    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "sphere.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print("P6\n{d} {d}\n255\n", .{ w, h });
    try writer.interface.writeAll(std.mem.sliceAsBytes(&pixels));
    try writer.interface.flush();
    std.debug.print("wrote sphere.ppm, {d}x{d}\n", .{ w, h });
}
