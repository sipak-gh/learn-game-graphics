//! A 2-second stall, then normal frames. Each tick costs real time, so a
//! frame that runs many ticks takes long, and the next frame has to catch
//! up even more. The 0.25 s cap stops that "spiral of death".
const std = @import("std");

const tick_seconds = 1.0 / 60.0;
const draw_seconds = 0.004;

fn run(tick_cost: f64, cap: f64) void {
    var lag: f64 = 0;
    var frame_seconds: f64 = 2.0; // the stall: a dragged window, a debugger
    for (0..8) |_| {
        lag += @min(frame_seconds, cap);
        var ticks: u32 = 0;
        while (lag >= tick_seconds) : (lag -= tick_seconds) ticks += 1;
        std.debug.print(" {d:>3}", .{ticks});
        // Running the ticks and drawing is what the next frame has to cover.
        frame_seconds = draw_seconds + @as(f64, @floatFromInt(ticks)) * tick_cost;
    }
    std.debug.print("\n", .{});
}

pub fn main() void {
    const inf = std.math.inf(f64);
    for ([_]f64{ 0.012, 0.020 }) |cost| {
        std.debug.print("a tick costs {d} ms; ticks in each frame after the stall:\n", .{cost * 1000});
        std.debug.print("  no cap:   ", .{});
        run(cost, inf);
        std.debug.print("  0.25 cap: ", .{});
        run(cost, 0.25);
    }
}
