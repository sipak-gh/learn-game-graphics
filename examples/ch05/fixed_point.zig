//! 16.16 fixed point: a whole number of 1/65536ths. Integers add exactly,
//! so the same steps give the same result on every machine.
const std = @import("std");

const one: u32 = 1 << 16; // 1.0 in 16.16

/// Ticks until `per_tick` (in 1/65536ths) adds up to one whole row.
fn ticksToFall(per_tick: u32) u32 {
    var fall: u32 = 0;
    var ticks: u32 = 0;
    while (fall < one) : (ticks += 1) fall += per_tick;
    return ticks;
}

pub fn main() !void {
    // Ten steps of 0.1 in floating point.
    var f: f32 = 0;
    for (0..10) |_| f += 0.1;
    std.debug.print("f32: 0.1 * 10 = {d:.9}, == 1.0? {}\n", .{ f, f == 1.0 });

    // The same in 16.16: 0.1 is 6554/65536 (rounded), and the sum is exact.
    const tenth: u32 = (one + 5) / 10;
    var x: u32 = 0;
    for (0..10) |_| x += tenth;
    std.debug.print("16.16: tenth = {d}, sum = {d} = {d} + {d}/65536\n", .{ tenth, x, x >> 16, x & 0xffff });

    // One row per second at 60 ticks per second.
    const down = one / 60;
    const up = try std.math.divCeil(u32, one, 60);
    std.debug.print("65536 / 60 = {d}: {d} ticks to fall a row\n", .{ down, ticksToFall(down) });
    std.debug.print("divCeil    = {d}: {d} ticks to fall a row\n", .{ up, ticksToFall(up) });
}
