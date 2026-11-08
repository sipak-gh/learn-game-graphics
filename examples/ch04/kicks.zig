//! Wall kicks: when a turned piece does not fit, try a few offsets in a
//! fixed order and keep the first one that fits.
const std = @import("std");

const Pos = struct { col: i32, row: i32 };
const Shape = [4]Pos;

fn rotateCw(shape: Shape) Shape {
    var out: Shape = undefined;
    for (shape, &out) |p, *q| q.* = .{ .col = p.row, .row = 2 - p.col };
    return out;
}

/// The T in its four states (spawn, right, flip, left), in a 3x3 box.
const t_shapes: [4]Shape = blk: {
    var s: Shape = .{ .{ .col = 1, .row = 2 }, .{ .col = 0, .row = 1 }, .{ .col = 1, .row = 1 }, .{ .col = 2, .row = 1 } };
    var table: [4]Shape = undefined;
    for (&table) |*t| {
        t.* = s;
        s = rotateCw(s);
    }
    break :blk table;
};

/// SRS offsets (columns right, rows up) for a clockwise turn of J, L, S, T, Z,
/// indexed by the state the piece turns from.
const cw_kicks: [4][5][2]i32 = .{
    .{ .{ 0, 0 }, .{ -1, 0 }, .{ -1, 1 }, .{ 0, -2 }, .{ -1, -2 } }, // 0->R
    .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, -1 }, .{ 0, 2 }, .{ 1, 2 } }, // R->2
    .{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, -2 }, .{ 1, -2 } }, // 2->L
    .{ .{ 0, 0 }, .{ -1, 0 }, .{ -1, -1 }, .{ 0, 2 }, .{ -1, 2 } }, // L->0
};

/// A 10x5 board; row 0 is the last line of the picture.
fn fits(picture: *const [5][10]u8, rot: usize, box: Pos) bool {
    for (t_shapes[rot]) |p| {
        const col = box.col + p.col;
        const row = box.row + p.row;
        if (col < 0 or col >= 10 or row < 0 or row >= 5) return false;
        if (picture[@intCast(4 - row)][@intCast(col)] != '.') return false;
    }
    return true;
}

fn turnCw(name: []const u8, picture: *const [5][10]u8, rot: usize, box: Pos) void {
    std.debug.print("{s}:", .{name});
    for (cw_kicks[rot], 0..) |k, i| {
        const moved: Pos = .{ .col = box.col + k[0], .row = box.row + k[1] };
        if (fits(picture, (rot + 1) % 4, moved)) {
            std.debug.print(" test {d} ({d},{d}) fits, box -> ({d},{d})\n", .{ i + 1, k[0], k[1], moved.col, moved.row });
            return;
        }
        std.debug.print(" test {d} ({d},{d}) no;", .{ i + 1, k[0], k[1] });
    }
    std.debug.print(" the turn is refused\n", .{});
}

pub fn main() void {
    const open: [5][10]u8 = .{ "..........".*, "..........".*, "..........".*, "..........".*, "..........".* };
    const shaft: [5][10]u8 = .{ "###.######".*, "###.######".*, "###..#####".*, "###.######".*, "###.######".* };
    turnCw("open field, spawn -> right", &open, 0, .{ .col = 3, .row = 1 });
    turnCw("left state at the right wall", &open, 3, .{ .col = 8, .row = 1 });
    // The box may hang below the floor: only the four cells must fit.
    turnCw("spawn state lying on the floor", &open, 0, .{ .col = 3, .row = -1 });
    turnCw("right state in a shaft", &shaft, 1, .{ .col = 2, .row = 1 });
}
