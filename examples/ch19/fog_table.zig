//! Exponential fog: the share of a surface's light that gets through
//! `d` units of air, exp(-density * d), for three densities. Then one
//! color seen through the fog at a few distances.
const std = @import("std");

fn visibility(d: f32, density: f32) f32 {
    return @exp(-density * d);
}

pub fn main() void {
    const densities = [_]f32{ 0.06, 0.12, 0.25 };
    const distances = [_]f32{ 1, 2, 5, 10, 20 };
    std.debug.print("density", .{});
    for (distances) |d| std.debug.print("  {d:>5.0}", .{d});
    std.debug.print("   half at\n", .{});
    for (densities) |density| {
        std.debug.print("{d:>7.2}", .{density});
        for (distances) |d| std.debug.print("  {d:>5.3}", .{visibility(d, density)});
        // exp(-density * d) = 1/2  <=>  d = ln 2 / density.
        std.debug.print("  {d:>6.2}\n", .{@log(2.0) / density});
    }

    // delve's fog: density 0.12 toward the clear color (16, 16, 24).
    const fog = [3]f32{ 16, 16, 24 };
    const wall = [3]f32{ 160, 90, 60 };
    std.debug.print("a brick wall through delve's fog:\n", .{});
    for (distances) |d| {
        const seen = visibility(d, 0.12);
        var rgb: [3]u8 = undefined;
        for (&rgb, fog, wall) |*c, f, w| c.* = @intFromFloat(@round(f + (w - f) * seen));
        std.debug.print("  d = {d:>2.0}: ({d:>3}, {d:>3}, {d:>3})\n", .{ d, rgb[0], rgb[1], rgb[2] });
    }
}
