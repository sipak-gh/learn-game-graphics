//! Juice: small effects that make the game feel alive. They react to the
//! core's events and change only how things look, never the game itself.
const std = @import("std");
const rl = @import("rl");
const core = @import("core");

pub const Effects = struct {
    /// Ticks of screen shake left.
    shake: u32 = 0,
    /// Ticks the level-up banner stays on screen.
    banner: u32 = 0,

    pub fn react(e: *Effects, events: core.game.Events) void {
        if (events.hard_drop) e.shake = @max(e.shake, 8);
        if (events.cleared == 4) e.shake = 20;
        if (events.level_up) e.banner = 90;
    }

    /// Runs once per game tick, so effects last as long at any frame rate.
    pub fn tick(e: *Effects) void {
        e.shake -|= 1;
        e.banner -|= 1;
    }

    /// How far to move the whole picture this frame: a wobble that dies down.
    pub fn offset(e: *const Effects) rl.Vector2 {
        const t: f32 = @floatFromInt(e.shake);
        return .{ .x = @sin(t * 2.1) * t * 0.4, .y = @cos(t * 1.7) * t * 0.6 };
    }
};
