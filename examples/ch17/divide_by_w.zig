//! What the perspective divide does to a point as it approaches the eye
//! plane (w = 0) and passes behind it (w < 0).
const std = @import("std");

/// NDC x to a pixel column on a 640-pixel-wide screen.
fn column(ndc_x: f32) f32 {
    return (ndc_x + 1) / 2 * 640;
}

pub fn main() void {
    // A point with clip x = 1, at shrinking w. On screen it is x / w.
    std.debug.print("   w      x/w      column\n", .{});
    for ([_]f32{ 1, 0.5, 0.1, 0.01, -0.01, -0.1, -1 }) |w| {
        const ndc = 1 / w;
        std.debug.print("{d:>6.2} {d:>8.1} {d:>10.0}\n", .{ w, ndc, column(ndc) });
    }

    // An edge from a = (x 0.5, w 2), in front, to b = (x 0.5, w -1), behind.
    // The points along it in clip space, and where each one lands.
    std.debug.print("\nalong the edge a -> b (a in front, b behind):\n", .{});
    std.debug.print("   t      w      x/w      column\n", .{});
    const a = [2]f32{ 0.5, 2 }; // x, w
    const b = [2]f32{ 0.5, -1 };
    for ([_]f32{ 0, 0.25, 0.5, 0.6, 0.66, 0.67, 0.7, 0.8, 1 }) |t| {
        const x = a[0] + (b[0] - a[0]) * t;
        const w = a[1] + (b[1] - a[1]) * t;
        std.debug.print("{d:>5.2} {d:>6.2} {d:>8.2} {d:>10.0}\n", .{ t, w, x / w, column(x / w) });
    }
}
