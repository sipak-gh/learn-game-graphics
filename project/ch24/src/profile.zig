//! Where a frame's time goes. A stopwatch charges the time since its
//! last lap to one stage of the frame; `--bench` collects every frame's
//! times and prints what they add up to.
const std = @import("std");

/// The stages of `App.render`, in order.
pub const Stage = enum {
    /// Working out which chunks to draw.
    visibility,
    /// Clearing the screen and drawing the world: the 3D pipeline.
    world,
    /// The crosshair, minimap, and numbers on top.
    overlays,
};

/// Nanoseconds spent in each stage.
pub const Times = std.EnumArray(Stage, u64);

pub fn total(times: Times) u64 {
    var sum: u64 = 0;
    for (times.values) |ns| sum += ns;
    return sum;
}

pub const Stopwatch = struct {
    io: std.Io,
    last: std.Io.Timestamp,
    times: Times = .initFill(0),

    pub fn start(io: std.Io) Stopwatch {
        return .{ .io = io, .last = .now(io, .awake) };
    }

    /// Adds the time since the last lap (or the start) to `stage`.
    pub fn lap(w: *Stopwatch, stage: Stage) void {
        const now: std.Io.Timestamp = .now(w.io, .awake);
        w.times.getPtr(stage).* += @intCast(w.last.durationTo(now).nanoseconds);
        w.last = now;
    }
};

/// The times of every frame of a run.
pub const Bench = struct {
    /// Each frame's total, in nanoseconds.
    frames: std.ArrayList(u64) = .empty,
    /// Each stage's total over all frames.
    stages: Times = .initFill(0),

    pub fn deinit(b: *Bench, gpa: std.mem.Allocator) void {
        b.frames.deinit(gpa);
    }

    pub fn add(b: *Bench, gpa: std.mem.Allocator, times: Times) !void {
        try b.frames.append(gpa, total(times));
        for (&b.stages.values, times.values) |*sum, ns| sum.* += ns;
    }

    /// Prints the mean frame time, then the median, the 95th percentile,
    /// and the worst: a mean hides the slow frames that make a game feel
    /// jerky. Sorts the frames.
    pub fn report(b: *Bench, w: *std.Io.Writer) !void {
        const n = b.frames.items.len;
        if (n == 0) return;
        std.mem.sort(u64, b.frames.items, {}, std.sort.asc(u64));
        const sorted = b.frames.items;
        const mean = ms(total(b.stages)) / @as(f64, @floatFromInt(n));
        try w.print("{d} frames  mean {d:.2} ms ({d:.0} fps)  median {d:.2}  95% {d:.2}  worst {d:.2}\n", .{
            n,
            mean,
            1000 / mean,
            ms(sorted[(n - 1) / 2]),
            ms(sorted[(n - 1) * 95 / 100]),
            ms(sorted[n - 1]),
        });
        try w.writeAll("per frame:");
        for (std.enums.values(Stage)) |stage| {
            try w.print("  {t} {d:.2} ms", .{ stage, ms(b.stages.get(stage)) / @as(f64, @floatFromInt(n)) });
        }
        try w.writeAll("\n");
    }
};

fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1e6;
}

test "the bench report gives the mean, median, 95th percentile and worst frame" {
    const gpa = std.testing.allocator;
    var b: Bench = .{};
    defer b.deinit(gpa);
    // Frames of 1 to 100 ms, out of order, all of it drawing the world
    // except 0.5 ms of overlays each.
    for (0..100) |i| {
        const frame_ms = (i * 37) % 100 + 1;
        try b.add(gpa, .init(.{ .visibility = 0, .world = frame_ms * 1_000_000 - 500_000, .overlays = 500_000 }));
    }
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try b.report(&out.writer);
    try std.testing.expectEqualStrings(
        \\100 frames  mean 50.50 ms (20 fps)  median 50.00  95% 95.00  worst 100.00
        \\per frame:  visibility 0.00 ms  world 50.00 ms  overlays 0.50 ms
        \\
    , out.written());
}
