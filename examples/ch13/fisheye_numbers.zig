//! A flat wall straight ahead, 3 units in front of the camera. Using the
//! distance from the eye makes its edges shrink (a bulge); the distance
//! along the view direction keeps it the same height everywhere.
const std = @import("std");

pub fn main() void {
    const width = 640;
    const height: f32 = 400;
    const wall_dist: f32 = 3; // the wall is the line x = 3, the camera looks along +x

    std.debug.print("column  camera_x  eye dist  perp dist  height(eye)  height(perp)\n", .{});
    for ([_]usize{ 0, 80, 160, 240, 320, 400, 480, 560, 639 }) |x| {
        const fx: f32 = @floatFromInt(x);
        const camera_x = 2 * (fx + 0.5) / width - 1;
        // ray = (1, 0.8 * camera_x); it reaches x = 3 at t = 3.
        const ray_len = @sqrt(1 + 0.64 * camera_x * camera_x);
        const t = wall_dist; // the DDA's t: ray.x is 1
        const eye = t * ray_len;
        std.debug.print("{d:>6}  {d:>8.3}  {d:>8.3}  {d:>9.3}  {d:>11.1}  {d:>12.1}\n", .{
            x, camera_x, eye, t, height / eye, height / t,
        });
    }
    // The cosine fix used by many tutorials is the same number:
    // eye distance * cos(angle) = t * |ray| * (1 / |ray|) = t.
    const camera_x: f32 = 2 * (0 + 0.5) / @as(f32, width) - 1;
    const angle = std.math.atan(0.8 * camera_x);
    std.debug.print("\ncolumn 0: eye dist * cos(angle) = {d:.3}\n", .{wall_dist * @sqrt(1 + 0.64 * camera_x * camera_x) * @cos(angle)});
}
