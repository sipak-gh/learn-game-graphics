//! What the divide by w does to a point that passes the eye. The camera is
//! at the origin looking down -z; the point is half a unit to the right and
//! moves from 2 units in front of the eye to 2 units behind it.
const std = @import("std");

const near: f32 = 0.05;

pub fn main() void {
    const f: f32 = 2; // 1/tan(vfov/2) for delve's 53.13 degrees
    const aspect: f32 = 1.6;
    std.debug.print("     z      w    ndc x      screen x   project\n", .{});
    for ([_]f32{ -2, -1, -0.5, -0.2, -0.1, -0.05, -0.01, 0.01, 0.1, 0.5, 1, 2 }) |z| {
        // Rows 1 and 4 of the projection matrix: x_clip = (f/aspect) x, w = -z.
        const x_clip = f / aspect * 0.5;
        const w = -z;
        const ndc_x = x_clip / w;
        const sx = (ndc_x + 1) / 2 * 640;
        const verdict = if (w < near) "null (behind the near plane)" else if (@abs(ndc_x) <= 1) "on screen" else "off screen";
        std.debug.print("{d:6.2}  {d:5.2}  {d:8.2}  {d:10.1}   {s}\n", .{ z, w, ndc_x, sx, verdict });
    }
}
