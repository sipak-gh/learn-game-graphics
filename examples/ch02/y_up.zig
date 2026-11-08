//! Board rows count up from the floor; screen pixels count down from the top.
const std = @import("std");

const visible_rows = 20;
const cell_size = 32;
const board_x = 240; // pixel position of the board's top-left corner
const board_y = 40;

/// Pixel x of the left edge of a column.
fn cellX(col: i32) i32 {
    return board_x + col * cell_size;
}

/// Pixel y of the top edge of a row: flip the row, then scale.
fn cellY(row: i32) i32 {
    return board_y + (visible_rows - 1 - row) * cell_size;
}

pub fn main() void {
    std.debug.print("{s:>4}  {s:>6}  {s}\n", .{ "row", "flip", "pixel y (top edge)" });
    const sample_rows = [_]i32{ 0, 1, 2, 18, 19, 20, 21 };
    for (sample_rows) |row| {
        const note = if (row >= visible_rows) "  hidden: above the window's board" else "";
        std.debug.print("{d:>4}  {d:>6}  {d:>4}{s}\n", .{ row, visible_rows - 1 - row, cellY(row), note });
    }
    std.debug.print("col 0 -> x {d}, col 9 -> x {d}\n", .{ cellX(0), cellX(9) });
    std.debug.print("bottom edge of the board: y {d}\n", .{board_y + visible_rows * cell_size});
}
