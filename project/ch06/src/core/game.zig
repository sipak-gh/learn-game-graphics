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
const Bag = @import("bag.zig").Bag;

pub const ticks_per_second = 60;

/// Falling speed is counted in 1/65536ths of a row per tick (fixed point),
/// so the game uses integers only and every run gives the same result.
pub const one_row = 1 << 16;
/// Gravity for levels 1 to 20, computed at compile time from the guideline
/// curve: (0.8 - (level - 1) * 0.007) ^ (level - 1) seconds per row.
/// Rounded up, so level 1 falls its first row in exactly 60 ticks.
pub const gravity_table: [20]u32 = blk: {
    @setEvalBranchQuota(10_000);
    var table: [20]u32 = undefined;
    for (&table, 1..) |*g, level| {
        const n: f64 = @floatFromInt(level - 1);
        const seconds_per_row = std.math.pow(f64, 0.8 - n * 0.007, n);
        const rows_per_tick = 1.0 / (seconds_per_row * ticks_per_second);
        // Never more than 20 rows per tick ("20G"): the height of the field.
        g.* = @intFromFloat(@ceil(@min(rows_per_tick, 20.0) * one_row));
    }
    break :blk table;
};

pub fn gravityAt(level: u32) u32 {
    return gravity_table[@min(level, gravity_table.len) - 1];
}
/// Holding Down makes the piece fall this many times faster.
pub const soft_drop_factor = 20;
/// Ticks a piece may rest on the stack before it locks.
pub const lock_delay = 30;
/// Moves and turns that restart the lock delay, per row reached.
pub const max_lock_resets = 15;
/// Ticks the full rows flash before they disappear.
pub const clear_delay = 20;
/// How many upcoming pieces the player can see.
pub const preview = 5;
pub const lines_per_level = 10;
/// Points for clearing 1, 2, 3 or 4 rows at once, times the level.
const line_points = [_]u32{ 0, 100, 300, 500, 800 };

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
    bag: Bag,
    /// The next pieces, soonest first.
    queue: [preview]Kind,
    /// The piece put aside with Hold, if any.
    held: ?Kind = null,
    /// Hold works once per piece: false until the current piece locks.
    can_hold: bool = true,
    score: u32 = 0,
    lines: u32 = 0,
    level: u32 = 1,

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

    pub fn init(board: Board, seed: u64) Game {
        var bag: Bag = .init(seed);
        const p: Piece = .spawn(bag.next());
        var queue: [preview]Kind = undefined;
        for (&queue) |*k| k.* = bag.next();
        return .{ .board = board, .piece = p, .bag = bag, .queue = queue, .lowest = p.pos.row };
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
                    g.spawn(g.takeNext());
                }
                return;
            },
            .falling => {},
        }

        if (input.cw and !g.before.cw and g.turn(.cw)) g.restartLockDelay();
        if (input.ccw and !g.before.ccw and g.turn(.ccw)) g.restartLockDelay();
        const dx = g.shift.update(input, g.before);
        if (dx != 0 and g.move(dx, 0)) g.restartLockDelay();

        if (input.hold and !g.before.hold and g.can_hold) {
            g.can_hold = false;
            const kind = g.piece.kind;
            if (g.held) |h| g.spawn(h) else g.spawn(g.takeNext());
            g.held = kind;
            return;
        }

        if (input.drop and !g.before.drop) {
            while (g.move(0, -1)) g.score += 2;
            g.lock();
            return;
        }

        const speed = gravityAt(g.level);
        g.fall += if (input.down) speed * soft_drop_factor else speed;
        while (g.fall >= one_row) {
            g.fall -= one_row;
            if (!g.move(0, -1)) {
                g.fall = 0;
                break;
            }
            if (input.down) g.score += 1;
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
        g.can_hold = true;
        const full = g.board.fullRows();
        const cleared: u32 = @intCast(full.count());
        if (cleared > 0) {
            g.score += line_points[cleared] * g.level;
            g.lines += cleared;
            g.level = 1 + g.lines / lines_per_level;
            g.phase = .{ .clearing = .{ .rows = full, .timer = clear_delay } };
        } else {
            g.spawn(g.takeNext());
        }
    }

    /// Takes the first piece from the queue and refills it from the bag.
    fn takeNext(g: *Game) Kind {
        const kind = g.queue[0];
        std.mem.copyForwards(Kind, g.queue[0 .. preview - 1], g.queue[1..]);
        g.queue[preview - 1] = g.bag.next();
        return kind;
    }

    fn spawn(g: *Game, kind: Kind) void {
        g.piece = .spawn(kind);
        g.fall = 0;
        g.lock_timer = 0;
        g.lock_resets = 0;
        g.lowest = g.piece.pos.row;
        if (!g.fits(g.piece)) g.phase = .over;
    }
};

