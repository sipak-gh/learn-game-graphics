//! Which way is right? With y up and the map's y as the world's z, the
//! camera's right is forward x up. The other order, up x forward, points
//! left. The map's own right is perp(dir) = (-dir.y, dir.x).
const std = @import("std");

const Vec3 = @Vector(3, f32);

fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn normalize(v: Vec3) Vec3 {
    return v / @as(Vec3, @splat(@sqrt(@reduce(.Add, v * v))));
}

fn forward(yaw: f32, pitch: f32) Vec3 {
    return tidy(.{ @cos(yaw) * @cos(pitch), @sin(pitch), @sin(yaw) * @cos(pitch) });
}

/// Rounds away float noise like cos(90 deg) = -4.4e-8, and turns -0 into 0.
fn tidy(v: Vec3) Vec3 {
    return @round(v * @as(Vec3, @splat(1e6))) / @as(Vec3, @splat(1e6)) + @as(Vec3, @splat(0));
}

pub fn main() void {
    const up: Vec3 = .{ 0, 1, 0 };
    for ([_]f32{ 0, 90 }) |deg| {
        const yaw = std.math.degreesToRadians(deg);
        const f = forward(yaw, 0);
        const dir = [2]f32{ f[0], f[2] }; // the map direction (cos yaw, sin yaw)
        std.debug.print("yaw {d:>2}: forward ({d:.0}, {d:.0}, {d:.0})\n", .{ deg, f[0], f[1], f[2] });
        const fu = tidy(cross(f, up));
        const uf = tidy(cross(up, f));
        std.debug.print("  forward x up = ({d:.0}, {d:.0}, {d:.0})\n", .{ fu[0], fu[1], fu[2] });
        std.debug.print("  up x forward = ({d:.0}, {d:.0}, {d:.0})\n", .{ uf[0], uf[1], uf[2] });
        std.debug.print("  map perp(dir) = ({d:.0}, {d:.0}) -> world ({d:.0}, 0, {d:.0})\n", .{ 0 - dir[1], dir[0], 0 - dir[1], dir[0] });
    }

    // Tilted up 30 degrees: right stays level, the camera's up leans back.
    const f = forward(0, std.math.degreesToRadians(30.0));
    const r = normalize(cross(f, up));
    const u = cross(r, f);
    std.debug.print("pitch 30: forward ({d:.3}, {d:.3}, {d:.3})  right ({d:.0}, {d:.0}, {d:.0})  camera up ({d:.3}, {d:.3}, {d:.3})\n", .{
        f[0], f[1], f[2], r[0], r[1], r[2], u[0], u[1], u[2],
    });
}
