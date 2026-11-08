//! Follows one ray through a small grid with a DDA and prints every grid
//! line it crosses, until it enters a wall cell.
const std = @import("std");

const grid = [_][]const u8{
    "##########",
    "#........#",
    "#......#.#",
    "#........#",
    "#........#",
    "##########",
};

fn isWall(x: i32, y: i32) bool {
    if (x < 0 or y < 0 or y >= grid.len or x >= grid[0].len) return true;
    return grid[@intCast(y)][@intCast(x)] == '#';
}

pub fn main() void {
    const origin = [2]f32{ 1.5, 4.5 };
    const angle: f32 = std.math.degreesToRadians(-20.0);
    const dir = [2]f32{ @cos(angle), @sin(angle) };

    var cell = [2]i32{ @intFromFloat(@floor(origin[0])), @intFromFloat(@floor(origin[1])) };
    var step: [2]i32 = undefined;
    var delta: [2]f32 = undefined; // t to cross one whole cell
    var next: [2]f32 = undefined; // t of the next x line and the next y line
    for (0..2) |i| {
        delta[i] = if (dir[i] == 0) std.math.inf(f32) else @abs(1 / dir[i]);
        const fc: f32 = @floatFromInt(cell[i]);
        if (dir[i] < 0) {
            step[i] = -1;
            next[i] = (origin[i] - fc) * delta[i];
        } else {
            step[i] = 1;
            next[i] = (fc + 1 - origin[i]) * delta[i];
        }
    }
    std.debug.print("dir = ({d:.3}, {d:.3})  start cell ({d}, {d})\n", .{ dir[0], dir[1], cell[0], cell[1] });
    std.debug.print("delta = ({d:.3}, {d:.3})  first crossings next = ({d:.3}, {d:.3})\n\n", .{
        delta[0], delta[1], next[0], next[1],
    });

    var n: usize = 1;
    while (true) : (n += 1) {
        // The nearer of the two next crossings is the next grid line.
        const i: usize = if (next[0] < next[1]) 0 else 1;
        const t = next[i];
        next[i] += delta[i];
        cell[i] += step[i];
        const px = origin[0] + t * dir[0];
        const py = origin[1] + t * dir[1];
        const wall = isWall(cell[0], cell[1]);
        std.debug.print("{d}: t = {d:.3}  cross {s} line at ({d:.3}, {d:.3})  -> cell ({d}, {d}){s}\n", .{
            n,                          t, if (i == 0) "x" else "y", px, py, cell[0], cell[1],
            if (wall) "  WALL" else "",
        });
        if (wall) break;
    }
}