const testing = std.testing;

/// A game on `board` whose current piece is `first`.
fn startWith(board: Board, first: Kind) Game {
    var g: Game = .init(board, 0);
    g.spawn(first);
    return g;
}

/// Runs `n` ticks of the same input.
fn run(g: *Game, input: Input, n: usize) void {
    for (0..n) |_| g.tick(input);
}

test "the piece stops at the walls" {
    var g = startWith(.empty, .o);
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
    var g = startWith(.empty, .t);
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
    var g = startWith(.parse(
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
    var g = startWith(.empty, .t);
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
    var g = startWith(.empty, .i);
    const next = g.queue[0];
    g.tick(.{ .drop = true });
    try testing.expectFmt("...IIII...", "{f}", .{g.board});
    try testing.expectEqual(next, g.piece.kind);
    // Two points per row dropped: from row 19 to row 0.
    try testing.expectEqual(2 * 19, g.score);
}

test "a resting piece locks after the lock delay" {
    var g = startWith(.empty, .o);
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
    var g = startWith(.empty, .o);
    run(&g, .{ .down = true }, 60);
    // Tap left and right forever: each tap restarts the delay until the
    // resets run out, then the piece locks.
    var ticks: u32 = 0;
    while (g.board.get(.{ .col = 4, .row = 0 }) == .empty) : (ticks += 2) {
        g.tick(if (ticks % 4 == 0) .{ .left = true } else .{ .right = true });
        g.tick(.none);
        if (ticks > 1000) return error.NeverLocked;
    }
    try testing.expect(ticks > lock_delay);
}

test "the gravity curve speeds up with the level" {
    try testing.expectEqual(1093, gravityAt(1)); // 1 row per second
    for (1..18) |level| {
        try testing.expect(gravityAt(@intCast(level + 1)) > gravityAt(@intCast(level)));
    }
    // From level 19 the curve passes 20 rows per tick and is capped.
    try testing.expectEqual(20 * one_row, gravityAt(19));
    try testing.expectEqual(20 * one_row, gravityAt(20));
    try testing.expectEqual(gravityAt(20), gravityAt(99));
}

test "hold puts the piece aside once per piece" {
    var g = startWith(.empty, .t);
    const next = g.queue[0];
    g.tick(.{ .hold = true });
    try testing.expectEqual(Kind.t, g.held.?);
    try testing.expectEqual(next, g.piece.kind);
    // A second hold before the piece locks does nothing.
    g.tick(.none);
    g.tick(.{ .hold = true });
    try testing.expectEqual(next, g.piece.kind);
    // After a lock, hold swaps the new piece with the T.
    g.tick(.{ .drop = true });
    g.tick(.{ .hold = true });
    try testing.expectEqual(Kind.t, g.piece.kind);
}

test "clearing rows scores points and raises the level" {
    var g = startWith(.parse(
        \\####.#####
        \\####.#####
        \\####.#####
        \\####.#####
    ), .i);
    g.lines = 9;
    g.piece = .{ .kind = .i, .rot = .right, .pos = .{ .col = 2, .row = 10 } };
    g.tick(.{ .drop = true });
    try testing.expectEqual(4, g.phase.clearing.rows.count());
    // 800 for four rows at level 1, plus 2 for each of the 10 rows dropped.
    try testing.expectEqual(800 + 20, g.score);
    try testing.expectEqual(13, g.lines);
    try testing.expectEqual(2, g.level);
}

test "a full row flashes, then disappears" {
    var g = startWith(.parse(
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
    var g = startWith(.empty, .o);
    for (0..20) |_| {
        g.tick(.{ .drop = true });
        g.tick(.none);
    }
    try testing.expect(g.phase == .over);
}
