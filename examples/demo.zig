//! A helper for the raylib examples, so that they can run headless:
//!
//!   while (d.running()) { ... }
//!
//! With `--frames N` the loop stops after N frames, and with `--screenshot
//! PATH` the last frame is saved as a PNG. Without options it runs until
//! the window is closed. The project builds the same idea into its own
//! options (Chapter 1).
const std = @import("std");
const rl = @import("rl");

pub const Demo = struct {
    frames: ?u32 = null,
    screenshot: ?[:0]const u8 = null,
    frame: u32 = 0,

    pub fn init(args: []const [:0]const u8) Demo {
        var d: Demo = .{};
        var i: usize = 1;
        while (i + 1 < args.len) : (i += 2) {
            if (std.mem.eql(u8, args[i], "--frames")) {
                d.frames = std.fmt.parseInt(u32, args[i + 1], 10) catch null;
            } else if (std.mem.eql(u8, args[i], "--screenshot")) {
                d.screenshot = args[i + 1];
            }
        }
        return d;
    }

    /// Call once per frame, before drawing. False when it is time to stop.
    pub fn running(d: *Demo) bool {
        if (d.frames) |n| if (d.frame == n) {
            if (d.screenshot) |path| rl.TakeScreenshot(path);
            return false;
        };
        d.frame += 1;
        return !rl.WindowShouldClose();
    }

    /// The frame time: a fixed 1/60 s in a headless run, so that it gives
    /// the same picture every time.
    pub fn frameTime(d: *const Demo) f32 {
        return if (d.frames != null) 1.0 / 60.0 else rl.GetFrameTime();
    }
};
