//! What the player is doing: the buttons held during one tick, and the
//! auto-repeat that turns a held direction into a stream of moves.
const std = @import("std");

/// The buttons held during one tick. The game never sees keys or a keyboard,
/// only this, so a script or a replay can play exactly like a person.
pub const Input = packed struct {
    left: bool = false,
    right: bool = false,
    down: bool = false,
    cw: bool = false,
    ccw: bool = false,
    drop: bool = false,
    hold: bool = false,

    pub const none: Input = .{};
};

/// Delayed auto shift (DAS) with an auto repeat rate (ARR): a held direction
/// moves once at once, then waits `delay` ticks, then moves every `rate` ticks.
pub const AutoRepeat = struct {
    pub const delay = 10;
    pub const rate = 2;

    /// The direction being repeated: -1 (left), 0 (none) or +1 (right).
    dir: i32 = 0,
    /// Ticks since that direction was pressed.
    held: u32 = 0,

    /// Returns how many columns to shift this tick: -1, 0 or +1.
    pub fn update(r: *AutoRepeat, now: Input, before: Input) i32 {
        // A new press wins, even if the other direction is still held.
        if (now.left and !before.left) return r.start(-1);
        if (now.right and !before.right) return r.start(1);

        const still_held = (r.dir < 0 and now.left) or (r.dir > 0 and now.right);
        if (!still_held) {
            // Released: fall back to the other direction if it is held.
            if (now.left) return r.start(-1);
            if (now.right) return r.start(1);
            r.dir = 0;
            return 0;
        }
        r.held += 1;
        if (r.held >= delay and (r.held - delay) % rate == 0) return r.dir;
        return 0;
    }

    fn start(r: *AutoRepeat, dir: i32) i32 {
        r.* = .{ .dir = dir };
        return dir;
    }
};

/// Feeds `ticks` ticks of `input` and returns the total shift.
fn shiftFor(r: *AutoRepeat, input: Input, ticks: u32) i32 {
    var total: i32 = 0;
    var before: Input = .none;
    for (0..ticks) |_| {
        total += r.update(input, before);
        before = input;
    }
    return total;
}

test "a tap moves one column" {
    var r: AutoRepeat = .{};
    try std.testing.expectEqual(-1, r.update(.{ .left = true }, .none));
    try std.testing.expectEqual(0, r.update(.none, .{ .left = true }));
}

test "holding waits for the delay, then repeats at the rate" {
    var r: AutoRepeat = .{};
    // 1 at once, nothing during the delay, then one every `rate` ticks.
    try std.testing.expectEqual(1, shiftFor(&r, .{ .right = true }, AutoRepeat.delay));
    r = .{};
    try std.testing.expectEqual(2, shiftFor(&r, .{ .right = true }, AutoRepeat.delay + 1));
    r = .{};
    try std.testing.expectEqual(4, shiftFor(&r, .{ .right = true }, AutoRepeat.delay + 2 * AutoRepeat.rate + 1));
}

test "the newest direction wins, and releasing it returns to the other" {
    var r: AutoRepeat = .{};
    const left: Input = .{ .left = true };
    const both: Input = .{ .left = true, .right = true };
    try std.testing.expectEqual(-1, r.update(left, .none));
    try std.testing.expectEqual(1, r.update(both, left));
    try std.testing.expectEqual(-1, r.update(left, both));
}
