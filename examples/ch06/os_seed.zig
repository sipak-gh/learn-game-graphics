//! A seed from the operating system: different on every run. The program
//! prints it, so a run worth repeating can be repeated with that seed.
const std = @import("std");

pub fn main(init: std.process.Init) void {
    var bytes: [8]u8 = undefined;
    init.io.random(&bytes);
    const seed = std.mem.readInt(u64, &bytes, .little);
    std.debug.print("bytes: {x}\n", .{&bytes});
    std.debug.print("seed:  {d}\n", .{seed});

    var prng: std.Random.DefaultPrng = .init(seed);
    std.debug.print("first roll: {d}\n", .{prng.random().intRangeLessThan(u8, 0, 7)});
}
