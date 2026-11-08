//! Building a lookup table while the program compiles. The table ends up
//! in the executable as plain data; nothing is computed when it runs.
const std = @import("std");

const Pos = struct { col: i32, row: i32 };
const Shape = [4]Pos;

fn rotateCw(shape: Shape, n: i32) Shape {
    var out: Shape = undefined;
    for (shape, &out) |p, *q| q.* = .{ .col = p.row, .row = n - 1 - p.col };
    return out;
}

const t_spawn: Shape = .{
    .{ .col = 1, .row = 2 }, .{ .col = 0, .row = 1 },
    .{ .col = 1, .row = 1 }, .{ .col = 2, .row = 1 },
};

/// Container-level constants are always evaluated at compile time, so the
/// labelled block below runs inside the compiler.
const t_shapes: [4]Shape = blk: {
    var table: [4]Shape = undefined;
    var shape = t_spawn;
    for (&table) |*slot| {
        slot.* = shape;
        shape = rotateCw(shape, 3);
    }
    break :blk table;
};

fn squares(comptime n: usize) [n]u32 {
    var out: [n]u32 = undefined;
    for (&out, 0..) |*s, i| s.* = @intCast(i * i);
    return out;
}

pub fn main() void {
    // Using the table is an index, nothing more.
    for (t_shapes, 0..) |shape, r| {
        std.debug.print("rotation {d}:", .{r});
        for (shape) |p| std.debug.print(" ({d},{d})", .{ p.col, p.row });
        std.debug.print("\n", .{});
    }
    // Inside a function, `comptime` forces compile-time evaluation.
    const sq = comptime squares(6);
    std.debug.print("squares: {any}\n", .{sq});
    std.debug.print("table size: {d} bytes\n", .{@sizeOf(@TypeOf(t_shapes))});
}
