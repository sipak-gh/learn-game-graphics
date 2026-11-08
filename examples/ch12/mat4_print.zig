//! A Mat4 that prints itself the way books write matrices, and the order
//! its sixteen numbers really have in memory.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Mat4 = struct {
    cols: [4]Vec4,

    /// Rows in, columns stored: element (r, c) goes to cols[c][r].
    fn fromRows(rows: [4][4]f32) Mat4 {
        var m: Mat4 = undefined;
        for (0..4) |c| m.cols[c] = .{ rows[0][c], rows[1][c], rows[2][c], rows[3][c] };
        return m;
    }

    fn at(m: Mat4, r: usize, c: usize) f32 {
        const col: [4]f32 = m.cols[c];
        return col[r];
    }

    /// Used by `{f}`: one line per row.
    pub fn format(m: Mat4, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (0..4) |r| {
            try w.writeAll("| ");
            for (0..4) |c| try w.print("{d:>4} ", .{m.at(r, c)});
            try w.writeAll("|\n");
        }
    }
};

pub fn main() void {
    // Written as on paper: a translation by (7, 8, 9) in the last column,
    // a scale of 2, 3, 4 on the diagonal.
    const m: Mat4 = .fromRows(.{
        .{ 2, 0, 0, 7 },
        .{ 0, 3, 0, 8 },
        .{ 0, 0, 4, 9 },
        .{ 0, 0, 0, 1 },
    });
    std.debug.print("m =\n{f}", .{m});
    std.debug.print("m.at(0, 3) = {d} (row 0, column 3)\n", .{m.at(0, 3)});

    // In memory the columns come one after another: column-major order.
    const flat: *const [16]f32 = @ptrCast(&m.cols);
    std.debug.print("memory: {any}\n", .{flat.*});
    std.debug.print("@sizeOf(Mat4) = {d} bytes\n", .{@sizeOf(Mat4)});
}
