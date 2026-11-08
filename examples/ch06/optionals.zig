//! An optional `?T` is either a T or null. Hold is one: the slot is empty
//! until the player first holds a piece.
const std = @import("std");

const Kind = enum { i, o, t, s, z, j, l };

const Hold = struct {
    held: ?Kind = null,

    /// Puts `current` aside and returns the piece to play instead: the
    /// held one if there is one, otherwise null (take the next piece).
    fn swap(h: *Hold, current: Kind) ?Kind {
        const out = h.held;
        h.held = current;
        return out;
    }
};

pub fn main() void {
    var hold: Hold = .{};

    // `if (x) |v|` runs only when x is not null, with v unwrapped.
    if (hold.held) |k| std.debug.print("holding {t}\n", .{k}) else std.debug.print("hold is empty\n", .{});

    // `orelse` gives a value for the null case.
    const first = hold.swap(.t) orelse .i;
    std.debug.print("held t, now playing {t}\n", .{first});

    const second = hold.swap(.s) orelse .i;
    std.debug.print("held s, now playing {t}\n", .{second});

    // `.?` unwraps when you know it is not null; null would panic.
    std.debug.print("held is {t}; == .s? {}\n", .{ hold.held.?, hold.held == .s });

    // Comparing with null, and the size an optional costs.
    hold.held = null;
    std.debug.print("held == null: {}; @sizeOf(Kind) = {d}, @sizeOf(?Kind) = {d}\n", .{
        hold.held == null, @sizeOf(Kind), @sizeOf(?Kind),
    });
}
