//! Turning a shape a quarter turn clockwise inside an n-by-n box:
//! the cell at (col, row) moves to (row, n-1-col). Row 0 is the bottom.
const std = @import("std");

const Pos = struct { col: i32, row: i32 };
const Shape = [4]Pos;

fn rotateCw(shape: Shape, n: i32) Shape {
    var out: Shape = undefined;
    for (shape, &out) |p, *q| q.* = .{ .col = p.row, .row = n - 1 - p.col };
    return out;
}

/// Prints the box top row first, so that "up" is up on the screen.
fn show(shape: Shape, n: i32) void {
    var row = n - 1;
    while (row >= 0) : (row -= 1) {
        var col: i32 = 0;
        while (col < n) : (col += 1) {
            var filled = false;
            for (shape) |p| filled = filled or (p.col == col and p.row == row);
            std.debug.print("{c}", .{@as(u8, if (filled) '#' else '.')});
        }
        std.debug.print("\n", .{});
    }
}

pub fn main() void {
    // The T in its spawn state, pointing up, in a 3x3 box.
    var t: Shape = .{
        .{ .col = 1, .row = 2 },
        .{ .col = 0, .row = 1 },
        .{ .col = 1, .row = 1 },
        .{ .col = 2, .row = 1 },
    };
    const next = rotateCw(t, 3);
    for (t, next) |from, to| {
        std.debug.print("({d},{d}) -> ({d},{d})\n", .{ from.col, from.row, to.col, to.row });
    }
    for (0..5) |turn| {
        std.debug.print("turn {d}:\n", .{turn});
        show(t, 3);
        t = rotateCw(t, 3);
    }
}
