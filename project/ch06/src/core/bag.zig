//! The 7-bag randomizer: deal the seven pieces in a shuffled order, then
//! shuffle a fresh set. Random enough to surprise, fair enough that no piece
//! is ever missing for long.
const std = @import("std");
const Kind = @import("piece.zig").Kind;

pub const Bag = struct {
    prng: std.Random.DefaultPrng,
    kinds: [7]Kind = undefined,
    /// Pieces not yet dealt from `kinds`.
    left: usize = 0,

    /// The same seed deals the same pieces, on every machine.
    pub fn init(seed: u64) Bag {
        return .{ .prng = .init(seed) };
    }

    pub fn next(bag: *Bag) Kind {
        if (bag.left == 0) {
            bag.kinds = std.meta.tags(Kind).*;
            // A u32 index (rather than usize) makes the shuffle the same
            // on 32-bit and 64-bit targets.
            bag.prng.random().shuffleWithIndex(Kind, &bag.kinds, u32);
            bag.left = bag.kinds.len;
        }
        bag.left -= 1;
        return bag.kinds[bag.left];
    }
};

test "every group of seven holds each piece once" {
    var bag: Bag = .init(1234);
    for (0..100) |_| {
        var seen: std.enums.EnumSet(Kind) = .empty;
        for (0..7) |_| seen.insert(bag.next());
        try std.testing.expectEqual(7, seen.count());
    }
}

test "the same seed deals the same pieces" {
    var a: Bag = .init(42);
    var b: Bag = .init(42);
    var c: Bag = .init(43);
    var differs = false;
    for (0..70) |_| {
        const k = a.next();
        try std.testing.expectEqual(k, b.next());
        if (k != c.next()) differs = true;
    }
    try std.testing.expect(differs);
}
