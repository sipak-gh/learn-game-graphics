//! Two rectangles that pierce each other: A is flat, B slants from near
//! (left) to far (right). Without a depth buffer the one drawn last wins
//! everywhere; with one, each pixel keeps whichever is nearer there.
const std = @import("std");

const width = 30;
const height = 9;

const Rect = struct {
    name: u8,
    x0: usize,
    x1: usize,
    y0: usize,
    y1: usize,
    /// Depth at the left and right side: 0 is at the eye, 1 far away.
    z_left: f32,
    z_right: f32,

    fn depthAt(r: Rect, x: usize) f32 {
        const t = @as(f32, @floatFromInt(x - r.x0)) / @as(f32, @floatFromInt(r.x1 - r.x0));
        return std.math.lerp(r.z_left, r.z_right, t);
    }
};

fn render(order: []const Rect, depth_test: bool) void {
    var color: [height][width]u8 = @splat(@splat('.'));
    var depth: [height][width]f32 = @splat(@splat(1));
    var written: usize = 0;
    for (order) |r| {
        for (r.y0..r.y1 + 1) |y| for (r.x0..r.x1 + 1) |x| {
            const z = r.depthAt(x);
            if (depth_test and z >= depth[y][x]) continue;
            depth[y][x] = z;
            color[y][x] = r.name;
            written += 1;
        };
    }
    std.debug.print("{c} then {c}, depth test {s}: {d} pixels written\n", .{
        order[0].name, order[1].name, if (depth_test) "on" else "off", written,
    });
    for (color) |line| std.debug.print("  {s}\n", .{&line});
}

pub fn main() void {
    const a: Rect = .{ .name = 'A', .x0 = 2, .x1 = 20, .y0 = 0, .y1 = 5, .z_left = 0.5, .z_right = 0.5 };
    const b: Rect = .{ .name = 'B', .x0 = 8, .x1 = 28, .y0 = 3, .y1 = 8, .z_left = 0.2, .z_right = 0.8 };
    render(&.{ a, b }, false);
    render(&.{ b, a }, false);
    render(&.{ a, b }, true);
    render(&.{ b, a }, true);
}
