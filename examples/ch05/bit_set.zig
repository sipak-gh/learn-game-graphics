//! std.bit_set.IntegerBitSet(n): a set of numbers below n, one bit each,
//! stored in a single integer. Ideal for "which rows are full?".
const std = @import("std");

const rows = 22;
const RowSet = std.bit_set.IntegerBitSet(rows);

pub fn main() void {
    var full: RowSet = .empty;
    full.set(0);
    full.set(2);
    full.set(3);

    std.debug.print("size: {d} bytes, mask: 0b{b}\n", .{ @sizeOf(RowSet), full.mask });
    std.debug.print("count: {d}\n", .{full.count()});
    std.debug.print("row 1 set? {}  row 2 set? {}\n", .{ full.isSet(1), full.isSet(2) });

    std.debug.print("rows:", .{});
    var it = full.iterator(.{});
    while (it.next()) |row| std.debug.print(" {d}", .{row});
    std.debug.print("\n", .{});

    full.unset(2);
    full.toggle(21);
    std.debug.print("after unset(2), toggle(21): count {d}, first {?d}\n", .{ full.count(), full.findFirstSet() });
}
