//! How long can a player wait for an I piece? Deal 100 000 pieces with a
//! pure random choice and with a 7-bag, and measure the longest "drought".
const std = @import("std");

const Kind = enum { i, o, t, s, z, j, l };
const count = 100_000;

/// The 7-bag from the project (core/bag.zig), in short.
const Bag = struct {
    prng: std.Random.DefaultPrng,
    kinds: [7]Kind = undefined,
    left: usize = 0,

    fn next(bag: *Bag) Kind {
        if (bag.left == 0) {
            bag.kinds = std.meta.tags(Kind).*;
            bag.prng.random().shuffleWithIndex(Kind, &bag.kinds, u32);
            bag.left = bag.kinds.len;
        }
        bag.left -= 1;
        return bag.kinds[bag.left];
    }
};

const Stats = struct {
    /// The longest run of pieces without an I.
    longest: u32 = 0,
    /// Pieces dealt since the last I.
    since: u32 = 0,
    /// I pieces dealt.
    total: u32 = 0,

    fn add(s: *Stats, k: Kind) void {
        if (k == .i) {
            s.total += 1;
            s.since = 0;
        } else {
            s.since += 1;
            s.longest = @max(s.longest, s.since);
        }
    }
};

pub fn main() void {
    var prng: std.Random.DefaultPrng = .init(1);
    const random = prng.random();
    var bag: Bag = .{ .prng = .init(1) };

    var pure: Stats = .{};
    var bagged: Stats = .{};
    for (0..count) |_| {
        pure.add(random.enumValueWithIndex(Kind, u32));
        bagged.add(bag.next());
    }
    std.debug.print("{d} pieces dealt\n", .{count});
    std.debug.print("pure random: {d} I pieces, longest wait {d} pieces\n", .{ pure.total, pure.longest });
    std.debug.print("7-bag:       {d} I pieces, longest wait {d} pieces\n", .{ bagged.total, bagged.longest });
}
