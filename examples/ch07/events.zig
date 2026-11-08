//! Events as a packed struct: the producer sets flags during a tick, and
//! any number of consumers read them afterwards. No callbacks, no queue.
const std = @import("std");

const Events = packed struct {
    moved: bool = false,
    locked: bool = false,
    /// Rows cleared, 0 to 4. A u3 holds 0 to 7.
    cleared: u3 = 0,
    game_over: bool = false,
};

const Action = union(enum) { idle, move, lock: usize, top_out };

/// The producer: a pretend game that reports what each action did.
const Game = struct {
    events: Events = .{},
    lines: usize = 0,

    fn tick(g: *Game, action: Action) void {
        g.events = .{}; // forget the last tick
        switch (action) {
            .idle => {},
            .move => g.events.moved = true,
            .lock => |rows| {
                g.events.locked = true;
                g.events.cleared = @intCast(rows);
                g.lines += rows;
            },
            .top_out => g.events.game_over = true,
        }
    }
};

/// Consumer 1: picks one sound per tick, the most important first.
fn sound(e: Events) []const u8 {
    if (e.game_over) return "game-over";
    if (e.cleared == 4) return "four";
    if (e.cleared > 0) return "clear";
    if (e.locked) return "lock";
    if (e.moved) return "move";
    return "-";
}

pub fn main() void {
    std.debug.print("Events: {d} bits, {d} byte(s)\n", .{ @bitSizeOf(Events), @sizeOf(Events) });
    const actions = [_]Action{ .idle, .move, .{ .lock = 0 }, .{ .lock = 1 }, .{ .lock = 4 }, .top_out };
    var g: Game = .{};
    var shake: u32 = 0;
    for (actions) |action| {
        g.tick(action);
        // Consumer 2: screen shake on a four-line clear, dying down.
        shake -|= 1;
        if (g.events.cleared == 4) shake = 20;
        const quiet = g.events == Events{};
        std.debug.print("{t:<8} bits={b:0>6} quiet={} sound={s} shake={d}\n", .{
            action, @as(u6, @bitCast(g.events)), quiet, sound(g.events), shake,
        });
    }
    std.debug.print("lines: {d}\n", .{g.lines});
}
