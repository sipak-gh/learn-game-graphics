//! The command-line arguments, through `std.process.Init`.
const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    // The arena is freed when main returns, so nothing here needs a free.
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    std.debug.print("{d} arguments\n", .{args.len});
    for (args, 0..) |arg, i| {
        std.debug.print("  [{d}] {s} ({d} bytes)\n", .{ i, arg, arg.len });
    }
    if (args.len < 2) {
        std.log.err("expected at least one argument", .{});
        return 2;
    }
    return 0;
}
