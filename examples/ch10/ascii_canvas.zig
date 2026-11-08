//! A canvas of characters, so drawing algorithms can show their pixels in
//! the terminal. The other ch10 examples import it:
//! `const Ascii = @import("ascii_canvas.zig").Ascii;`
const std = @import("std");

pub const Ascii = struct {
    pub const width = 32;
    pub const height = 13;

    cells: [height][width]u8 = @splat(@splat('.')),

    /// Sets one cell. Like the project's Canvas.set, it ignores
    /// coordinates outside the canvas.
    pub fn set(canvas: *Ascii, x: i32, y: i32, char: u8) void {
        if (x < 0 or y < 0 or x >= width or y >= height) return;
        canvas.cells[@intCast(y)][@intCast(x)] = char;
    }

    pub fn get(canvas: Ascii, x: i32, y: i32) u8 {
        return canvas.cells[@intCast(y)][@intCast(x)];
    }

    /// Prints the canvas with a row number at the start of each line.
    pub fn print(canvas: Ascii) void {
        for (canvas.cells, 0..) |row, y| std.debug.print("{d:>2} {s}\n", .{ y, &row });
    }

    /// Prints two canvases next to each other, to compare algorithms.
    pub fn printPair(a: Ascii, b: Ascii) void {
        for (a.cells, b.cells, 0..) |left, right, y| {
            std.debug.print("{d:>2} {s}   {s}\n", .{ y, &left, &right });
        }
    }

    pub fn count(canvas: Ascii, char: u8) usize {
        var n: usize = 0;
        for (canvas.cells) |row| n += std.mem.countScalar(u8, &row, char);
        return n;
    }
};

pub fn main() void {
    var canvas: Ascii = .{};
    // A span from x = -3 to 5 on row 1: the part left of x = 0 is clipped.
    var x: i32 = -3;
    while (x <= 5) : (x += 1) canvas.set(x, 1, '#');
    canvas.set(0, 0, 'A'); // top-left corner
    canvas.set(Ascii.width - 1, Ascii.height - 1, 'Z'); // bottom-right corner
    canvas.set(40, 3, '!'); // off the canvas: ignored
    canvas.print();
    std.debug.print("{d} cells set\n", .{canvas.count('#') + canvas.count('A') + canvas.count('Z')});
}
