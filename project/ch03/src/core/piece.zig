//! The seven tetrominoes and their rotation states, following the Super
//! Rotation System (SRS) used by modern falling-block games.
const std = @import("std");
const board = @import("board.zig");
const Pos = board.Pos;
const Cell = board.Cell;

pub const Kind = enum {
    i,
    o,
    t,
    s,
    z,
    j,
    l,

    /// The cell a locked piece of this kind leaves on the board.
    pub fn cell(kind: Kind) Cell {
        return switch (kind) {
            inline else => |k| @field(Cell, @tagName(k)),
        };
    }

    /// Width and height of the square box the piece rotates in.
    pub fn boxSize(kind: Kind) i32 {
        return switch (kind) {
            .i => 4,
            .o => 2,
            .t, .s, .z, .j, .l => 3,
        };
    }
};

/// The four rotation states, in clockwise order. SRS calls them 0, R, 2, L.
pub const Rotation = enum(u2) {
    spawn,
    right,
    flip,
    left,

    pub fn cw(r: Rotation) Rotation {
        return @fromBackingInt(@backingInt(r) +% 1);
    }

    pub fn ccw(r: Rotation) Rotation {
        return @fromBackingInt(@backingInt(r) -% 1);
    }
};

/// The four cells of a piece, relative to the bottom-left corner of its box.
pub const Shape = [4]Pos;

/// Each piece in its spawn state, drawn inside its box, top row first.
const spawn_pictures: std.enums.EnumArray(Kind, []const u8) = .init(.{
    .i = "....\nXXXX\n....\n....",
    .o = "XX\nXX",
    .t = ".X.\nXXX\n...",
    .s = ".XX\nXX.\n...",
    .z = "XX.\n.XX\n...",
    .j = "X..\nXXX\n...",
    .l = "..X\nXXX\n...",
});

fn parseShape(kind: Kind) Shape {
    const size = kind.boxSize();
    var shape: Shape = undefined;
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, spawn_pictures.get(kind), '\n');
    var row: i32 = size - 1;
    while (lines.next()) |line| : (row -= 1) {
        for (line, 0..) |c, col| {
            if (c == 'X') {
                shape[n] = .{ .col = @intCast(col), .row = row };
                n += 1;
            }
        }
    }
    if (n != 4) @compileError("a tetromino has exactly four cells");
    return shape;
}

/// Turns a shape a quarter turn clockwise inside its box.
fn rotateCw(shape: Shape, size: i32) Shape {
    var out: Shape = undefined;
    for (shape, &out) |p, *q| q.* = .{ .col = p.row, .row = size - 1 - p.col };
    return out;
}

/// Every shape of every piece, computed once, at compile time.
const shapes: std.enums.EnumArray(Kind, [4]Shape) = blk: {
    var table: std.enums.EnumArray(Kind, [4]Shape) = .initUndefined();
    for (std.meta.tags(Kind)) |kind| {
        var shape = parseShape(kind);
        for (0..4) |r| {
            table.getPtr(kind)[r] = shape;
            shape = rotateCw(shape, kind.boxSize());
        }
    }
    break :blk table;
};

pub fn shapeOf(kind: Kind, rot: Rotation) Shape {
    return shapes.get(kind)[@backingInt(rot)];
}

/// A piece in play: what it is, how it is turned, and where its box is.
pub const Piece = struct {
    kind: Kind,
    rot: Rotation = .spawn,
    /// Board position of the bottom-left corner of the piece's box.
    pos: Pos,

    /// A new piece at the top of the board: centered (rounding left), with
    /// its top row in the first hidden row, just above the visible field.
    pub fn spawn(kind: Kind) Piece {
        const size = kind.boxSize();
        return .{
            .kind = kind,
            .pos = .{
                .col = if (kind == .o) 4 else 3,
                .row = board.visible_rows + 1 - size,
            },
        };
    }

    /// The four board positions the piece covers.
    pub fn cells(p: Piece) [4]Pos {
        var out: [4]Pos = undefined;
        for (shapeOf(p.kind, p.rot), &out) |offset, *cell| cell.* = p.pos.add(offset);
        return out;
    }
};

fn expectCells(p: Piece, expected: []const u8) !void {
    var b: board.Board = .empty;
    for (p.cells()) |pos| b.set(pos, p.kind.cell());
    try std.testing.expectFmt(expected, "{f}", .{b});
}

test "T rotates clockwise through all four states" {
    var t: Piece = .{ .kind = .t, .pos = .{ .col = 0, .row = 0 } };
    try expectCells(t,
        \\.T........
        \\TTT.......
        \\..........
    );
    t.rot = t.rot.cw();
    try expectCells(t,
        \\.T........
        \\.TT.......
        \\.T........
    );
    t.rot = t.rot.cw();
    try expectCells(t,
        \\TTT.......
        \\.T........
    );
    t.rot = t.rot.cw();
    try expectCells(t,
        \\.T........
        \\TT........
        \\.T........
    );
    try std.testing.expectEqual(Rotation.spawn, t.rot.cw());
    try std.testing.expectEqual(Rotation.left, Rotation.spawn.ccw());
}

test "I rotates inside its 4x4 box" {
    var i: Piece = .{ .kind = .i, .pos = .{ .col = 0, .row = 0 } };
    try expectCells(i,
        \\IIII......
        \\..........
        \\..........
    );
    i.rot = .right;
    try expectCells(i,
        \\..I.......
        \\..I.......
        \\..I.......
        \\..I.......
    );
}

test "pieces spawn in the middle, touching the top of the visible field" {
    for (std.meta.tags(Kind)) |kind| {
        const cells = Piece.spawn(kind).cells();
        var lowest: i32 = board.rows;
        var left: i32 = board.cols;
        var right: i32 = 0;
        for (cells) |c| {
            lowest = @min(lowest, c.row);
            left = @min(left, c.col);
            right = @max(right, c.col);
        }
        try std.testing.expectEqual(board.visible_rows - 1, lowest);
        try std.testing.expect(left == 3 or left == 4);
        try std.testing.expect(right == 5 or right == 6);
    }
}

test "every kind maps to its own cell" {
    try std.testing.expectEqual(Cell.i, Kind.i.cell());
    try std.testing.expectEqual(Cell.l, Kind.l.cell());
}
