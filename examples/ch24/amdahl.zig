//! Amdahl's law. If a share p of a program's time can be split over n
//! cores and the rest cannot, the time goes from 1 to (1 - p) + p / n,
//! and the speedup is the inverse of that. Prints the speedup for three
//! values of p, then fits p to measured times and compares the law's
//! predictions with them.
const std = @import("std");

fn speedup(p: f64, n: f64) f64 {
    return 1 / ((1 - p) + p / n);
}

/// The p that best explains measured speedups. The law says
/// 1/s - 1 = p * (1/n - 1): a straight line through the origin with slope
/// p, so least squares gives p = sum(x * y) / sum(x * x).
fn fit(cores: []const f64, speedups: []const f64) f64 {
    var xy: f64 = 0;
    var xx: f64 = 0;
    for (cores, speedups) |n, s| {
        const x = 1 / n - 1;
        const y = 1 / s - 1;
        xy += x * y;
        xx += x * x;
    }
    return xy / xx;
}

pub fn main() void {
    const cores = [_]f64{ 1, 2, 4, 8, 16, 32, 64, 1e9 };
    std.debug.print("{s:>6}", .{"p \\ n"});
    for (cores[0 .. cores.len - 1]) |n| std.debug.print("{d:>7}", .{n});
    std.debug.print("  limit\n", .{});
    for ([_]f64{ 0.5, 0.9, 0.99 }) |p| {
        std.debug.print("{d:>6.2}", .{p});
        for (cores) |n| std.debug.print("{d:>7.2}", .{speedup(p, n)});
        std.debug.print("\n", .{});
    }

    // delve's tour, Phong, mean ms per frame on n threads (chapter 24).
    const threads = [_]f64{ 1, 2, 3, 4, 6, 8, 12, 16, 24, 32 };
    const ms = [_]f64{ 14.74, 8.44, 6.45, 4.83, 3.81, 3.76, 2.88, 2.53, 2.16, 2.19 };
    var measured: [ms.len]f64 = undefined;
    for (&measured, ms) |*s, t| s.* = ms[0] / t;
    const p = fit(&threads, &measured);
    std.debug.print("fitted: p = {d:.3}\n", .{p});
    std.debug.print("threads  measured  predicted\n", .{});
    for (threads, measured) |n, s| {
        std.debug.print("{d:>7}  {d:>8.2}  {d:>9.2}\n", .{ n, s, speedup(p, n) });
    }
}
