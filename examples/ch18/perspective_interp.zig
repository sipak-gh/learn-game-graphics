//! Interpolating along an edge that recedes from the eye. A value that
//! is linear along the edge in the world (u, from 0 to 1) is not linear
//! on the screen, but u/w and 1/w are; so is the depth z/w.
const std = @import("std");

const near = 0.05;
const far = 64.0;

/// The depth delve stores: 0 at the near plane, 1 at the far plane.
fn depth(w: f32) f32 {
    return far / (far - near) * (1 - near / w);
}

pub fn main() void {
    // An edge on the floor: from x = -1 at distance w = 1 to x = 2 at
    // w = 4. On the screen x/w goes from -1 to 0.5.
    const xa: f32 = -1;
    const wa: f32 = 1;
    const xb: f32 = 2;
    const wb: f32 = 4;
    std.debug.print("    s  screen x  u (lerp)  u (1/w)    true u  depth (lerp)  true depth\n", .{});
    for (0..9) |i| {
        // s: how far along the edge on the screen.
        const s = @as(f32, @floatFromInt(i)) / 8;
        const sx = std.math.lerp(xa / wa, xb / wb, s);
        // Where the world edge (xa + t(xb - xa), wa + t(wb - wa)) has
        // x/w = sx: solve for t.
        const t = (sx * wa - xa) / ((xb - xa) - sx * (wb - wa));
        const w = std.math.lerp(wa, wb, t);
        // u is 0 at a and 1 at b: u/w is 0/wa and 1/wb at the ends.
        const u_correct = std.math.lerp(0 / wa, 1 / wb, s) / std.math.lerp(1 / wa, 1 / wb, s);
        const z_lerp = std.math.lerp(depth(wa), depth(wb), s);
        std.debug.print("{d:>5.3} {d:>9.4} {d:>9.4} {d:>8.4} {d:>9.4} {d:>13.6} {d:>11.6}\n", .{
            s, sx, s, u_correct, t, z_lerp, depth(w),
        });
    }
}
