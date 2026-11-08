//! A golden test pins down a whole result, here a picture of a pile of
//! blocks built from a seed. Write the test with an empty expectation, run
//! it, check the actual output by eye, then paste it in.
const std = @import("std");

const cols = 6;
const rows = 4;

const Pile = struct {
    heights: [cols]u8 = @splat(0),

    /// Top row first, like the board pictures in quadfall's tests.
    pub fn format(p: Pile, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var row: u8 = rows;
        while (row > 0) : (row -= 1) {
            for (p.heights) |h| try w.writeByte(if (h >= row) '#' else '.');
            if (row > 1) try w.writeByte('\n');
        }
    }
};

/// Drops ten blocks into random columns; a full column takes no more.
fn play(seed: u64) Pile {
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();
    var p: Pile = .{};
    for (0..10) |_| {
        const col = random.uintLessThan(u32, cols);
        if (p.heights[col] < rows) p.heights[col] += 1;
    }
    return p;
}

test "seed 7 builds this pile" {
    try std.testing.expectFmt(
        \\.....#
        \\..#..#
        \\..#..#
        \\###.##
    , "{f}", .{play(7)});
}
