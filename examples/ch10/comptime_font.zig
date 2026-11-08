//! A three-glyph bitmap font, written as text and turned into bit masks at
//! compile time. The program only prints the table the compiler built.
const std = @import("std");

/// One glyph per line: the character, then 7 rows of 5 pixels.
const source =
    \\H #...# #...# #...# ##### #...# #...# #...#
    \\I .###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.
    \\! ..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..
    // A mistyped glyph: its last row is missing. Uncomment it to see the
    // compiler catch the mistake.
    // \\X #...# #...# .#.#. ..#.. .#.#. #...#
;

const Glyph = [7]u5; // one 5-bit mask per row, leftmost pixel in bit 4

const glyphs: [128]Glyph = blk: {
    @setEvalBranchQuota(10_000);
    var table: [128]Glyph = @splat(@splat(0));
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |text| {
        // A character, a space, and 7 groups of 5 separated by spaces.
        if (text.len != 2 + 7 * 6 - 1) {
            @compileError(std.fmt.comptimePrint("glyph '{c}': {d} characters, expected 43", .{ text[0], text.len }));
        }
        var glyph: Glyph = undefined;
        for (&glyph, 0..) |*bits, row| {
            bits.* = 0;
            for (text[2 + row * 6 ..][0..5]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
        }
        table[text[0]] = glyph;
    }
    break :blk table;
};

pub fn main() void {
    for ("HI!") |char| {
        std.debug.print("'{c}':", .{char});
        for (glyphs[char]) |bits| std.debug.print(" {b:0>5}", .{bits});
        std.debug.print("\n", .{});
    }
    // Draw the same masks as text: each set bit is a '#'.
    for (0..7) |row| {
        for ("HI!") |char| {
            const bits = glyphs[char][row];
            for (0..5) |col| {
                const set = bits & (@as(u5, 1) << @intCast(4 - col)) != 0;
                std.debug.print("{c}", .{@as(u8, if (set) '#' else '.')});
            }
            std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("the table is {d} bytes of constant data\n", .{@sizeOf(@TypeOf(glyphs))});
}
