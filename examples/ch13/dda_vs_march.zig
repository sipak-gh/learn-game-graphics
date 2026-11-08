//! Marching along a ray in small fixed steps can jump straight over the
//! corner of a wall. The DDA visits every cell the ray touches.
const std = @import("std");

const size = 10;

/// One wall cell, (5, 5), in an open room; the edge of the grid is wall.
fn isWall(x: i32, y: i32) bool {
    if (x <= 0 or y <= 0 or x >= size - 1 or y >= size - 1) return true;
    return x == 5 and y == 5;
}

fn cellOf(v: f32) i32 {
    return @intFromFloat(@floor(v));
}

const Result = struct { cell: [2]i32, t: f32, tests: usize };

fn dda(origin: [2]f32, dir: [2]f32) Result {
    var cell = [2]i32{ cellOf(origin[0]), cellOf(origin[1]) };
    var step: [2]i32 = undefined;
    var delta: [2]f32 = undefined;
    var next: [2]f32 = undefined;
    for (0..2) |i| {
        delta[i] = if (dir[i] == 0) std.math.inf(f32) else @abs(1 / dir[i]);
        const fc: f32 = @floatFromInt(cell[i]);
        step[i] = if (dir[i] < 0) -1 else 1;
        next[i] = if (dir[i] < 0) (origin[i] - fc) * delta[i] else (fc + 1 - origin[i]) * delta[i];
    }
    var tests: usize = 0;
    while (true) {
        const i: usize = if (next[0] < next[1]) 0 else 1;
        const t = next[i];
        next[i] += delta[i];
        cell[i] += step[i];
        tests += 1;
        if (isWall(cell[0], cell[1])) return .{ .cell = cell, .t = t, .tests = tests };
    }
}

fn march(origin: [2]f32, dir: [2]f32, dt: f32) Result {
    var t: f32 = 0;
    var tests: usize = 0;
    while (true) : (t += dt) {
        const cell = [2]i32{ cellOf(origin[0] + t * dir[0]), cellOf(origin[1] + t * dir[1]) };
        tests += 1;
        if (isWall(cell[0], cell[1])) return .{ .cell = cell, .t = t, .tests = tests };
    }
}

pub fn main() void {
    // A 45-degree ray that clips the top-right corner of cell (5, 5): it
    // is inside that cell only from (5.97, 5.00) to (6.00, 5.03).
    const origin = [2]f32{ 2.47, 1.5 };
    const dir = [2]f32{ std.math.sqrt1_2, std.math.sqrt1_2 };

    const results = [_]struct { name: []const u8, r: Result }{
        .{ .name = "DDA       ", .r = dda(origin, dir) },
        .{ .name = "march 0.1 ", .r = march(origin, dir, 0.1) },
        .{ .name = "march 0.01", .r = march(origin, dir, 0.01) },
    };
    for (results) |e| {
        std.debug.print("{s}: wall cell ({d}, {d}) at t = {d:.3}, {d} cells tested\n", .{
            e.name, e.r.cell[0], e.r.cell[1], e.r.t, e.r.tests,
        });
    }
}
