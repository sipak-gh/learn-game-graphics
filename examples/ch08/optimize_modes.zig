//! The same code in each optimize mode. Safe modes stop at an integer
//! overflow; fast and small modes assume it never happens.
const std = @import("std");
const builtin = @import("builtin");

/// Adds up `n` scores of 100 in a u16, which holds at most 65535.
fn total(n: u32) u16 {
    var sum: u16 = 0;
    for (0..n) |_| sum += 100;
    return sum;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    // Read n at run time, so the compiler cannot work out the answer itself.
    const n = try std.fmt.parseInt(u32, args[1], 10);
    std.debug.print("mode {t}: total({d}) = {d}\n", .{ builtin.mode, n, total(n) });
}
