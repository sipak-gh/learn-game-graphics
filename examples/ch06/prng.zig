//! A pseudo-random number generator (PRNG) is a function of its state. Seed
//! it with the same number and it produces the same sequence, every time.
const std = @import("std");

fn rolls(seed: u64) [8]u8 {
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var out: [8]u8 = undefined;
    for (&out) |*r| r.* = random.intRangeLessThan(u8, 0, 7);
    return out;
}

pub fn main() void {
    std.debug.print("seed 7:  {any}\n", .{rolls(7)});
    std.debug.print("seed 7:  {any}\n", .{rolls(7)});
    std.debug.print("seed 8:  {any}\n", .{rolls(8)});

    // random() is a small interface (a pointer and a function) over the
    // generator's state, which lives in `prng`.
    var prng: std.Random.DefaultPrng = .init(7);
    const random = prng.random();
    std.debug.print("state: {d} bytes; float {d:.4}; bool {}; u64 0x{x}\n", .{
        @sizeOf(std.Random.DefaultPrng), random.float(f32), random.boolean(), random.int(u64),
    });
}
