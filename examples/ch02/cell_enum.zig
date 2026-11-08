//! What a board cell holds, as an enum with a fixed integer type.
const std = @import("std");

/// What fills one cell. A locked piece keeps its letter, so it keeps its color.
pub const Cell = enum(u8) {
    empty,
    i,
    o,
    t,
    s,
    z,
    j,
    l,
    garbage,

    /// The character for this cell in a board picture.
    pub fn char(cell: Cell) u8 {
        return ".IOTSZJL#"[@backingInt(cell)];
    }

    pub fn fromChar(c: u8) ?Cell {
        const index = std.mem.findScalar(u8, ".IOTSZJL#", c) orelse return null;
        return @fromBackingInt(@intCast(index));
    }
};

/// An exhaustive switch: add a tag and the compiler finds every switch
/// that does not handle it.
fn describe(cell: Cell) []const u8 {
    return switch (cell) {
        .empty => "nothing",
        .i, .o, .t, .s, .z, .j, .l => "part of a piece",
        .garbage => "garbage",
    };
}

pub fn main() void {
    std.debug.print("@sizeOf(Cell) = {d}\n", .{@sizeOf(Cell)});
    for (std.enums.values(Cell)) |cell| {
        std.debug.print("{d}  {c}  .{t:<8} {s}\n", .{ @backingInt(cell), cell.char(), cell, describe(cell) });
    }
    std.debug.print("fromChar('T') = {?}\n", .{Cell.fromChar('T')});
    std.debug.print("fromChar('x') = {?}\n", .{Cell.fromChar('x')});
}
