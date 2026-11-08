//! Shuffling seven pieces with a seeded generator. `shuffle` draws its
//! random indices as usize, whose size depends on the target; with
//! `shuffleWithIndex(..., u32)` the same seed gives the same order everywhere.
const std = @import("std");

const Kind = enum { i, o, t, s, z, j, l };

fn printKinds(label: []const u8, kinds: []const Kind) void {
    std.debug.print("{s}", .{label});
    for (kinds) |k| std.debug.print(" {t}", .{k});
    std.debug.print("\n", .{});
}

pub fn main() void {
    std.debug.print("usize is {d} bits\n", .{@bitSizeOf(usize)});

    var a: std.Random.DefaultPrng = .init(7);
    var kinds = std.meta.tags(Kind).*; // a copy we may reorder
    a.random().shuffle(Kind, &kinds);
    printKinds("shuffle:               ", &kinds);

    var b: std.Random.DefaultPrng = .init(7);
    kinds = std.meta.tags(Kind).*;
    b.random().shuffleWithIndex(Kind, &kinds, u32);
    printKinds("shuffleWithIndex(u32): ", &kinds);
}
