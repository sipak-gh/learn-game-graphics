//! A grid as an array of arrays: grid[row][col].
const std = @import("std");

const rows = 4;
const cols = 6;

pub fn main() void {
    // @splat fills an array with one value. The inner @splat makes a row,
    // the outer one makes `rows` copies of that row.
    var grid: [rows][cols]u8 = @splat(@splat('.'));

    grid[0][0] = 'A'; // row 0, column 0
    grid[1][4] = 'B'; // row 1, column 4
    grid[rows - 1][cols - 1] = 'C'; // the last cell

    // Fill column 2 from top to bottom.
    for (&grid) |*row| row[2] = '|';

    for (grid, 0..) |row, r| {
        std.debug.print("row {d}: {s}\n", .{ r, &row });
    }

    std.debug.print("@sizeOf = {d} bytes ({d} x {d})\n", .{ @sizeOf(@TypeOf(grid)), rows, cols });

    // Row-major: each row is stored whole, one after another, so grid[r][c]
    // is byte number r * cols + c of the grid's memory.
    const flat: *const [rows * cols]u8 = @ptrCast(&grid);
    std.debug.print("flat: {s}\n", .{flat});
    std.debug.print("grid[1][4] = {c}, flat[1 * cols + 4] = {c}\n", .{ grid[1][4], flat[1 * cols + 4] });
}
