//! A `format` method lets a type print itself with `{f}`.
const std = @import("std");

const Pos = struct {
    col: i32,
    row: i32,

    /// Called by `{f}`. It writes to any std.Io.Writer: a terminal, a
    /// buffer, a file. It may only fail with the writer's own error.
    pub fn format(pos: Pos, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("({d},{d})", .{ pos.col, pos.row });
    }
};

/// A 3x3 grid that prints as three lines, top row first, with no
/// newline after the last one.
const Tiny = struct {
    cells: [3][3]u8 = @splat(@splat('.')),

    pub fn format(t: Tiny, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var row: usize = 3;
        while (row > 0) {
            row -= 1;
            try w.writeAll(&t.cells[row]);
            if (row > 0) try w.writeByte('\n');
        }
    }
};

test "Pos prints as (col,row)" {
    const p: Pos = .{ .col = 4, .row = -1 };
    try std.testing.expectFmt("(4,-1)", "{f}", .{p});
    try std.testing.expectFmt("at (4,-1)!", "at {f}!", .{p});
}

test "Tiny prints the top row first" {
    var t: Tiny = .{};
    t.cells[0][0] = '#'; // bottom-left
    t.cells[2][2] = '#'; // top-right
    try std.testing.expectFmt(
        \\..#
        \\...
        \\#..
    , "{f}", .{t});
}

test "formatting into a buffer" {
    var buf: [32]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try w.print("{f} {f}", .{ Pos{ .col = 0, .row = 0 }, Pos{ .col = 9, .row = 21 } });
    try std.testing.expectEqualStrings("(0,0) (9,21)", w.buffered());
}
