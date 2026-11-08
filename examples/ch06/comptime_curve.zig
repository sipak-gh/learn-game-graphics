//! The guideline gravity curve, (0.8 - (level-1) * 0.007) ^ (level-1)
//! seconds per row, turned into a table of 16.16 rows per tick while the
//! program compiles. At run time it is just 20 numbers.
const std = @import("std");

const ticks_per_second = 60;
const one_row = 1 << 16;

const gravity_table: [20]u32 = blk: {
    // std.math.pow loops a lot; comptime code gets 1000 backward branches
    // unless it asks for more.
    @setEvalBranchQuota(10_000);
    var table: [20]u32 = undefined;
    for (&table, 1..) |*g, level| {
        const n: f64 = @floatFromInt(level - 1);
        const seconds_per_row = std.math.pow(f64, 0.8 - n * 0.007, n);
        const rows_per_tick = 1.0 / (seconds_per_row * ticks_per_second);
        g.* = @intFromFloat(@ceil(@min(rows_per_tick, 20.0) * one_row));
    }
    break :blk table;
};

pub fn main() void {
    std.debug.print("level  16.16/tick   rows/tick\n", .{});
    for (gravity_table, 1..) |g, level| {
        const rows: f64 = @as(f64, @floatFromInt(g)) / one_row;
        std.debug.print("{d:>5}  {d:>10}  {d:>10.4}\n", .{ level, g, rows });
    }
}
