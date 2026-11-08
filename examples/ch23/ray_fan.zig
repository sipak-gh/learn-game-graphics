//! Which cells of a grid map can the eye see? Cast a fan of rays across
//! the view, as seen from above, and follow each through the grid with a
//! DDA until it enters a wall. Mark every cell a ray passes through (*) and
//! the eight cells around it (+). Prints the map for a dense fan (1024 rays
//! per radian, as delve casts) and a sparse one, and how many rays a fan
//! needs when looking up.
const std = @import("std");

const map_text = [_][]const u8{
    "########################",
    "#......#...............#",
    "#......#....######.....#",
    "#..........#.....#.....#",
    "#......#...#.....#.....#",
    "####.###...#.....#######",
    "#......#...###.###.....#",
    "#......................#",
    "#......#...............#",
    "########################",
};
const width = map_text[0].len;
const height = map_text.len;

const Mark = enum { none, near, crossed };

fn isWall(x: i32, y: i32) bool {
    if (x < 0 or y < 0 or x >= width or y >= height) return true;
    return map_text[@intCast(y)][@intCast(x)] == '#';
}

/// Follows the ray from `origin` along `dir`, calling `visit` for each
/// cell before the wall it stops at.
fn cast(origin: [2]f32, dir: [2]f32, marks: *[height][width]Mark) void {
    const inf = std.math.inf(f32);
    const delta = [2]f32{
        if (dir[0] == 0) inf else @abs(1 / dir[0]),
        if (dir[1] == 0) inf else @abs(1 / dir[1]),
    };
    var cell = [2]i32{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    var next: [2]f32 = undefined;
    for (0..2) |i| {
        const fc: f32 = @floatFromInt(cell[i]);
        step[i] = if (dir[i] < 0) -1 else 1;
        next[i] = if (dir[i] < 0) (origin[i] - fc) * delta[i] else (fc + 1 - origin[i]) * delta[i];
    }
    while (true) {
        visit(marks, cell);
        const i: usize = if (next[0] < next[1]) 0 else 1;
        next[i] += delta[i];
        cell[i] += step[i];
        if (isWall(cell[0], cell[1])) return;
    }
}

/// Marks `cell` as crossed and its neighbors as near.
fn visit(marks: *[height][width]Mark, cell: [2]i32) void {
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            const x = cell[0] + dx;
            const y = cell[1] + dy;
            if (x < 0 or y < 0 or x >= width or y >= height) continue;
            const m = &marks[@intCast(y)][@intCast(x)];
            if (dx == 0 and dy == 0) m.* = .crossed else if (m.* == .none) m.* = .near;
        }
    }
}

/// Half the angle the view covers on the floor (see visibility.zig), or
/// null when it covers all the way around.
fn groundSpan(pitch: f32) ?f32 {
    const tan_v = 0.5;
    const tan_h = 0.8;
    const ahead = @cos(pitch) - tan_v * @abs(@sin(pitch));
    if (ahead <= 0) return null;
    return std.math.atan(tan_h / ahead);
}

fn fan(eye: [2]f32, yaw: f32, pitch: f32, rays_per_radian: f32) void {
    var marks: [height][width]Mark = @splat(@splat(.none));
    const half = groundSpan(pitch) orelse std.math.pi;
    const n: usize = @intFromFloat(@ceil(2 * half * rays_per_radian));
    for (0..n + 1) |k| {
        const a = yaw - half + 2 * half * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n));
        cast(eye, .{ @cos(a), @sin(a) }, &marks);
    }
    var crossed: usize = 0;
    var near: usize = 0;
    std.debug.print("{d} rays per radian: {d} rays\n", .{ rays_per_radian, n + 1 });
    for (map_text, marks, 0..) |row, mark_row, y| {
        std.debug.print("  ", .{});
        for (row, mark_row, 0..) |c, m, x| {
            const at_eye = x == @as(usize, @intFromFloat(eye[0])) and y == @as(usize, @intFromFloat(eye[1]));
            const shown: u8 = if (at_eye) '@' else switch (m) {
                .crossed => '*',
                .near => '+',
                .none => c,
            };
            crossed += @intFromBool(m == .crossed);
            near += @intFromBool(m == .near);
            std.debug.print("{c}", .{shown});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("  crossed {d}, near {d}\n", .{ crossed, near });
}

pub fn main() void {
    // Standing in the west room, looking east (yaw 0, x right, y down).
    const eye = [2]f32{ 2.5, 3.5 };
    fan(eye, 0, 0, 1024);
    fan(eye, 0, 0, 4);

    std.debug.print("rays for the whole view, 1024 per radian:\n", .{});
    for ([_]f32{ 0, 0.5, 1.0, 1.2 }) |pitch| {
        if (groundSpan(pitch)) |half| {
            const n: usize = @intFromFloat(@ceil(2 * half * 1024));
            std.debug.print("  pitch {d:.1}: half span {d:.3} rad, {d} rays\n", .{ pitch, half, n + 1 });
        } else {
            std.debug.print("  pitch {d:.1}: all around, {d} rays\n", .{ pitch, @as(usize, @intFromFloat(@ceil(std.math.tau * 1024.0))) + 1 });
        }
    }
}
