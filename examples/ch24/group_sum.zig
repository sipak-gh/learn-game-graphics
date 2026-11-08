//! Splitting work across threads with `std.Io.Group`. Sums 100 million
//! floats in 1, 2, 4 and 8 bands, one task per band, and prints how long
//! each took and what it got. Each task writes only its own slot of
//! `partial`, so no locks are needed.
const std = @import("std");

const count = 100_000_000;

/// One band's work: add up `data` into `out`.
fn sumBand(data: []const f32, out: *f64) void {
    var sum: f64 = 0;
    for (data) |x| sum += x;
    out.* = sum;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const data = try gpa.alloc(f32, count);
    defer gpa.free(data);
    var prng: std.Random.DefaultPrng = .init(24);
    const random = prng.random();
    for (data) |*x| x.* = random.float(f32);
    std.debug.print("{d} floats, {d} cores\n", .{ count, try std.Thread.getCpuCount() });

    for ([_]usize{ 1, 2, 4, 8 }) |bands| {
        var partial: [8]f64 = undefined;
        const start: std.Io.Timestamp = .now(io, .awake);
        var group: std.Io.Group = .init;
        for (0..bands) |k| {
            // Band k: elements k * n / bands to (k + 1) * n / bands.
            const band = data[k * count / bands .. (k + 1) * count / bands];
            group.async(io, sumBand, .{ band, &partial[k] });
        }
        try group.await(io);
        var total: f64 = 0;
        for (partial[0..bands]) |p| total += p;
        const ns = start.durationTo(.now(io, .awake)).nanoseconds;
        std.debug.print("{d} band(s): {d:>6.1} ms  sum {d:.6}\n", .{
            bands,
            @as(f64, @floatFromInt(ns)) / 1e6,
            total,
        });
    }
}
