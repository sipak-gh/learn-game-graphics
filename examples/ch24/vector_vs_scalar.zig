//! A dot product of two arrays, written twice: a plain loop, and with
//! `@Vector(8, f32)`, eight products at a time. Times both. Build it in
//! Debug and in ReleaseFast, and compare; then read both functions in
//! `objdump -d`.
const std = @import("std");

const n = 1 << 20;
const repeats = 200;

const V = @Vector(8, f32);

noinline fn dotScalar(a: []const f32, b: []const f32) f32 {
    var sum: f32 = 0;
    for (a, b) |x, y| sum += x * y;
    return sum;
}

noinline fn dotVector(a: []const f32, b: []const f32) f32 {
    var sum: V = @splat(0);
    var i: usize = 0;
    while (i + 8 <= a.len) : (i += 8) {
        const x: V = a[i..][0..8].*;
        const y: V = b[i..][0..8].*;
        sum += x * y;
    }
    var rest: f32 = 0;
    while (i < a.len) : (i += 1) rest += a[i] * b[i];
    return @reduce(.Add, sum) + rest;
}

fn time(io: std.Io, f: *const fn ([]const f32, []const f32) f32, a: []const f32, b: []const f32) struct { f32, f64 } {
    var result: f32 = 0;
    var best: i96 = std.math.maxInt(i96);
    for (0..repeats) |_| {
        const start: std.Io.Timestamp = .now(io, .awake);
        result = f(a, b);
        std.mem.doNotOptimizeAway(result);
        best = @min(best, start.durationTo(.now(io, .awake)).nanoseconds);
    }
    return .{ result, @as(f64, @floatFromInt(best)) / 1000 };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const a = try gpa.alloc(f32, n);
    defer gpa.free(a);
    const b = try gpa.alloc(f32, n);
    defer gpa.free(b);
    var prng: std.Random.DefaultPrng = .init(8);
    for (a, b) |*x, *y| {
        x.* = prng.random().float(f32);
        y.* = prng.random().float(f32);
    }

    const builtin = @import("builtin");
    std.debug.print("{t} build, {d} floats, best of {d}\n", .{ builtin.mode, n, repeats });
    const s_sum, const s_us = time(io, dotScalar, a, b);
    const v_sum, const v_us = time(io, dotVector, a, b);
    std.debug.print("scalar  {d:>8.1} us  sum {d}\n", .{ s_us, s_sum });
    std.debug.print("vector  {d:>8.1} us  sum {d}\n", .{ v_us, v_sum });
    std.debug.print("vector is {d:.2}x as fast\n", .{s_us / v_us});
}
