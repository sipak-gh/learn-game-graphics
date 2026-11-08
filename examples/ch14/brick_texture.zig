//! A 64x64 brick texture made from code, printed as a small text picture
//! and written to brick.ppm tiled 4x4 (256x256) to show that it repeats
//! without a seam.
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

fn isMortar(x: u32, y: u32) bool {
    const row = y / 16; // bricks are 32x16 texels
    const sx = (x + (row % 2) * 16) % size; // every other row shifted by half a brick
    return y % 16 < 2 or sx % 32 < 2;
}

fn brick(x: u32, y: u32) [3]u8 {
    const grain = 0.85 + 0.15 * random(x, y, 7);
    if (isMortar(x, y)) return shade(.{ 0x9a, 0x94, 0x88 }, grain * 0.9);
    const row = y / 16;
    const sx = (x + (row % 2) * 16) % size;
    const tint = 0.75 + 0.3 * random(sx / 32, row, 3); // one tint per brick
    return shade(.{ 0xb0, 0x5a, 0x38 }, @min(1, tint * grain));
}

fn shade(c: [3]u8, f: f32) [3]u8 {
    var out: [3]u8 = undefined;
    for (c, &out) |v, *o| o.* = @intFromFloat(@as(f32, @floatFromInt(v)) * f);
    return out;
}

pub fn main(init: std.process.Init) !void {
    // One character per 2x4 texels: '-' where any mortar is, 'B' for brick.
    var y: u32 = 0;
    while (y < size) : (y += 4) {
        var x: u32 = 0;
        while (x < size) : (x += 2) {
            const m = isMortar(x, y) or isMortar(x + 1, y) or isMortar(x, y + 1);
            std.debug.print("{c}", .{@as(u8, if (m) '-' else 'B')});
        }
        std.debug.print("\n", .{});
    }

    const w = 4 * size;
    var pixels: [w * w][3]u8 = undefined;
    for (0..w) |py| {
        // `% size` repeats the texture: the same wrap the renderer does with `& 63`.
        for (0..w) |px| pixels[py * w + px] = brick(@intCast(px % size), @intCast(py % size));
    }
    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "brick.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print("P6\n{d} {d}\n255\n", .{ w, w });
    try writer.interface.writeAll(std.mem.sliceAsBytes(&pixels));
    try writer.interface.flush();
    std.debug.print("wrote brick.ppm, {d}x{d}\n", .{ w, w });
}
