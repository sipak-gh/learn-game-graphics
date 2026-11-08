//! Where an edge crosses a plane of the view volume, computed in clip
//! space: t = d(a) / (d(a) - d(b)). The same t is the right fraction for
//! the world position and for any value carried along the edge.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// delve's projection: vertical FOV 2 atan(0.5), aspect 640/400,
/// near 0.05, far 64. Clip = M * (x, y, z, 1) for a point in view space.
fn project(p: [3]f32) Vec4 {
    const n = 0.05;
    const f = 64.0;
    const x, const y, const z = p;
    return .{ 2.0 / 1.6 * x, 2 * y, f / (n - f) * z + n * f / (n - f), -z };
}

fn lerp(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return a + (b - a) * @as(@TypeOf(a), @splat(t));
}

fn lerp3(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
    const v = lerp(@as(@Vector(3, f32), a), @as(@Vector(3, f32), b), t);
    return v;
}

pub fn main() void {
    // View space: the eye at the origin, looking down -z.
    // a is 2 units ahead, b is 1 unit behind the eye.
    const a_view = [3]f32{ 0.4, 0.1, -2 };
    const b_view = [3]f32{ -0.6, 0.3, 1 };
    const a = project(a_view);
    const b = project(b_view);
    std.debug.print("a clip = {any}\nb clip = {any}\n", .{ a, b });

    // The near plane's distance is z; find where it is zero.
    const t = a[2] / (a[2] - b[2]);
    const cut = lerp(a, b, t);
    std.debug.print("near: t = {d:.6}, crossing = {any}\n", .{ t, cut });

    // The same fraction of the way along the edge *in the world*, projected:
    const cut_world = project(lerp3(a_view, b_view, t));
    std.debug.print("world point at t, projected = {any}\n", .{cut_world});

    // A value carried along the edge (say a brightness 0 at a, 1 at b)
    // is linear in the world, so at the crossing it is t as well.
    const value = lerp(@as(@Vector(1, f32), .{0}), .{1}, t)[0];
    std.debug.print("value at the crossing = {d:.6}\n\n", .{value});

    // Now an edge entirely in front of the eye that leaves the screen on
    // the right. Its t in clip space vs the "same" t taken from the
    // projected (divided) positions.
    const c_view = [3]f32{ 0.5, 0, -1 };
    const d_view = [3]f32{ 6, 0, -5 };
    const c = project(c_view);
    const d = project(d_view);
    const dc = c[3] - c[0]; // right plane: w - x
    const dd = d[3] - d[0];
    const t_clip = dc / (dc - dd);
    const ndc_c = c[0] / c[3];
    const ndc_d = d[0] / d[3];
    const t_screen = (1 - ndc_c) / (ndc_d - ndc_c);
    std.debug.print("right edge: ndc x from {d:.4} to {d:.4}\n", .{ ndc_c, ndc_d });
    std.debug.print("t in clip space   = {d:.4}\n", .{t_clip});
    std.debug.print("t on the screen   = {d:.4}\n", .{t_screen});
    for ([_]f32{ t_clip, t_screen }) |tt| {
        const p = project(lerp3(c_view, d_view, tt));
        std.debug.print("world point at t = {d:.4} lands at ndc x = {d:.4}\n", .{ tt, p[0] / p[3] });
    }
}
