//! Blending lattice values with a straight line versus smoothstep.
//! Three lattice values a, b, c at x = 0, 1, 2. With linear blending the
//! slope jumps at x = 1 (a visible crease in a texture); with smoothstep
//! the slope is 0 on both sides of every lattice point.
const std = @import("std");

fn smooth(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

fn blend(values: [3]f32, x: f32, comptime f: fn (f32) f32) f32 {
    const i: usize = @min(1, @as(usize, @intFromFloat(@floor(x))));
    const t = x - @as(f32, @floatFromInt(i));
    return std.math.lerp(values[i], values[i + 1], f(t));
}

fn linear(t: f32) f32 {
    return t;
}

pub fn main() void {
    const values = [3]f32{ 0.2, 0.9, 0.4 };
    std.debug.print("   x   linear  smooth\n", .{});
    var k: usize = 0;
    while (k <= 8) : (k += 1) {
        const x = @as(f32, @floatFromInt(k)) * 0.25;
        std.debug.print("{d:>4.2}  {d:>6.3}  {d:>6.3}\n", .{ x, blend(values, x, linear), blend(values, x, smooth) });
    }

    // Slopes just left and just right of the lattice point x = 1.
    const e = 0.001;
    inline for (.{ .{ "linear", linear }, .{ "smooth", smooth } }) |pair| {
        const left = (blend(values, 1, pair[1]) - blend(values, 1 - e, pair[1])) / e;
        const right = (blend(values, 1 + e, pair[1]) - blend(values, 1, pair[1])) / e;
        std.debug.print("{s}: slope left of x=1 {d:>6.3}, right of x=1 {d:>6.3}\n", .{ pair[0], left, right });
    }
}
