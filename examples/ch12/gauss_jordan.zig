//! Gauss-Jordan elimination, step by step: row operations that turn M into
//! the identity turn the identity next to it into M's inverse.
const std = @import("std");

const n = 3;
const Row = [2 * n]f32;

fn printAug(title: []const u8, a: [n]Row) void {
    std.debug.print("{s}\n", .{title});
    for (a) |row| {
        std.debug.print("  [", .{});
        for (row[0..n]) |x| std.debug.print(" {d:>6.3}", .{x});
        std.debug.print(" |", .{});
        for (row[n..]) |x| std.debug.print(" {d:>6.3}", .{x});
        std.debug.print(" ]\n", .{});
    }
}

fn inverse(m: [n][n]f32) ?[n][n]f32 {
    var a: [n]Row = undefined; // [m | identity]
    for (0..n) |r| {
        for (0..n) |c| {
            a[r][c] = m[r][c];
            a[r][c + n] = if (r == c) 1 else 0;
        }
    }
    printAug("start [M | I]:", a);
    for (0..n) |col| {
        // Partial pivoting: use the row with the largest entry in this
        // column, so we never divide by zero or by a tiny number.
        var pivot = col;
        for (col + 1..n) |r| {
            if (@abs(a[r][col]) > @abs(a[pivot][col])) pivot = r;
        }
        if (@abs(a[pivot][col]) < 1e-12) {
            std.debug.print("column {d}: no usable pivot, the matrix is singular\n", .{col});
            return null;
        }
        std.mem.swap(Row, &a[col], &a[pivot]);
        // Scale the pivot row so the pivot becomes 1...
        const inv_pivot = 1 / a[col][col];
        for (&a[col]) |*x| x.* *= inv_pivot;
        // ...then subtract it from every other row to clear the column.
        for (0..n) |r| {
            if (r == col) continue;
            const factor = a[r][col];
            for (&a[r], a[col]) |*x, p| x.* -= factor * p;
        }
        var title: [64]u8 = undefined;
        printAug(std.fmt.bufPrint(&title, "column {d} (pivot from row {d}):", .{ col, pivot }) catch unreachable, a);
    }
    var result: [n][n]f32 = undefined;
    for (&result, a) |*out, row| out.* = row[n..].*;
    return result;
}

pub fn main() void {
    const m: [n][n]f32 = .{ .{ 0, 2, 1 }, .{ 1, 1, 0 }, .{ 2, 0, 1 } };
    const inv = inverse(m).?;

    // Check: M times its inverse should be the identity.
    std.debug.print("M * inverse:\n", .{});
    for (0..n) |r| {
        std.debug.print(" ", .{});
        for (0..n) |c| {
            var sum: f32 = 0;
            for (0..n) |k| sum += m[r][k] * inv[k][c];
            std.debug.print(" {d:>6.3}", .{sum});
        }
        std.debug.print("\n", .{});
    }

    // Row 1 is twice row 0, so this matrix squashes space onto a plane.
    std.debug.print("\n", .{});
    const flat: [n][n]f32 = .{ .{ 1, 2, 3 }, .{ 2, 4, 6 }, .{ 1, 0, 1 } };
    std.debug.print("singular inverse: {any}\n", .{inverse(flat)});
}
