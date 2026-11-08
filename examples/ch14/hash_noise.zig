//! A hash turns lattice coordinates into repeatable random numbers; value
//! noise blends those numbers smoothly. Prints a grid of noise values and
//! writes noise.ppm: noise with cells of 16, 8, and 4 texels, then the
//! three added together (a 64x64 panel each).
const std = @import("std");

const size = 64;

fn hash(x: u32, y: u32, seed: u32) u32 {
    var h = x *% 0x8da6b343 +% y *% 0xd8163841 +% seed *% 0xcb1ab31f;
    h ^= h >> 15;
    h *%= 0x2c1b3c6d;
    h ^= h >> 12;
    h *%= 0x297a2d39;
    h ^= h >> 15;
    return h;
}

fn random(x: u32, y: u32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) & 0xffff)) / 65535.0;
}

fn smooth(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

fn noise(x: u32, y: u32, cell: u32, seed: u32) f32 {
    const cells = size / cell; // lattice points per row; wrapping makes it tile
    const x0 = x / cell;
    const y0 = y / cell;
    const fx = smooth(@as(f32, @floatFromInt(x % cell)) / @as(f32, @floatFromInt(cell)));
    const fy = smooth(@as(f32, @floatFromInt(y % cell)) / @as(f32, @floatFromInt(cell)));
    const a = random(x0 % cells, y0 % cells, seed);
    const b = random((x0 + 1) % cells, y0 % cells, seed);
    const c = random(x0 % cells, (y0 + 1) % cells, seed);
    const d = random((x0 + 1) % cells, (y0 + 1) % cells, seed);
    return std.math.lerp(std.math.lerp(a, b, fx), std.math.lerp(c, d, fx), fy);
}

fn fractal(x: u32, y: u32, seed: u32) f32 {
    return 0.5 * noise(x, y, 16, seed) + 0.3 * noise(x, y, 8, seed + 1) + 0.2 * noise(x, y, 4, seed + 2);
}

pub fn main(init: std.process.Init) !void {
    for ([_][3]u32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 } }) |a| {
        std.debug.print("hash({d}, {d}, {d}) = 0x{x:0>8}\n", .{ a[0], a[1], a[2], hash(a[0], a[1], a[2]) });
    }
    std.debug.print("\n", .{});
    std.debug.print("noise(x, y, cell 16) every 4 texels:\n", .{});
    for (0..8) |y| {
        for (0..8) |x| std.debug.print(" {d:.2}", .{noise(@intCast(x * 4), @intCast(y * 4), 16, 1)});
        std.debug.print("\n", .{});
    }

    const w = 4 * size;
    var pixels: [w * size][3]u8 = undefined;
    for (0..size) |y| {
        for (0..w) |px| {
            const x: u32 = @intCast(px % size);
            const yy: u32 = @intCast(y);
            const v = switch (px / size) {
                0 => noise(x, yy, 16, 1),
                1 => noise(x, yy, 8, 2),
                2 => noise(x, yy, 4, 3),
                else => fractal(x, yy, 1),
            };
            pixels[y * w + px] = @splat(@intFromFloat(v * 255));
        }
    }
    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "noise.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print("P6\n{d} {d}\n255\n", .{ w, size });
    try writer.interface.writeAll(std.mem.sliceAsBytes(&pixels));
    try writer.interface.flush();
    std.debug.print("\nwrote noise.ppm, {d}x{d}\n", .{ w, size });
}
