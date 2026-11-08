//! One game: the board, the falling piece, and the rules that move it.
//! The game advances in fixed steps called ticks, 60 per second.
const std = @import("std");
const board_ = @import("board.zig");
const Board = board_.Board;
const piece = @import("piece.zig");
const Piece = piece.Piece;
const Kind = piece.Kind;
const input_ = @import("input.zig");
const Input = input_.Input;
const AutoRepeat = input_.AutoRepeat;

pub const ticks_per_second = 60;

/// Falling speed is counted in 1/65536ths of a row per tick (fixed point),
/// so the game uses integers only and every run gives the same result.
pub const one_row = 1 << 16;
/// One row per second. Rounded up: 65536 / 60 rounded down would need 61
/// ticks to fall the first row.
pub const gravity = std.math.divCeil(u32, one_row, ticks_per_second) catch unreachable;
/// Holding Down makes the piece fall this many times faster.
pub const soft_drop_factor = 20;
/// Ticks a piece may rest on the stack before it locks.
pub const lock_delay = 30;
/// Moves and turns that restart the lock delay, per row reached.
pub const max_lock_resets = 15;
/// Ticks the full rows flash before they disappear.
pub const clear_delay = 20;

pub const Phase = union(enum) {
    /// A piece is falling and the player controls it.
    falling,
    /// Full rows are about to be removed.
    clearing: struct { rows: board_.RowSet, timer: u32 },
    /// The stack reached the top.
    over,
};

