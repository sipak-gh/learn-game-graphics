//! A complete ray caster that draws into text: 80 columns by 24 rows.
//! Walls are drawn with denser characters when they are closer.
const std = @import("std");

const map = [_][]const u8{
    "################",
    "#..............#",
    "#..##......%%..#",
    "#..##......%%..#",
    "#..............#",
    "#.......#......#",
    "#.......#......#",
    "#..............#",
    "################",
};

fn isWall(x: i32, y: i32) bool {
    if (x < 0 or y < 0 or y >= map.len or x >= map[0].len) return true;
    return map[@intCast(y)][@intCast(x)] != '.';
}

/// The DDA from the chapter: returns t, the distance along the view direction.
fn cast(origin: [2]f32, dir: [2]f32) f32 {
    var cell = [2]i32{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    var delta: [2]f32 = undefined;
    var next: [2]f32 = undefined;
    for (0..2) |i| {
        delta[i] = if (dir[i] == 0) std.math.inf(f32) else @abs(1 / dir[i]);
        const fc: f32 = @floatFromInt(cell[i]);
        step[i] = if (dir[i] < 0) -1 else 1;
        next[i] = if (dir[i] < 0) (origin[i] - fc) * delta[i] else (fc + 1 - origin[i]) * delta[i];
    }
    while (true) {
        const i: usize = if (next[0] < next[1]) 0 else 1;
        const t = next[i];
        next[i] += delta[i];
        cell[i] += step[i];
        if (isWall(cell[0], cell[1])) return t;
    }
}

pub fn main() void {
    const cols = 80;
    const rows = 24;
    const plane_scale: f32 = 0.8;
    // A text cell is about twice as tall as it is wide. Across, the plane
    // maps to cols / (2 * 0.8) = 50 cells per unit; up, half of that.
    const rows_per_unit: f32 = cols / (2 * plane_scale) / 2;

    const pos = [2]f32{ 6.0, 4.0 };
    const yaw: f32 = std.math.degreesToRadians(-10.0);
    const dir = [2]f32{ @cos(yaw), @sin(yaw) };
    const plane = [2]f32{ -dir[1] * plane_scale, dir[0] * plane_scale };

    var screen: [rows][cols]u8 = undefined;
    for (0..cols) |x| {
        const camera_x = 2 * (@as(f32, @floatFromInt(x)) + 0.5) / cols - 1;
        const t = cast(pos, .{ dir[0] + plane[0] * camera_x, dir[1] + plane[1] * camera_x });
        const half = rows_per_unit / t / 2;
        const char: u8 = if (t < 2.5) '#' else if (t < 5) '+' else ':';
        for (0..rows) |y| {
            const center = @as(f32, @floatFromInt(y)) + 0.5 - rows / 2.0;
            screen[y][x] = if (@abs(center) < half) char else if (center > 0) '.' else ' ';
        }
    }
    for (screen) |line| std.debug.print("{s}\n", .{&line});
}
