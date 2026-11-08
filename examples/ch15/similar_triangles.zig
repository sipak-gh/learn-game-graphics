//! Perspective by hand and by matrix. A camera at the origin looks down -z.
//! By similar triangles a point (x, y, z) at distance d = -z lands on a
//! screen one unit away at (x/d, y/d); scaled so the screen's edges are at
//! -1 and 1, that is the point's NDC. The matrix puts d into w instead, and
//! the divide by w afterwards does the same thing.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// The projection matrix, written as rows (row r dotted with v gives lane r).
fn perspective(vfov: f32, aspect: f32, near: f32, far: f32) [4]Vec4 {
    const f = 1 / @tan(vfov / 2);
    return .{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, far / (near - far), near * far / (near - far) },
        .{ 0, 0, -1, 0 },
    };
}

fn mulVec(rows: [4]Vec4, v: Vec4) Vec4 {
    var out: Vec4 = undefined;
    inline for (0..4) |r| out[r] = @reduce(.Add, rows[r] * v);
    return out;
}

pub fn main() void {
    const vfov = 2 * std.math.atan(@as(f32, 0.5)); // 53.13 degrees
    const aspect: f32 = 640.0 / 400.0;
    const f = 1 / @tan(vfov / 2);
    const p = perspective(vfov, aspect, 0.05, 64);
    std.debug.print("f = 1/tan(vfov/2) = {d:.4}, f/aspect = {d:.4}\n\n", .{ f, f / aspect });

    const points = [_][3]f32{
        .{ 0, 0.5, -0.5 },
        .{ 0.4, 0.5, -1 },
        .{ -1, -0.5, -2 },
        .{ 2, 0.5, -4 },
        .{ 3, 0.25, -10 },
    };
    std.debug.print("   point (x, y, z)       d   x/d     y/d    | by hand: ndc x, y | matrix: clip (x, y, z, w)          -> ndc x, y\n", .{});
    for (points) |pt| {
        const x, const y, const z = pt;
        const d = -z;
        // By hand: similar triangles, then scale to the screen's edges.
        const hand_x = (f / aspect) * x / d;
        const hand_y = f * y / d;
        // By matrix: multiply, then divide by w.
        const clip = mulVec(p, .{ x, y, z, 1 });
        std.debug.print("({d:5.1}, {d:5.2}, {d:5.1})  {d:5.1}  {d:6.3}  {d:6.3}  | {d:7.4}, {d:7.4}  | ({d:7.4}, {d:7.4}, {d:7.4}, {d:5.1}) -> {d:7.4}, {d:7.4}\n", .{
            x,       y,       z,       d,       x / d,             y / d,             hand_x, hand_y,
            clip[0], clip[1], clip[2], clip[3], clip[0] / clip[3], clip[1] / clip[3],
        });
    }
}
