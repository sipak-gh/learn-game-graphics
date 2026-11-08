//! A wireframe cube in about 70 lines: turn the 8 corners, push them in
//! front of the eye, divide by the distance, and draw the 12 edges with
//! Bresenham's line into cube.ppm.
const std = @import("std");

const w = 320;
const h = 200;
var pixels: [w * h][3]u8 = @splat(.{ 16, 16, 24 });

fn plot(x: i32, y: i32) void {
    if (x < 0 or y < 0 or x >= w or y >= h) return;
    pixels[@as(usize, @intCast(y)) * w + @as(usize, @intCast(x))] = .{ 240, 240, 240 };
}

fn line(x0: i32, y0: i32, x1: i32, y1: i32) void {
    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;
    var x = x0;
    var y = y0;
    while (true) {
        plot(x, y);
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const f: f32 = 2; // 1/tan(vfov/2), vfov = 53.13 degrees
    const aspect: f32 = @as(f32, w) / h;
    const ay: f32 = 0.6; // turn about y
    const ax: f32 = 0.4; // then tilt about x
    var screen: [8][2]i32 = undefined;
    for (0..8) |i| {
        // Corner i of the cube from -0.5 to 0.5: bit 0 is x, bit 1 y, bit 2 z.
        var x: f32 = if (i & 1 != 0) 0.5 else -0.5;
        var y: f32 = if (i & 2 != 0) 0.5 else -0.5;
        var z: f32 = if (i & 4 != 0) 0.5 else -0.5;
        const x1 = x * @cos(ay) + z * @sin(ay);
        z = -x * @sin(ay) + z * @cos(ay);
        x = x1;
        const y1 = y * @cos(ax) - z * @sin(ax);
        z = y * @sin(ax) + z * @cos(ax);
        y = y1;
        const d = 2.2 - z; // the cube's center is 2.2 in front of the eye
        const ndc_x = f / aspect * x / d;
        const ndc_y = f * y / d;
        screen[i] = .{ @intFromFloat(@floor((ndc_x + 1) / 2 * w)), @intFromFloat(@floor((1 - ndc_y) / 2 * h)) };
        std.debug.print("corner {d}: d = {d:.3}  pixel ({d}, {d})\n", .{ i, d, screen[i][0], screen[i][1] });
    }
    // Two corners share an edge when they differ in exactly one bit.
    var edges: usize = 0;
    for (0..8) |i| for (0..8) |j| {
        if (i < j and @popCount(i ^ j) == 1) {
            line(screen[i][0], screen[i][1], screen[j][0], screen[j][1]);
            edges += 1;
        }
    };
    const file = try std.Io.Dir.cwd().createFile(init.io, "cube.ppm", .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var out = file.writer(init.io, &buffer);
    try out.interface.print("P6\n{d} {d}\n255\n", .{ w, h });
    try out.interface.writeAll(std.mem.sliceAsBytes(&pixels));
    try out.interface.flush();
    std.debug.print("{d} edges -> cube.ppm\n", .{edges});
}