pub const Game = struct {
    board: Board,
    piece: Piece,
    phase: Phase = .falling,
    next_kind: Kind,
    lines: u32 = 0,

    /// Last tick's input, to tell a new press from a held button.
    before: Input = .none,
    shift: AutoRepeat = .{},
    /// Fraction of a row fallen so far, in 1/65536ths.
    fall: u32 = 0,
    /// Ticks spent resting on the stack.
    lock_timer: u32 = 0,
    lock_resets: u32 = 0,
    /// The lowest row the piece's box has reached.
    lowest: i32,

    pub fn init(board: Board, first: Kind) Game {
        const p: Piece = .spawn(first);
        return .{ .board = board, .piece = p, .next_kind = nextInCycle(first), .lowest = p.pos.row };
    }

    /// Advances the game by one tick.
    pub fn tick(g: *Game, input: Input) void {
        defer g.before = input;
        switch (g.phase) {
            .over => return,
            .clearing => |*c| {
                c.timer -= 1;
                if (c.timer == 0) {
                    g.board.removeRows(c.rows);
                    g.phase = .falling;
                    g.spawn();
                }
                return;
            },
            .falling => {},
        }

        if (input.cw and !g.before.cw and g.turn(.cw)) g.restartLockDelay();
        if (input.ccw and !g.before.ccw and g.turn(.ccw)) g.restartLockDelay();
        const dx = g.shift.update(input, g.before);
        if (dx != 0 and g.move(dx, 0)) g.restartLockDelay();

        if (input.drop and !g.before.drop) {
            while (g.move(0, -1)) {}
            g.lock();
            return;
        }

        g.fall += if (input.down) gravity * soft_drop_factor else gravity;
        while (g.fall >= one_row) {
            g.fall -= one_row;
            if (!g.move(0, -1)) {
                g.fall = 0;
                break;
            }
            g.lock_timer = 0;
            if (g.piece.pos.row < g.lowest) {
                g.lowest = g.piece.pos.row;
                g.lock_resets = 0;
            }
        }

        if (!g.fits(g.piece.moved(0, -1))) {
            g.lock_timer += 1;
            if (g.lock_timer >= lock_delay) g.lock();
        }
    }

    /// The piece as far down as it can fall from where it is.
    pub fn dropped(g: *const Game) Piece {
        var p = g.piece;
        while (g.fits(p.moved(0, -1))) p = p.moved(0, -1);
        return p;
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

    /// A move or turn gives a resting piece more time, a limited number of
    /// times, so that it cannot stay up forever.
    fn restartLockDelay(g: *Game) void {
        if (g.lock_resets < max_lock_resets) {
            g.lock_timer = 0;
            g.lock_resets += 1;
        }
    }

    /// Writes the piece into the board, then clears rows or spawns the next.
    fn lock(g: *Game) void {
        var above_field = true;
        for (g.piece.cells()) |pos| {
            g.board.set(pos, g.piece.kind.cell());
            if (pos.row < board_.visible_rows) above_field = false;
        }
        if (above_field) {
            g.phase = .over;
            return;
        }
        const full = g.board.fullRows();
        if (full.count() > 0) {
            g.lines += @intCast(full.count());
            g.phase = .{ .clearing = .{ .rows = full, .timer = clear_delay } };
        } else {
            g.spawn();
        }
    }

    fn spawn(g: *Game) void {
        g.piece = .spawn(g.next_kind);
        g.next_kind = nextInCycle(g.next_kind);
        g.fall = 0;
        g.lock_timer = 0;
        g.lock_resets = 0;
        g.lowest = g.piece.pos.row;
        if (!g.fits(g.piece)) g.phase = .over;
    }
};

/// I, O, T, S, Z, J, L, then I again. Chapter 6 replaces this with a bag.
fn nextInCycle(kind: Kind) Kind {
    return @fromBackingInt((@backingInt(kind) + 1) % 7);
}

const testing = std.testing;

/// Runs `n` ticks of the same input.
fn run(g: *Game, input: Input, n: usize) void {
    for (0..n) |_| g.tick(input);
}

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

test "gravity pulls the piece down one row per second" {
    var g: Game = .init(.empty, .t);
    const start = g.piece.pos.row;
    run(&g, .none, ticks_per_second - 1);
    try testing.expectEqual(start, g.piece.pos.row);
    g.tick(.none);
    try testing.expectEqual(start - 1, g.piece.pos.row);
    // Soft drop is 20 times faster: 20 rows per second, one every 3 ticks.
    run(&g, .{ .down = true }, 3);
    try testing.expectEqual(start - 2, g.piece.pos.row);
}

test "hard drop locks at once and the next piece spawns" {
    var g: Game = .init(.empty, .i);
    g.tick(.{ .drop = true });
    try testing.expectFmt("...IIII...", "{f}", .{g.board});
    try testing.expectEqual(Kind.o, g.piece.kind);
}

test "a resting piece locks after the lock delay" {
    var g: Game = .init(.empty, .o);
    run(&g, .{ .down = true }, 60); // reach the floor
    try testing.expectEqual(0, g.piece.pos.row);
    try testing.expectFmt("", "{f}", .{g.board});
    run(&g, .none, lock_delay);
    try testing.expectFmt(
        \\....OO....
        \\....OO....
    , "{f}", .{g.board});
}

test "moving restarts the lock delay, but only so many times" {
    var g: Game = .init(.empty, .o);
    run(&g, .{ .down = true }, 60);
    // Tap left and right forever: each tap restarts the delay until the
    // resets run out, then the piece locks.
    var ticks: u32 = 0;
    while (g.board.get(.{ .col = 4, .row = 0 }) == .empty and g.piece.kind == .o) : (ticks += 2) {
        g.tick(if (ticks % 4 == 0) .{ .left = true } else .{ .right = true });
        g.tick(.none);
        if (ticks > 1000) return error.NeverLocked;
    }
    try testing.expect(ticks > lock_delay);
    try testing.expectEqual(Kind.t, g.piece.kind);
}

test "a full row flashes, then disappears" {
    var g: Game = .init(.parse(
        \\###....###
    ), .i);
    g.tick(.{ .drop = true });
    try testing.expect(g.phase == .clearing);
    try testing.expectEqual(1, g.lines);
    run(&g, .none, clear_delay);
    try testing.expect(g.phase == .falling);
    try testing.expectFmt("", "{f}", .{g.board});
}

test "the game is over when a new piece has no room" {
    var g: Game = .init(.empty, .o);
    for (0..20) |_| {
        g.tick(.{ .drop = true });
        g.tick(.none);
    }
    try testing.expect(g.phase == .over);
}
