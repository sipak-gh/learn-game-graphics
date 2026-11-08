//! Key presses and a fixed timestep. A frame can run zero, one, or several
//! ticks; a press must still act exactly once. Run with `zig test`.
const std = @import("std");

const Action = enum { toggle_map };

const Input = struct {
    forward: f32 = 0,
    pressed: std.EnumSet(Action) = .empty,

    fn accumulate(pending: *Input, fresh: Input) void {
        const presses = pending.pressed.unionWith(fresh.pressed);
        pending.* = fresh;
        pending.pressed = presses;
    }

    fn take(pending: *Input) Input {
        const input = pending.*;
        pending.pressed = .empty;
        return input;
    }
};

/// Ticks per frame for a run where the frame rate stutters: frame 0 runs
/// two ticks, frame 1 none, and so on.
const ticks_per_frame = [_]u32{ 2, 0, 1, 0, 2, 1 };
/// The frames on which the keyboard reports a fresh press of Tab.
const press_on_frame = [_]bool{ true, true, false, false, true, false };

/// Counts how many ticks see the press, feeding each tick the frame's
/// input directly.
fn naive() u32 {
    var acted: u32 = 0;
    for (ticks_per_frame, press_on_frame) |ticks, press| {
        var input: Input = .{};
        if (press) input.pressed.insert(.toggle_map);
        for (0..ticks) |_| acted += @intFromBool(input.pressed.contains(.toggle_map));
    }
    return acted;
}

/// The same run through accumulate and take.
fn queued() u32 {
    var acted: u32 = 0;
    var queue: Input = .{};
    for (ticks_per_frame, press_on_frame) |ticks, press| {
        var input: Input = .{};
        if (press) input.pressed.insert(.toggle_map);
        queue.accumulate(input);
        for (0..ticks) |_| acted += @intFromBool(queue.take().pressed.contains(.toggle_map));
    }
    return acted;
}

test "naive input doubles and drops presses" {
    const n = naive();
    std.debug.print("\n3 presses, naive: acted {d} times\n", .{n});
    // Frames 0 and 4 act twice (two ticks each); frame 1's press is lost
    // (no tick): 2 + 0 + 2.
    try std.testing.expectEqual(4, n);
}

test "accumulate and take act once per press" {
    const n = queued();
    std.debug.print("\n3 presses, accumulate/take: acted {d} times\n", .{n});
    // Frame 1's press waits in the queue until frame 2's tick takes it.
    try std.testing.expectEqual(3, n);
}

test "held state survives take" {
    var queue: Input = .{};
    queue.accumulate(.{ .forward = 1 });
    _ = queue.take();
    try std.testing.expectEqual(1, queue.take().forward);
}
