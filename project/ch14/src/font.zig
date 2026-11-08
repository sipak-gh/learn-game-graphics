//! A tiny 5x7 bitmap font for the HUD. The glyphs are drawn as text below
//! and turned into bit masks at compile time.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");

pub const glyph_width = 5;
pub const glyph_height = 7;
/// Distance from one character to the next, including a 1-pixel gap.
pub const advance = glyph_width + 1;

/// One line per glyph: the character, a space, then 7 rows of 5 pixels.
const source =
    \\A .###. #...# #...# ##### #...# #...# #...#
    \\B ####. #...# #...# ####. #...# #...# ####.
    \\C .###. #...# #.... #.... #.... #...# .###.
    \\D ####. #...# #...# #...# #...# #...# ####.
    \\E ##### #.... #.... ####. #.... #.... #####
    \\F ##### #.... #.... ####. #.... #.... #....
    \\G .###. #...# #.... #.### #...# #...# .####
    \\H #...# #...# #...# ##### #...# #...# #...#
    \\I .###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.
    \\J ..### ...#. ...#. ...#. ...#. #..#. .##..
    \\K #...# #..#. #.#.. ##... #.#.. #..#. #...#
    \\L #.... #.... #.... #.... #.... #.... #####
    \\M #...# ##.## #.#.# #.#.# #...# #...# #...#
    \\N #...# #...# ##..# #.#.# #..## #...# #...#
    \\O .###. #...# #...# #...# #...# #...# .###.
    \\P ####. #...# #...# ####. #.... #.... #....
    \\Q .###. #...# #...# #...# #.#.# #..#. .##.#
    \\R ####. #...# #...# ####. #.#.. #..#. #...#
    \\S .#### #.... #.... .###. ....# ....# ####.
    \\T ##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..
    \\U #...# #...# #...# #...# #...# #...# .###.
    \\V #...# #...# #...# #...# #...# .#.#. ..#..
    \\W #...# #...# #...# #.#.# #.#.# #.#.# .#.#.
    \\X #...# #...# .#.#. ..#.. .#.#. #...# #...#
    \\Y #...# #...# .#.#. ..#.. ..#.. ..#.. ..#..
    \\Z ##### ....# ...#. ..#.. .#... #.... #####
    \\0 .###. #...# #..## #.#.# ##..# #...# .###.
    \\1 ..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.
    \\2 .###. #...# ....# ...#. ..#.. .#... #####
    \\3 ####. ....# ....# .###. ....# ....# ####.
    \\4 ...#. ..##. .#.#. #..#. ##### ...#. ...#.
    \\5 ##### #.... ####. ....# ....# #...# .###.
    \\6 ..##. .#... #.... ####. #...# #...# .###.
    \\7 ##### ....# ...#. ..#.. .#... .#... .#...
    \\8 .###. #...# #...# .###. #...# #...# .###.
    \\9 .###. #...# #...# .#### ....# ...#. .##..
    \\! ..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..
    \\" .#.#. .#.#. ..... ..... ..... ..... .....
    \\# .#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.
    \\% ##..# ##..# ...#. ..#.. .#... #..## #..##
    \\' ..#.. ..#.. ..... ..... ..... ..... .....
    \\( ...#. ..#.. .#... .#... .#... ..#.. ...#.
    \\) .#... ..#.. ...#. ...#. ...#. ..#.. .#...
    \\* ..... ..#.. #.#.# .###. #.#.# ..#.. .....
    \\+ ..... ..#.. ..#.. ##### ..#.. ..#.. .....
    \\, ..... ..... ..... ..... .##.. ..#.. .#...
    \\- ..... ..... ..... ##### ..... ..... .....
    \\. ..... ..... ..... ..... ..... .##.. .##..
    \\/ ....# ....# ...#. ..#.. .#... #.... #....
    \\: ..... .##.. .##.. ..... .##.. .##.. .....
    \\; ..... .##.. .##.. ..... .##.. ..#.. .#...
    \\< ...#. ..#.. .#... #.... .#... ..#.. ...#.
    \\= ..... ..... ##### ..... ##### ..... .....
    \\> .#... ..#.. ...#. ....# ...#. ..#.. .#...
    \\? .###. #...# ....# ...#. ..#.. ..... ..#..
    \\[ .###. .#... .#... .#... .#... .#... .###.
    \\] .###. ...#. ...#. ...#. ...#. ...#. .###.
    \\_ ..... ..... ..... ..... ..... ..... #####
    \\| ..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..
;

/// One glyph: 7 rows, each a 5-bit mask with the leftmost pixel in bit 4.
const Glyph = [glyph_height]u5;

/// Glyphs indexed by ASCII code; characters without a glyph stay blank.
const glyphs: [128]Glyph = blk: {
    @setEvalBranchQuota(100_000);
    var table: [128]Glyph = @splat(@splat(0));
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |text| {
        var glyph: Glyph = undefined;
        for (&glyph, 0..) |*bits, row| {
            bits.* = 0;
            for (text[2 + row * 6 ..][0..glyph_width]) |c| bits.* = (bits.* << 1) | @intFromBool(c == '#');
        }
        table[text[0]] = glyph;
    }
    break :blk table;
};

/// Draws `text` with its top-left corner at (x, y), each font pixel a
/// `scale` x `scale` square. Lowercase letters use the uppercase glyphs.
/// Returns the x coordinate just past the last character.
pub fn drawText(canvas: Canvas, x: i32, y: i32, text: []const u8, scale: i32, color: Color) i32 {
    var pen = x;
    for (text) |char| {
        const glyph = glyphs[std.ascii.toUpper(char) & 0x7f];
        for (glyph, 0..) |bits, row| {
            for (0..glyph_width) |col| {
                const bit = @as(u5, 1) << @intCast(glyph_width - 1 - col);
                if (bits & bit == 0) continue;
                const px = pen + @as(i32, @intCast(col)) * scale;
                const py = y + @as(i32, @intCast(row)) * scale;
                draw.fillRect(canvas, px, py, scale, scale, color);
            }
        }
        pen += advance * scale;
    }
    return pen;
}

/// The width in pixels of `text` drawn at `scale`, without the final gap.
pub fn textWidth(text: []const u8, scale: i32) i32 {
    if (text.len == 0) return 0;
    return (@as(i32, @intCast(text.len)) * advance - 1) * scale;
}

test "glyphs are parsed at compile time" {
    // The letter T: a full top row, then the middle column.
    try std.testing.expectEqual(0b11111, glyphs['T'][0]);
    try std.testing.expectEqual(0b00100, glyphs['T'][6]);
    try std.testing.expectEqual(@as(Glyph, @splat(0)), glyphs[' ']);
}

test "drawText returns the pen position" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 40, 10);
    defer canvas.deinit(gpa);
    try std.testing.expectEqual(2 + 3 * advance, drawText(canvas, 2, 1, "abc", 1, Color.white));
    try std.testing.expectEqual(17, textWidth("abc", 1));
}
