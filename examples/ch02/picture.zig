//! A small grid built from a picture at compile time.
const std = @import("std");

const cols = 5;
const max_rows = 4;

const Grid = struct {
    /// cells[0] is the BOTTOM row.
    cells: [max_rows][cols]u8 = @splat(@splat('.')),

    /// The picture's first line is the top row; its last line is row 0.
    fn parse(picture: []const u8) Grid {
        var grid: Grid = .{};
        const height = std.mem.countScalar(u8, picture, '\n') + 1;
        if (height > max_rows) @panic("picture has too many rows");
        var lines = std.mem.splitScalar(u8, picture, '\n');
        var row = height;
        while (lines.next()) |line| {
            row -= 1;
            if (line.len != cols) @panic("picture rows must be 5 characters wide");
            for (line, 0..) |c, col| grid.cells[row][col] = c;
        }
        return grid;
    }
};

// A multi-line string literal: each line starts with \\ and the final
// newline is not included.
const pyramid =
    \\..#..
    \\.###.
    \\#####
;

// A container-level constant is computed while compiling, so parse runs
// inside the compiler and the program only contains the finished grid.
const pyramid_grid = Grid.parse(pyramid);

pub fn main() void {
    std.debug.print("picture is {d} bytes, {d} lines\n", .{ pyramid.len, std.mem.countScalar(u8, pyramid, '\n') + 1 });
    for (pyramid_grid.cells, 0..) |row, r| {
        std.debug.print("cells[{d}] = {s}\n", .{ r, &row });
    }
}
