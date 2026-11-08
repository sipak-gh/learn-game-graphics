//! Telling a press from a hold: compare this tick's buttons with last tick's.
const std = @import("std");

const Input = packed struct {
    left: bool = false,
    cw: bool = false,

    pub const none: Input = .{};
};

pub fn main() void {
    // Who is holding what, tick by tick: L = left, C = cw, . = nothing.
    const ticks = "..LLLL.CCC.L.L..";
    var inputs: [ticks.len]Input = undefined;
    for (ticks, &inputs) |c, *in| in.* = .{ .left = c == 'L', .cw = c == 'C' };

    var held: [ticks.len]u8 = undefined;
    var pressed: [ticks.len]u8 = undefined;
    var released: [ticks.len]u8 = undefined;
    var before: Input = .none;
    for (inputs, 0..) |now, t| {
        held[t] = if (now.left) 'L' else if (now.cw) 'C' else '.';
        // An edge: the button is down now but was up last tick, or the reverse.
        pressed[t] = if (now.left and !before.left) 'L' else if (now.cw and !before.cw) 'C' else '.';
        released[t] = if (!now.left and before.left) 'L' else if (!now.cw and before.cw) 'C' else '.';
        before = now;
    }
    std.debug.print("tick      0123456789012345\n", .{});
    std.debug.print("held      {s}\n", .{&held});
    std.debug.print("pressed   {s}\n", .{&pressed});
    std.debug.print("released  {s}\n", .{&released});
}
