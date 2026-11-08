//! Collision is one question: are all of these cells on the board and empty?
const std = @import("std");

const cols = 10;
const rows = 6;
const Pos = struct { col: i32, row: i32 };

const Board = struct {
    /// cells[row][col], row 0 at the bottom; '.' is empty.
    cells: [rows][cols]u8 = @splat(@splat('.')),

    /// Top line first, sitting on the floor (like quadfall's Board.parse).
    fn parse(picture: []const u8) Board {
        var b: Board = .{};
        var lines = std.mem.splitBackwardsScalar(u8, picture, '\n');
        var row: usize = 0;
        while (lines.next()) |line| : (row += 1) @memcpy(&b.cells[row], line);
        return b;
    }

    fn inside(pos: Pos) bool {
        return pos.col >= 0 and pos.col < cols and pos.row >= 0 and pos.row < rows;
    }

    fn fits(b: *const Board, positions: []const Pos) bool {
        for (positions) |pos| {
            // `or` stops early, so cells[...] is only read for positions inside.
            if (!inside(pos) or b.cells[@intCast(pos.row)][@intCast(pos.col)] != '.') return false;
        }
        return true;
    }
};

/// A T pointing up, with the bottom-left corner of its 3x3 box at (col, row).
fn tAt(col: i32, row: i32) [4]Pos {
    return .{
        .{ .col = col + 1, .row = row + 2 }, .{ .col = col, .row = row + 1 },
        .{ .col = col + 1, .row = row + 1 }, .{ .col = col + 2, .row = row + 1 },
    };
}

const board: Board = .parse(
    \\..........
    \\..........
    \\..........
    \\.....#....
    \\....###...
    \\##.#######
);

test "open space fits" {
    try std.testing.expect(board.fits(&tAt(0, 0)));
    try std.testing.expect(board.fits(&tAt(5, 2)));
}

test "walls and floor do not fit" {
    try std.testing.expect(!board.fits(&tAt(-1, 2))); // left wall
    try std.testing.expect(!board.fits(&tAt(8, 2))); // right wall
    try std.testing.expect(!board.fits(&tAt(0, -2))); // below the floor
    try std.testing.expect(!board.fits(&tAt(0, 5))); // above the top
}

test "locked cells do not fit" {
    try std.testing.expect(!board.fits(&tAt(4, 1)));
    try std.testing.expect(!board.fits(&tAt(0, -1)));
}

test "a move is kept only if it fits" {
    // Push left until the next step would overlap: the block stops it...
    var col: i32 = 7;
    while (board.fits(&tAt(col - 1, 1))) col -= 1;
    try std.testing.expectEqual(6, col);
    // ...and one row higher, only the wall does.
    while (board.fits(&tAt(col - 1, 2))) col -= 1;
    try std.testing.expectEqual(0, col);
}
