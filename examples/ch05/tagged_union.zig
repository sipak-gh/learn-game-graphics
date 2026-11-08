//! A tagged union holds exactly one of its fields, and knows which one.
//! The game's phase is one: falling, clearing (with a timer), or over.
const std = @import("std");

const Phase = union(enum) {
    falling,
    clearing: struct { rows: u32, timer: u32 },
    over,
};

/// One tick of a tiny state machine: a clear lasts 3 ticks.
fn tick(phase: *Phase) void {
    switch (phase.*) {
        .falling => phase.* = .{ .clearing = .{ .rows = 2, .timer = 3 } },
        // |*c| captures a pointer to the payload, so it can be changed.
        .clearing => |*c| {
            c.timer -= 1;
            if (c.timer == 0) phase.* = .over;
        },
        .over => {},
    }
}

pub fn main() void {
    var phase: Phase = .falling;
    for (0..6) |i| {
        switch (phase) {
            .clearing => |c| std.debug.print("tick {d}: clearing {d} rows, timer {d}\n", .{ i, c.rows, c.timer }),
            else => std.debug.print("tick {d}: {t}\n", .{ i, phase }),
        }
        tick(&phase);
    }
    // Comparing with a tag ignores the payload.
    std.debug.print("phase == .over: {}\n", .{phase == .over});
    std.debug.print("@sizeOf(Phase) = {d}\n", .{@sizeOf(Phase)});
}
