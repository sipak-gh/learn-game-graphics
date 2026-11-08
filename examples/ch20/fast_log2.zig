//! log2 from the bits of a float. An f32 is 2^e times a mantissa m from 1
//! to 2, so log2(x) = e + log2(m). Replacing log2(m) by m - 1 is exact at
//! m = 1 and m = 2 and a little low between. Prints both for 30 values,
//! finds the largest error, and times both over many values.
const std = @import("std");

fn fastLog2(x: f32) f32 {
    const bits: u32 = @bitCast(x);
    const exponent: f32 = @floatFromInt(@as(i32, @intCast(bits >> 23)) - 127);
    const mantissa: f32 = @bitCast((bits & 0x7fffff) | 0x3f800000); // 1 to 2
    return exponent + mantissa - 1;
}

fn libraryLog2(x: f32) f32 {
    return @log2(x);
}

fn time(io: std.Io, comptime f: fn (f32) f32, xs: []const f32) struct { ns: i96, sum: f32 } {
    const start: std.Io.Timestamp = .now(io, .awake);
    var sum: f32 = 0;
    for (0..100) |_| {
        for (xs) |x| sum += f(x);
    }
    std.mem.doNotOptimizeAway(sum);
    const end: std.Io.Timestamp = .now(io, .awake);
    return .{ .ns = start.durationTo(end).nanoseconds, .sum = sum };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    std.debug.print("       x     @log2  fastLog2   error\n", .{});
    var x: f32 = 0.05;
    for (0..30) |_| {
        std.debug.print("{d:>8.3}  {d:>8.4}  {d:>8.4}  {d:>6.4}\n", .{ x, @log2(x), fastLog2(x), fastLog2(x) - @log2(x) });
        x *= 1.37;
    }

    // The error repeats in every octave, so one octave finds the worst.
    var worst: f32 = 0;
    var worst_m: f32 = 1;
    var m: f32 = 1;
    while (m < 2) : (m += 1.0 / 4096.0) {
        const e = @abs(fastLog2(m) - @log2(m));
        if (e > worst) {
            worst = e;
            worst_m = m;
        }
    }
    std.debug.print("largest error {d:.4} at m = {d:.3} (1 / ln 2 = {d:.3})\n", .{ worst, worst_m, 1.0 / @log(2.0) });

    const gpa = init.gpa;
    const xs = try gpa.alloc(f32, 1 << 20);
    defer gpa.free(xs);
    for (xs, 0..) |*v, i| v.* = 0.01 + @as(f32, @floatFromInt(i)) * 0.001;
    const lib = time(io, libraryLog2, xs);
    const fast = time(io, fastLog2, xs);
    const calls: f64 = @floatFromInt(xs.len * 100);
    std.debug.print("@log2:    {d:.2} ns per call\n", .{@as(f64, @floatFromInt(lib.ns)) / calls});
    std.debug.print("fastLog2: {d:.2} ns per call\n", .{@as(f64, @floatFromInt(fast.ns)) / calls});
}
