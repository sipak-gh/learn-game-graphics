//! One game: the board, the falling piece, and the rules that move it.
//! The game advances in fixed steps called ticks, 60 per second.
const std = @import("std");
const Board = @import("board.zig").Board;
const piece = @import("piece.zig");
const Piece = piece.Piece;
const input_ = @import("input.zig");
const Input = input_.Input;
const AutoRepeat = input_.AutoRepeat;

pub const ticks_per_second = 60;

pub const Game = struct {
    board: Board,
    piece: Piece,
    /// Last tick's input, to tell a new press from a held button.
    before: Input = .none,
    shift: AutoRepeat = .{},
    down: AutoRepeat = .{},

    pub fn init(board: Board, kind: piece.Kind) Game {
        return .{ .board = board, .piece = .spawn(kind) };
    }

    /// Advances the game by one tick.
    pub fn tick(g: *Game, input: Input) void {
        if (input.cw and !g.before.cw) _ = g.turn(.cw);
        if (input.ccw and !g.before.ccw) _ = g.turn(.ccw);

        const dx = g.shift.update(input, g.before);
        if (dx != 0) _ = g.move(dx, 0);

        // Down auto-repeats too; it reuses AutoRepeat with Down as "right".
        const dy = g.down.update(.{ .right = input.down }, .{ .right = g.before.down });
        if (dy != 0) _ = g.move(0, -1);

        g.before = input;
    }

    fn fits(g: *const Game, p: Piece) bool {
        return g.board.fits(&p.cells());
    }

    /// Moves the piece if the new place is free. Returns whether it moved.
    fn move(g: *Game, dcol: i32, drow: i32) bool {
        const moved = g.piece.moved(dcol, drow);
        if (!g.fits(moved)) return false;
        g.piece = moved;
        return true;
    }

    /// Turns the piece, trying each SRS kick in order. Returns whether it turned.
    fn turn(g: *Game, t: piece.Turn) bool {
        const turned = g.piece.turned(t);
        for (piece.kicks(g.piece.kind, g.piece.rot, t)) |kick| {
            const kicked = turned.moved(kick.col, kick.row);
            if (g.fits(kicked)) {
                g.piece = kicked;
                return true;
            }
        }
        return false;
    }
};

const testing = std.testing;

test "the piece stops at the walls" {
    var g: Game = .init(.empty, .o);
    for (0..10) |_| {
        g.tick(.{ .left = true });
        g.tick(.none);
    }
    try testing.expectEqual(0, g.piece.pos.col);
    for (0..10) |_| {
        g.tick(.{ .right = true });
        g.tick(.none);
    }
    try testing.expectEqual(8, g.piece.pos.col);
}

test "a turn against the wall kicks the piece away from it" {
    var g: Game = .init(.empty, .t);
    // T pointing left against the right wall: its box hangs outside.
    g.tick(.{ .ccw = true });
    g.tick(.none);
    for (0..5) |_| {
        g.tick(.{ .right = true });
        g.tick(.none);
    }
    try testing.expectEqual(piece.Rotation.left, g.piece.rot);
    try testing.expectEqual(8, g.piece.pos.col);
    // Turning to spawn would cover column 10, so the kick (-1, 0) moves it left.
    g.tick(.{ .cw = true });
    try testing.expectEqual(piece.Rotation.spawn, g.piece.rot);
    try testing.expectEqual(7, g.piece.pos.col);
}

test "a turn that no kick can fix does nothing" {
    // An I standing in a one-column well: all five tries hit a wall of '#'.
    var g: Game = .init(.parse(
        \\####.#####
        \\####.#####
        \\####.#####
        \\####.#####
    ), .i);
    g.piece = .{ .kind = .i, .rot = .right, .pos = .{ .col = 2, .row = 0 } };
    try testing.expect(g.fits(g.piece));
    g.tick(.{ .cw = true });
    try testing.expectEqual(piece.Rotation.right, g.piece.rot);
    try testing.expectEqual(2, g.piece.pos.col);
}
