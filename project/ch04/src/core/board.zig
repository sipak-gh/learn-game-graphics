//! The playfield: a grid of cells, 10 columns wide.
const std = @import("std");

pub const cols = 10;
/// Rows the player sees.
pub const visible_rows = 20;
/// Two hidden rows above the visible ones give new pieces room to appear.
pub const rows = visible_rows + 2;

/// What fills one cell. A locked piece keeps its letter, so it keeps its color.
pub const Cell = enum(u8) {
    empty,
    i,
    o,
    t,
    s,
    z,
    j,
    l,
    garbage,

    /// The character for this cell in a board picture.
    pub fn char(cell: Cell) u8 {
        return ".IOTSZJL#"[@backingInt(cell)];
    }

    pub fn fromChar(c: u8) ?Cell {
        const index = std.mem.findScalar(u8, ".IOTSZJL#", c) orelse return null;
        return @fromBackingInt(@intCast(index));
    }
};

/// A cell position. Column 0 is the left wall and row 0 is the bottom row,
/// so "up" means a larger row. Signed, because a position may be off the board.
pub const Pos = struct {
    col: i32,
    row: i32,

    pub fn add(a: Pos, b: Pos) Pos {
        return .{ .col = a.col + b.col, .row = a.row + b.row };
    }
};

pub const Board = struct {
    /// cells[row][col]; cells[0] is the bottom row.
    cells: [rows][cols]Cell = @splat(@splat(.empty)),

    pub const empty: Board = .{};

    pub fn inside(pos: Pos) bool {
        return pos.col >= 0 and pos.col < cols and pos.row >= 0 and pos.row < rows;
    }

    pub fn get(board: *const Board, pos: Pos) Cell {
        std.debug.assert(inside(pos));
        return board.cells[@intCast(pos.row)][@intCast(pos.col)];
    }

    pub fn set(board: *Board, pos: Pos, cell: Cell) void {
        std.debug.assert(inside(pos));
        board.cells[@intCast(pos.row)][@intCast(pos.col)] = cell;
    }

    /// True if every position is on the board and empty: a piece covering
    /// them would not overlap a wall, the floor, or a locked cell.
    pub fn fits(board: *const Board, positions: []const Pos) bool {
        for (positions) |pos| {
            if (!inside(pos) or board.get(pos) != .empty) return false;
        }
        return true;
    }

    /// Builds a board from a picture such as "..IIII....\n#########.".
    /// The picture is drawn top row first and sits on the floor: its last
    /// line is row 0. Meant for tests and demos, so a bad picture panics
    /// (a compile error when called at comptime).
    pub fn parse(picture: []const u8) Board {
        var board: Board = .empty;
        const height = std.mem.countScalar(u8, picture, '\n') + 1;
        if (height > rows) @panic("board picture has too many rows");
        var lines = std.mem.splitScalar(u8, picture, '\n');
        var row: i32 = @intCast(height - 1);
        while (lines.next()) |line| : (row -= 1) {
            if (line.len != cols) @panic("board picture rows must be 10 characters wide");
            for (line, 0..) |c, col| {
                const cell = Cell.fromChar(c) orelse @panic("unknown character in board picture");
                board.set(.{ .col = @intCast(col), .row = row }, cell);
            }
        }
        return board;
    }

    /// Writes the board as a picture (the format `parse` reads), from the
    /// highest non-empty row down to row 0. Use it with `{f}`.
    pub fn format(board: Board, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var top: usize = rows;
        while (top > 0 and board.rowIsEmpty(top - 1)) top -= 1;
        var row = top;
        while (row > 0) {
            row -= 1;
            for (board.cells[row]) |cell| try w.writeByte(cell.char());
            if (row > 0) try w.writeByte('\n');
        }
    }

    fn rowIsEmpty(board: *const Board, row: usize) bool {
        for (board.cells[row]) |cell| {
            if (cell != .empty) return false;
        }
        return true;
    }
};

test "a new board is empty" {
    const board: Board = .empty;
    try std.testing.expectEqual(Cell.empty, board.get(.{ .col = 0, .row = 0 }));
    try std.testing.expectFmt("", "{f}", .{board});
}

test "inside" {
    try std.testing.expect(Board.inside(.{ .col = 0, .row = 0 }));
    try std.testing.expect(Board.inside(.{ .col = 9, .row = 21 }));
    try std.testing.expect(!Board.inside(.{ .col = -1, .row = 0 }));
    try std.testing.expect(!Board.inside(.{ .col = 10, .row = 0 }));
    try std.testing.expect(!Board.inside(.{ .col = 0, .row = -1 }));
    try std.testing.expect(!Board.inside(.{ .col = 0, .row = 22 }));
}

test "row 0 is the bottom row" {
    var board: Board = .empty;
    board.set(.{ .col = 0, .row = 0 }, .j);
    board.set(.{ .col = 9, .row = 1 }, .l);
    try std.testing.expectFmt(
        \\.........L
        \\J.........
    , "{f}", .{board});
}

test "fits" {
    const board: Board = .parse(
        \\..........
        \\#.........
    );
    try std.testing.expect(board.fits(&.{ .{ .col = 1, .row = 0 }, .{ .col = 0, .row = 1 } }));
    try std.testing.expect(!board.fits(&.{.{ .col = 0, .row = 0 }})); // locked cell
    try std.testing.expect(!board.fits(&.{.{ .col = -1, .row = 1 }})); // left wall
    try std.testing.expect(!board.fits(&.{.{ .col = 3, .row = -1 }})); // floor
}

test "parse and format round-trip" {
    const picture =
        \\....T.....
        \\...TTT..OO
        \\#########.
    ;
    const board: Board = comptime .parse(picture);
    try std.testing.expectEqual(Cell.t, board.get(.{ .col = 4, .row = 2 }));
    try std.testing.expectEqual(Cell.garbage, board.get(.{ .col = 0, .row = 0 }));
    try std.testing.expectEqual(Cell.empty, board.get(.{ .col = 9, .row = 0 }));
    try std.testing.expectFmt(picture, "{f}", .{board});
}
