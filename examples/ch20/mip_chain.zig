//! A mip chain: a 64x64 brick texture, then 32x32, 16x16, ... 1x1, each
//! texel the rounded average of the 2x2 texels above it. Writes all levels
//! side by side into mips.ppm and prints each level's size and mean color.
const std = @import("std");

const size = 64;
const level_count = std.math.log2_int(u32, size) + 1;

const Color = @Vector(4, u8);

/// A well-mixed hash, so the "random" tint of each brick is the same on
/// every run.
fn hash(x: u32, y: u32) u32 {
    var h = x *% 0x8da6b343 +% y *% 0xd8163841;
    h ^= h >> 15;
    h *%= 0x2c1b3c6d;
    h ^= h >> 12;
    return h;
}

/// Bricks 32x16 texels in gray mortar, every other row shifted by half a
/// brick (a simpler cousin of delve's brick texture).
fn brick(x: u32, y: u32) Color {
    const row = y / 16;
    const sx = (x + (row % 2) * 16) % size;
    if (y % 16 < 2 or sx % 32 < 2) return .{ 154, 148, 136, 255 };
    const tint: u32 = 80 + hash(sx / 32, row) % 40; // percent
    const grain: u32 = 90 + hash(x, y) % 10;
    const scale = tint * grain;
    return .{ @intCast(176 * scale / 10000), @intCast(90 * scale / 10000), @intCast(56 * scale / 10000), 255 };
}

fn levelSize(level: usize) usize {
    return @as(usize, size) >> @intCast(level);
}

/// Each texel of `small` is the 2x2 box average of `big`, rounded: add 2
/// before dividing by 4. All four channels at once, as a vector.
fn halve(big: []const Color, small: []Color, n: usize) void {
    for (0..n) |y| {
        for (0..n) |x| {
            var sum: @Vector(4, u32) = @splat(0);
            for ([_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |d| {
                sum += big[(2 * y + d[1]) * 2 * n + 2 * x + d[0]];
            }
            small[y * n + x] = @intCast((sum + @as(@Vector(4, u32), @splat(2))) / @as(@Vector(4, u32), @splat(4)));
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var levels: [level_count][]Color = undefined;
    var made: usize = 0;
    defer for (levels[0..made]) |level| gpa.free(level);
    for (&levels, 0..) |*level, k| {
        const n = levelSize(k);
        level.* = try gpa.alloc(Color, n * n);
        made += 1;
    }
    for (0..size) |y| {
        for (0..size) |x| levels[0][y * size + x] = brick(@intCast(x), @intCast(y));
    }
    for (1..level_count) |k| halve(levels[k - 1], levels[k], levelSize(k));

    var texels: usize = 0;
    for (levels, 0..) |level, k| {
        const n = levelSize(k);
        var sum: @Vector(4, u32) = @splat(0);
        for (level) |c| sum += c;
        const mean = @as(@Vector(4, f32), @floatFromInt(sum)) / @as(@Vector(4, f32), @splat(@floatFromInt(n * n)));
        std.debug.print("level {d}: {d:>2}x{d:<2} {d:>5} texels, mean color {d:>6.2} {d:>6.2} {d:>6.2}\n", .{
            k, n, n, n * n, mean[0], mean[1], mean[2],
        });
        texels += n * n;
    }
    std.debug.print("all levels: {d} texels, {d:.4} times the texture alone\n", .{
        texels, @as(f32, @floatFromInt(texels)) / (size * size),
    });

    // All levels next to each other, top-aligned, on black.
    var width: usize = 0;
    for (0..level_count) |k| width += levelSize(k) + 2;
    var buffer: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "mips.ppm", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.print("P6\n{d} {d}\n255\n", .{ width, size });
    for (0..size) |y| {
        for (levels, 0..) |level, k| {
            const n = levelSize(k);
            for (0..n + 2) |x| {
                const c: Color = if (x < n and y < n) level[y * n + x] else .{ 0, 0, 0, 255 };
                try out.writeAll(&[3]u8{ c[0], c[1], c[2] });
            }
        }
    }
    try out.flush();
    std.debug.print("wrote mips.ppm ({d}x{d})\n", .{ width, size });
}
