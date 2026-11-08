//! What the player wants to do during one tick. The platform layer fills
//! it in from the keyboard; the game only ever sees this struct.
const std = @import("std");

/// Things that happen once per key press, not for as long as a key is held.
pub const Action = enum {
    next_view,
    toggle_fisheye,
    toggle_textures,
    toggle_minimap,
    toggle_overlay,
    toggle_clipping,
    toggle_culling,
    toggle_depth_test,
    next_shading,
    toggle_torch,
    toggle_fog,
    next_filter,
    toggle_perspective,
    toggle_info,
};

pub const Input = struct {
    /// -1 (backward) to 1 (forward).
    forward: f32 = 0,
    /// -1 (left) to 1 (right).
    strafe: f32 = 0,
    /// -1 (turn left) to 1 (turn right).
    turn: f32 = 0,
    /// -1 (look down) to 1 (look up).
    tilt: f32 = 0,
    /// How far the mouse moved sideways, in pixels (right is positive).
    look: f32 = 0,
    /// How far the mouse moved up or down, in pixels (down is positive,
    /// as on the screen).
    look_y: f32 = 0,
    /// Actions whose key went down since the last tick.
    pressed: std.EnumSet(Action) = .empty,

    /// Merges this frame's input into `pending`. Held keys are replaced by
    /// their current state; presses and mouse movement pile up until a
    /// tick takes them, so none is lost when a frame runs no tick.
    pub fn accumulate(pending: *Input, fresh: Input) void {
        const presses = pending.pressed.unionWith(fresh.pressed);
        const look = pending.look + fresh.look;
        const look_y = pending.look_y + fresh.look_y;
        pending.* = fresh;
        pending.pressed = presses;
        pending.look = look;
        pending.look_y = look_y;
    }

    /// The input for one tick. Presses and mouse movement are cleared, so
    /// each acts once even when a frame runs several ticks.
    pub fn take(pending: *Input) Input {
        const input = pending.*;
        pending.pressed = .empty;
        pending.look = 0;
        pending.look_y = 0;
        return input;
    }
};

/// Both inputs at once, as if two sets of keys were held.
pub fn combine(a: Input, b: Input) Input {
    return .{
        .forward = @max(-1, @min(1, a.forward + b.forward)),
        .strafe = @max(-1, @min(1, a.strafe + b.strafe)),
        .turn = @max(-1, @min(1, a.turn + b.turn)),
        .tilt = @max(-1, @min(1, a.tilt + b.tilt)),
        .look = a.look + b.look,
        .look_y = a.look_y + b.look_y,
        .pressed = a.pressed.unionWith(b.pressed),
    };
}

test "a press acts on exactly one tick" {
    var pending: Input = .{};
    var fresh: Input = .{ .forward = 1 };
    fresh.pressed.insert(.next_view);
    pending.accumulate(fresh);
    // The next frame's keyboard no longer reports the press...
    pending.accumulate(.{ .forward = 1 });
    // ...but the first tick still gets it, and the second does not.
    try std.testing.expect(pending.take().pressed.contains(.next_view));
    const second = pending.take();
    try std.testing.expect(!second.pressed.contains(.next_view));
    try std.testing.expectEqual(1, second.forward);
}

test "mouse movement adds up until a tick takes it" {
    var pending: Input = .{};
    pending.accumulate(.{ .look = 3, .look_y = 1 });
    pending.accumulate(.{ .look = -1, .look_y = 4 });
    const first = pending.take();
    try std.testing.expectEqual(2, first.look);
    try std.testing.expectEqual(5, first.look_y);
    const second = pending.take();
    try std.testing.expectEqual(0, second.look);
    try std.testing.expectEqual(0, second.look_y);
}
