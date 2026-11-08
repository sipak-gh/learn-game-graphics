//! Why texture coordinates must be interpolated with perspective. A floor
//! lies 0.5 below the eye and runs from distance 1 to distance 5. Its
//! texture coordinate v is 1 at the near edge and 0 at the far edge. On the
//! screen (focal length 1) the near edge is 0.5 below the center and the
//! far edge 0.1 below. For rows between them, compare v blended straight
//! across the screen (affine) with v from v/w and 1/w (perspective-correct).
const std = @import("std");

const eye_height: f32 = 0.5;
const near_d: f32 = 1.0;
const far_d: f32 = 5.0;
const near_v: f32 = 1.0;
const far_v: f32 = 0.0;

pub fn main() void {
    const near_y = eye_height / near_d;
    const far_y = eye_height / far_d;
    const rows = 20;
    var worst: f32 = 0;
    var worst_row: usize = 0;
    std.debug.print(" row  screen y  distance  v true  v affine  v perspective  affine error\n", .{});
    for (0..rows) |i| {
        // t runs from 0 at the near edge to 1 at the far edge, evenly on
        // the screen: that is how the rasterizer's weights run.
        const t = @as(f32, @floatFromInt(i)) / (rows - 1);
        const y = std.math.lerp(near_y, far_y, t);
        const d = eye_height / y;
        const v_true = near_v + (far_v - near_v) * (d - near_d) / (far_d - near_d);
        const affine = std.math.lerp(near_v, far_v, t);
        // w is the distance here; v/w and 1/w are what is linear on screen.
        const v_over_w = std.math.lerp(near_v / near_d, far_v / far_d, t);
        const one_over_w = std.math.lerp(1 / near_d, 1 / far_d, t);
        const perspective = v_over_w / one_over_w;
        const err = affine - v_true;
        if (@abs(err) > @abs(worst)) {
            worst = err;
            worst_row = i;
        }
        std.debug.print("{d:>4}  {d:>8.3}  {d:>8.3}  {d:>6.3}  {d:>8.3}  {d:>13.3}  {d:>12.3}\n", .{
            i, y, d, v_true, affine, perspective, err,
        });
    }
    std.debug.print("largest affine error: {d:.3} at row {d} ({d:.0}% of the texture)\n", .{
        worst, worst_row, @abs(worst) * 100,
    });
}
