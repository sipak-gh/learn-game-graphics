//! For a rotation, the transpose is the inverse: its columns are unit
//! length and at right angles, so R^T R = I. For a scale it is not.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Mat4 = struct {
    cols: [4]Vec4,

    fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    fn mulVec(m: Mat4, v: Vec4) Vec4 {
        var result: Vec4 = @splat(0);
        inline for (0..4) |i| result += m.cols[i] * @as(Vec4, @splat(v[i]));
        return result;
    }

    fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }

    fn transpose(m: Mat4) Mat4 {
        var t: Mat4 = undefined;
        inline for (0..4) |r| t.cols[r] = .{ m.cols[0][r], m.cols[1][r], m.cols[2][r], m.cols[3][r] };
        return t;
    }

    /// Gauss-Jordan with partial pivoting, as in delve's math.zig.
    fn inverse(m: Mat4) ?Mat4 {
        var a: [4][8]f32 = undefined;
        for (0..4) |r| {
            for (0..4) |c| {
                const col: [4]f32 = m.cols[c];
                a[r][c] = col[r];
                a[r][c + 4] = if (r == c) 1 else 0;
            }
        }
        for (0..4) |col| {
            var pivot = col;
            for (col + 1..4) |r| {
                if (@abs(a[r][col]) > @abs(a[pivot][col])) pivot = r;
            }
            if (@abs(a[pivot][col]) < 1e-12) return null;
            std.mem.swap([8]f32, &a[col], &a[pivot]);
            const inv_pivot = 1 / a[col][col];
            for (&a[col]) |*x| x.* *= inv_pivot;
            for (0..4) |r| {
                if (r == col) continue;
                const factor = a[r][col];
                for (&a[r], a[col]) |*x, p| x.* -= factor * p;
            }
        }
        var rows: [4][4]f32 = undefined;
        for (&rows, a) |*row, full| row.* = full[4..8].*;
        return fromRows(rows);
    }

    /// The largest difference between any two elements.
    fn maxDiff(a: Mat4, b: Mat4) f32 {
        var worst: f32 = 0;
        for (a.cols, b.cols) |x, y| worst = @max(worst, @reduce(.Max, @abs(x - y)));
        return worst;
    }
};

fn rotationX(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ 1, 0, 0, 0 }, .{ 0, c, -s, 0 }, .{ 0, s, c, 0 }, .{ 0, 0, 0, 1 } });
}

fn rotationZ(angle: f32) Mat4 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .fromRows(.{ .{ c, -s, 0, 0 }, .{ s, c, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

fn dot3(a: Vec4, b: Vec4) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn main() void {
    const r = rotationX(1.1).mul(rotationZ(-0.4));
    std.debug.print("column lengths: {d:.6} {d:.6} {d:.6}\n", .{
        @sqrt(dot3(r.cols[0], r.cols[0])), @sqrt(dot3(r.cols[1], r.cols[1])), @sqrt(dot3(r.cols[2], r.cols[2])),
    });
    std.debug.print("column dots:    {d:.6} {d:.6} {d:.6}\n", .{
        dot3(r.cols[0], r.cols[1]), dot3(r.cols[1], r.cols[2]), dot3(r.cols[0], r.cols[2]),
    });
    const identity = Mat4.fromRows(.{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
    std.debug.print("rotation: |R^T R - I| = {e}\n", .{r.transpose().mul(r).maxDiff(identity)});
    std.debug.print("rotation: |R^T - inverse(R)| = {e}\n", .{r.transpose().maxDiff(r.inverse().?)});

    const s = Mat4.fromRows(.{ .{ 2, 0, 0, 0 }, .{ 0, 3, 0, 0 }, .{ 0, 0, 4, 0 }, .{ 0, 0, 0, 1 } });
    std.debug.print("scale:    |S^T - inverse(S)| = {d}\n", .{s.transpose().maxDiff(s.inverse().?)});
}
