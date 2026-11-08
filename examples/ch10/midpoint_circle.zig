//! The midpoint circle algorithm: walk one eighth of the circle with an
//! integer decision variable and mirror each point into all eight octants.
const std = @import("std");
const Ascii = @import("ascii_canvas.zig").Ascii;

fn circle(canvas: *Ascii, cx: i32, cy: i32, radius: i32, char: u8) void {
    var x = radius;
    var y: i32 = 0;
    var err = 1 - radius; // f at the first midpoint, (r - 1/2, 1), times 1, rounded
    while (x >= y) : (y += 1) {
        std.debug.print("x={d} y={d} err={d}\n", .{ x, y, err });
        const points = [8][2]i32{
            .{ x, y }, .{ y, x }, .{ -y, x }, .{ -x, y }, .{ -x, -y }, .{ -y, -x }, .{ y, -x }, .{ x, -y },
        };
        for (points) |d| canvas.set(cx + d[0], cy + d[1], char);
        if (err < 0) {
            err += 2 * y + 3; // the midpoint was inside: keep x
        } else {
            err += 2 * (y - x) + 5; // outside: step x inward too
            x -= 1;
        }
    }
}

pub fn main() void {
    var canvas: Ascii = .{};
    circle(&canvas, 15, 6, 6, '#');
    canvas.set(15, 6, '+'); // the center
    canvas.print();
    std.debug.print("{d} pixels\n", .{canvas.count('#')});
}
