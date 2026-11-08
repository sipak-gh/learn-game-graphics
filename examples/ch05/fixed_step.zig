//! The fixed-timestep accumulator: whatever the frame times are, the game
//! advances in ticks of exactly 1/60 s, so one second is always 60 ticks.
const std = @import("std");

const tick_seconds = 1.0 / 60.0;

/// Runs frames until `seconds` of real time have passed. Returns the number
/// of ticks simulated and the time left over in `lag`.
fn simulate(frame_times: []const f64, seconds: f64) struct { ticks: u32, frames: u32, lag: f64 } {
    var lag: f64 = 0;
    var ticks: u32 = 0;
    var frames: u32 = 0;
    var clock: f64 = 0;
    while (clock < seconds - 1e-9) : (frames += 1) {
        const frame_seconds = frame_times[frames % frame_times.len];
        clock += frame_seconds;
        lag += frame_seconds;
        while (lag >= tick_seconds) : (lag -= tick_seconds) ticks += 1;
    }
    return .{ .ticks = ticks, .frames = frames, .lag = lag };
}

pub fn main() void {
    const machines = [_]struct { name: []const u8, times: []const f64 }{
        .{ .name = "30 Hz", .times = &.{1.0 / 30.0} },
        .{ .name = "60 Hz", .times = &.{1.0 / 60.0} },
        .{ .name = "144 Hz", .times = &.{1.0 / 144.0} },
        // An uneven machine: frames of 5, 30, 12 and 3 ms (50 ms in total).
        .{ .name = "jittery", .times = &.{ 0.005, 0.030, 0.012, 0.003 } },
    };
    for (machines) |m| {
        const r = simulate(m.times, 1.0);
        std.debug.print("{s:>7}: {d:>3} frames, {d} ticks, lag {d:.6} s", .{ m.name, r.frames, r.ticks, r.lag });
        if (r.lag > 0) std.debug.print(" ({e} s short of a tick)", .{tick_seconds - r.lag});
        std.debug.print("\n", .{});
    }
}
