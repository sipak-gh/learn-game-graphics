//! Timing with the std clock. Runs the same small job 1000 times, times
//! each run with `std.Io.Timestamp`, and prints the mean, the median, the
//! 95th percentile and the worst run. Run it twice: once on a quiet
//! machine, once while something else keeps the cores busy.
const std = @import("std");

/// The job: a few thousand square roots. `doNotOptimizeAway` keeps the
/// compiler from noticing that nobody uses the result.
fn job() void {
    var sum: f32 = 0;
    for (0..20_000) |i| sum += @sqrt(@as(f32, @floatFromInt(i)));
    std.mem.doNotOptimizeAway(sum);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var times: [1000]u64 = undefined;
    for (&times) |*t| {
        const start: std.Io.Timestamp = .now(io, .awake);
        job();
        t.* = @intCast(start.durationTo(.now(io, .awake)).nanoseconds);
    }

    var sum: u64 = 0;
    for (times) |t| sum += t;
    std.mem.sort(u64, &times, {}, std.sort.asc(u64));
    const n = times.len;
    const us = struct {
        fn f(ns: u64) f64 {
            return @as(f64, @floatFromInt(ns)) / 1000;
        }
    }.f;
    std.debug.print("{d} runs\n", .{n});
    std.debug.print("mean   {d:>8.2} us\n", .{us(sum) / @as(f64, @floatFromInt(n))});
    std.debug.print("median {d:>8.2} us\n", .{us(times[(n - 1) / 2])});
    std.debug.print("95%    {d:>8.2} us\n", .{us(times[(n - 1) * 95 / 100])});
    std.debug.print("worst  {d:>8.2} us\n", .{us(times[n - 1])});
    std.debug.print("best   {d:>8.2} us\n", .{us(times[0])});
}
