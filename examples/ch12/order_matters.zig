//! Matrix products apply right to left, and the order changes the result.
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

    /// a.mul(b): each column of b transformed by a. Applies b first.
    fn mul(a: Mat4, b: Mat4) Mat4 {
        var m: Mat4 = undefined;
        for (&m.cols, b.cols) |*col, b_col| col.* = a.mulVec(b_col);
        return m;
    }

    pub fn format(m: Mat4, w: *std.Io.Writer) std.Io.Writer.Error!void {
        inline for (0..4) |r| {
            try w.writeAll("  |");
            inline for (0..4) |c| try w.print(" {d:>3}", .{m.cols[c][r]});
            try w.writeAll(" |\n");
        }
    }
};

fn translation(x: f32, y: f32) Mat4 {
    return .fromRows(.{ .{ 1, 0, 0, x }, .{ 0, 1, 0, y }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });
}

/// A quarter turn about z: x goes to y, y goes to -x. (cos 90 = 0 and
/// sin 90 = 1 are written exactly, to keep the printout clean.)
const quarter_turn: Mat4 = .fromRows(.{ .{ 0, -1, 0, 0 }, .{ 1, 0, 0, 0 }, .{ 0, 0, 1, 0 }, .{ 0, 0, 0, 1 } });

pub fn main() void {
    const t = translation(5, 0);
    const r = quarter_turn;
    const p: Vec4 = .{ 1, 0, 0, 1 };

    std.debug.print("T R (rotate first, then translate):\n{f}", .{t.mul(r)});
    std.debug.print("T R p = {any}\n", .{t.mul(r).mulVec(p)});
    std.debug.print("step by step: R p = {any}, then T = {any}\n\n", .{ r.mulVec(p), t.mulVec(r.mulVec(p)) });

    std.debug.print("R T (translate first, then rotate):\n{f}", .{r.mul(t)});
    std.debug.print("R T p = {any}\n", .{r.mul(t).mulVec(p)});
    std.debug.print("step by step: T p = {any}, then R = {any}\n", .{ t.mulVec(p), r.mulVec(t.mulVec(p)) });
}
