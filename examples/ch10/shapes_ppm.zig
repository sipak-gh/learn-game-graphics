//! Lines, a circle, and a filled triangle on a small RGB canvas, saved as
//! shapes.ppm. Stand-alone: everything it needs is in this file.
const std = @import("std");

const width = 160;
const height = 100;
const Rgb = [3]u8;
const Point = struct { x: i32, y: i32 };

var pixels: [height][width]Rgb = @splat(@splat(.{ 24, 24, 40 }));

fn set(x: i32, y: i32, color: Rgb) void {
    if (x < 0 or y < 0 or x >= width or y >= height) return;
    pixels[@intCast(y)][@intCast(x)] = color;
}

fn line(a: Point, b: Point, color: Rgb) void {
    const dx: i32 = @intCast(@abs(b.x - a.x));
    const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
    const sx: i32 = if (a.x < b.x) 1 else -1;
    const sy: i32 = if (a.y < b.y) 1 else -1;
    var err = dx + dy;
    var p = a;
    while (true) {
        set(p.x, p.y, color);
        if (p.x == b.x and p.y == b.y) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            p.x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            p.y += sy;
        }
    }
}

fn circle(c: Point, r: i32, color: Rgb) void {
    var x = r;
    var y: i32 = 0;
    var err = 1 - r;
    while (x >= y) : (y += 1) {
        for ([_][2]i32{ .{ x, y }, .{ y, x }, .{ -y, x }, .{ -x, y }, .{ -x, -y }, .{ -y, -x }, .{ y, -x }, .{ x, -y } }) |d| {
            set(c.x + d[0], c.y + d[1], color);
        }
        if (err < 0) {
            err += 2 * y + 3;
        } else {
            err += 2 * (y - x) + 5;
            x -= 1;
        }
    }
}

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

fn fillTriangle(a: Point, b_in: Point, c_in: Point, color: Rgb) void {
    var b = b_in;
    var c = c_in;
    if (edge(a, b, c) < 0) std.mem.swap(Point, &b, &c);
    var y = @max(@min(a.y, b.y, c.y), 0);
    while (y <= @min(@max(a.y, b.y, c.y), height - 1)) : (y += 1) {
        var x = @max(@min(a.x, b.x, c.x), 0);
        while (x <= @min(@max(a.x, b.x, c.x), width - 1)) : (x += 1) {
            const p: Point = .{ .x = x, .y = y };
            if (edge(b, c, p) >= 0 and edge(c, a, p) >= 0 and edge(a, b, p) >= 0) set(x, y, color);
        }
    }
}

pub fn main(init: std.process.Init) !void {
    fillTriangle(.{ .x = 100, .y = 10 }, .{ .x = 150, .y = 90 }, .{ .x = 70, .y = 80 }, .{ 160, 80, 224 });
    circle(.{ .x = 40, .y = 50 }, 30, .{ 96, 224, 96 });
    var i: i32 = 0;
    while (i <= 8) : (i += 1) line(.{ .x = 40, .y = 50 }, .{ .x = 10 + i * 15, .y = 95 }, .{ 240, 192, 64 });

    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "shapes.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;
    try w.print("P6\n{d} {d}\n255\n", .{ width, height });
    try w.writeAll(std.mem.sliceAsBytes(&pixels));
    try w.flush();
    std.debug.print("wrote shapes.ppm ({d} x {d})\n", .{ width, height });
}
