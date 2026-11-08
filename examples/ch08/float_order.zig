//! Float addition is not associative: the same numbers summed in another
//! order can give another answer. Integer addition always agrees.
const std = @import("std");

pub fn main() void {
    // Three numbers, two groupings.
    const a: f32 = 1e8;
    const b: f32 = -1e8;
    const c: f32 = 0.5;
    std.debug.print("(a + b) + c = {d}\n", .{(a + b) + c});
    std.debug.print("a + (b + c) = {d}\n", .{a + (b + c)});

    // Ten thousand small steps, summed forwards and backwards.
    var steps: [10_000]f32 = undefined;
    for (&steps, 0..) |*s, i| s.* = 1.0 / @as(f32, @floatFromInt(i + 1));
    var forwards: f32 = 0;
    for (steps) |s| forwards += s;
    var backwards: f32 = 0;
    var i = steps.len;
    while (i > 0) : (i -= 1) backwards += steps[i - 1];
    std.debug.print("f32 forwards  = {d}\nf32 backwards = {d}\n", .{ forwards, backwards });

    // The same steps in 16.16 fixed point: integers, so the order does not matter.
    var fwd: u64 = 0;
    var bwd: u64 = 0;
    for (steps) |s| fwd += @intFromFloat(s * 65536);
    i = steps.len;
    while (i > 0) : (i -= 1) bwd += @intFromFloat(steps[i - 1] * 65536);
    std.debug.print("fixed forwards = {d}, backwards = {d}, equal: {}\n", .{ fwd, bwd, fwd == bwd });
}
