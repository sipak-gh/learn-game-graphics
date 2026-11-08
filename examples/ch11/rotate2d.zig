//! Rotating (1, 0) in 30-degree steps. With y pointing down the screen,
//! a positive angle turns clockwise.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// `v` rotated by `angle` radians, turning from +x toward +y.
fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ c * v[0] - s * v[1], s * v[0] + c * v[1] };
}

pub fn main() void {
    const step = std.math.degreesToRadians(30.0);
    var v: Vec2 = .{ 1, 0 };
    // Plot the tip of each step as a letter on a y-down character grid.
    var grid: [13][27]u8 = @splat(@splat(' '));
    grid[6][13] = '+';
    for (0..12) |i| {
        const deg = i * 30;
        std.debug.print("{c} {d:>3} deg: ({d:>6.3}, {d:>6.3})\n", .{ 'a' + @as(u8, @intCast(i)), deg, v[0], v[1] });
        // Column = x (two characters per unit so the circle looks round),
        // row = y, growing downward like the screen.
        const col: usize = @intFromFloat(@round(13 + 12 * v[0]));
        const row: usize = @intFromFloat(@round(6 + 6 * v[1]));
        grid[row][col] = 'a' + @as(u8, @intCast(i));
        v = rotate(v, step); // rotate the previous result: errors add up
    }
    for (grid) |row| std.debug.print("|{s}|\n", .{&row});
    std.debug.print("after 12 steps: ({d}, {d})\n", .{ v[0], v[1] });

    // Rotating step by step lets rounding errors pile up. Computing each
    // direction from its angle does not.
    var w: Vec2 = .{ 1, 0 };
    const tiny = std.math.degreesToRadians(0.1);
    for (0..36_000) |_| w = rotate(w, tiny);
    std.debug.print("after 36000 steps of 0.1 deg: ({d}, {d}), length {d}\n", .{ w[0], w[1], @sqrt(w[0] * w[0] + w[1] * w[1]) });
}
