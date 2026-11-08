//! Reading vector lanes in a loop. `v[i]` needs a comptime-known `i` when
//! `v` is a runtime vector; these are the two ways around that.
const std = @import("std");

const Vec4 = @Vector(4, f32);

/// The largest lane, with the loop unrolled at compile time: every `i`
/// is a comptime constant, so `v[i]` is allowed.
fn maxLaneInline(v: Vec4) f32 {
    var best = v[0];
    inline for (1..4) |i| best = @max(best, v[i]);
    return best;
}

/// The same with a runtime loop over an array copy: array elements can be
/// indexed by runtime values.
fn maxLaneArray(v: Vec4) f32 {
    const lanes: [4]f32 = v;
    var best = lanes[0];
    for (lanes[1..]) |x| best = @max(best, x);
    return best;
}

/// Lane `i`, where `i` is only known at run time.
fn lane(v: Vec4, i: usize) f32 {
    const lanes: [4]f32 = v;
    return lanes[i];
}

pub fn main() void {
    var v: Vec4 = .{ 3, -1, 8, 2 };
    v[1] = 5; // a comptime index works for writing too
    std.debug.print("v = {any}\n", .{v});
    std.debug.print("maxLaneInline = {d}\n", .{maxLaneInline(v)});
    std.debug.print("maxLaneArray  = {d}\n", .{maxLaneArray(v)});
    for (0..4) |i| std.debug.print("lane({d}) = {d}\n", .{ i, lane(v, i) });
    // For the common "largest lane" there is a builtin as well.
    std.debug.print("@reduce(.Max, v) = {d}\n", .{@reduce(.Max, v)});
}
