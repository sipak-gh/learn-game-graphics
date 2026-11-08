//! All seven pieces in all four rotation states, computed at compile time
//! from one picture each (the same code as quadfall's core/piece.zig).
const std = @import("std");

const Pos = struct { col: i32, row: i32 };
const Shape = [4]Pos;
const Kind = enum { i, o, t, s, z, j, l };

fn boxSize(kind: Kind) i32 {
    return switch (kind) {
        .i => 4,
        .o => 2,
        .t, .s, .z, .j, .l => 3,
    };
}

const spawn_pictures: std.enums.EnumArray(Kind, []const u8) = .init(.{
    .i = "....\nXXXX\n....\n....",
    .o = "XX\nXX",
    .t = ".X.\nXXX\n...",
    .s = ".XX\nXX.\n...",
    .z = "XX.\n.XX\n...",
    .j = "X..\nXXX\n...",
    .l = "..X\nXXX\n...",
});

fn parseShape(kind: Kind) Shape {
    var shape: Shape = undefined;
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, spawn_pictures.get(kind), '\n');
    var row: i32 = boxSize(kind) - 1;
    while (lines.next()) |line| : (row -= 1) {
        for (line, 0..) |c, col| if (c == 'X') {
            shape[n] = .{ .col = @intCast(col), .row = row };
            n += 1;
        };
    }
    if (n != 4) @compileError("a tetromino has exactly four cells");
    return shape;
}

fn rotateCw(shape: Shape, size: i32) Shape {
    var out: Shape = undefined;
    for (shape, &out) |p, *q| q.* = .{ .col = p.row, .row = size - 1 - p.col };
    return out;
}

const shapes: std.enums.EnumArray(Kind, [4]Shape) = blk: {
    var table: std.enums.EnumArray(Kind, [4]Shape) = .initUndefined();
    for (std.meta.tags(Kind)) |kind| {
        var shape = parseShape(kind);
        for (0..4) |r| {
            table.getPtr(kind)[r] = shape;
            shape = rotateCw(shape, boxSize(kind));
        }
    }
    break :blk table;
};

pub fn main() void {
    std.debug.print("     spawn right flip  left\n", .{});
    for (std.meta.tags(Kind)) |kind| {
        const n = boxSize(kind);
        var row = n - 1;
        while (row >= 0) : (row -= 1) {
            const label: u8 = if (row == n - 1) std.ascii.toUpper(@tagName(kind)[0]) else ' ';
            std.debug.print("{c}    ", .{label});
            for (shapes.get(kind), 0..) |shape, r| {
                if (r > 0) for (0..6 - @as(usize, @intCast(n))) |_| std.debug.print(" ", .{});
                var col: i32 = 0;
                while (col < n) : (col += 1) {
                    var filled = false;
                    for (shape) |p| filled = filled or (p.col == col and p.row == row);
                    std.debug.print("{c}", .{@as(u8, if (filled) '#' else '.')});
                }
            }
            std.debug.print("\n", .{});
        }
    }
}
