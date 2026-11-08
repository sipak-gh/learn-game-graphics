//! The DDA line: step along the longer axis one pixel at a time and add a
//! fractional increment to the other coordinate, rounding to plot.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;

pub fn ddaLine(canvas: *Ascii, x0: i32, y0: i32, x1: i32, y1: i32, char: u8) void {
    const dx: f32 = @floatFromInt(x1 - x0);
    const dy: f32 = @floatFromInt(y1 - y0);
    const steps = @max(@abs(dx), @abs(dy)); // pixels along the longer axis
    if (steps == 0) return canvas.set(x0, y0, char);
    const x_step = dx / steps; // one of the two steps is exactly +1 or -1
    const y_step = dy / steps;
    var x: f32 = @floatFromInt(x0);
    var y: f32 = @floatFromInt(y0);
    for (0..@as(usize, @intFromFloat(steps)) + 1) |_| {
        canvas.set(@intFromFloat(@round(x)), @intFromFloat(@round(y)), char);
        x += x_step;
        y += y_step;
    }
}

pub fn main() void {
    var canvas: Ascii = .{};
    ddaLine(&canvas, 1, 1, 30, 11, '#'); // shallow: x steps by 1, y by 10/29
    ddaLine(&canvas, 3, 12, 8, 0, '*'); // steep and upward: y steps by -1
    canvas.print();
    std.debug.print("shallow line: {d} pixels, steep line: {d} pixels\n", .{ canvas.count('#'), canvas.count('*') });
}
