//! Textures: small images that are painted onto walls, floors, and sprites.
//! delve has no image files; every texture is computed from noise and
//! simple shapes when the program starts.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;

/// Every texture is size x size texels. A power of two, so wrapping a
/// coordinate is a bitwise AND.
pub const size = 64;
const mask = size - 1;

pub const Texture = struct {
    canvas: Canvas,

    /// The texel at integer coordinates, wrapped so the texture repeats.
    pub fn texel(tex: Texture, x: i32, y: i32) Color {
        const ux: usize = @intCast(x & mask);
        const uy: usize = @intCast(y & mask);
        return tex.canvas.pixels[uy * size + ux];
    }

    /// Nearest-texel sampling at texture coordinates (u, v); (0, 0) is the
    /// top-left corner and (1, 1) the bottom-right. Outside 0..1 the texture
    /// repeats.
    pub fn sample(tex: Texture, u: f32, v: f32) Color {
        return tex.texel(@intFromFloat(@floor(u * size)), @intFromFloat(@floor(v * size)));
    }
};

pub const Kind = enum { brick, stone, floor, ceiling, lamp, barrel };

pub const Set = struct {
    textures: std.EnumArray(Kind, Texture),

    pub fn generate(gpa: std.mem.Allocator) !Set {
        var set: Set = .{ .textures = undefined };
        var done: usize = 0;
        errdefer for (set.textures.values[0..done]) |*t| t.canvas.deinit(gpa);
        inline for (comptime std.enums.values(Kind)) |kind| {
            var canvas = try Canvas.init(gpa, size, size);
            for (0..size) |y| {
                for (canvas.row(y), 0..) |*p, x| p.* = paint(kind, @intCast(x), @intCast(y));
            }
            set.textures.set(kind, .{ .canvas = canvas });
            done += 1;
        }
        return set;
    }

    pub fn deinit(set: *Set, gpa: std.mem.Allocator) void {
        for (&set.textures.values) |*t| t.canvas.deinit(gpa);
    }

    pub fn get(set: *const Set, kind: Kind) Texture {
        return set.textures.get(kind);
    }
};

fn paint(comptime kind: Kind, x: u32, y: u32) Color {
    return switch (kind) {
        .brick => brick(x, y),
        .stone => stone(x, y),
        .floor => flagstone(x, y),
        .ceiling => planks(x, y),
        .lamp => lamp(x, y),
        .barrel => barrel(x, y),
    };
}

/// A well-mixed 32-bit hash of a lattice point: the same inputs always
/// give the same "random" number, so textures are identical on every run.
fn hash(x: u32, y: u32, seed: u32) u32 {
    var h = x *% 0x8da6b343 +% y *% 0xd8163841 +% seed *% 0xcb1ab31f;
    h ^= h >> 15;
    h *%= 0x2c1b3c6d;
    h ^= h >> 12;
    h *%= 0x297a2d39;
    h ^= h >> 15;
    return h;
}

/// A random number from 0 to 1 for a lattice point.
fn random(x: u32, y: u32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) & 0xffff)) / 65535.0;
}

/// Value noise: random values at the corners of a grid of `cell`-texel
/// squares, blended smoothly in between. It wraps around at the texture
/// edge, so the texture tiles without a seam.
fn noise(x: u32, y: u32, cell: u32, seed: u32) f32 {
    const cells = size / cell;
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

fn smooth(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

/// Several octaves of noise added together: coarse shapes plus fine grain.
fn fractal(x: u32, y: u32, seed: u32) f32 {
    return 0.5 * noise(x, y, 16, seed) + 0.3 * noise(x, y, 8, seed + 1) + 0.2 * noise(x, y, 4, seed + 2);
}

/// Bricks 32x16 texels, every other row shifted by half a brick, in mortar.
fn brick(x: u32, y: u32) Color {
    const row = y / 16;
    // Wrapped, so the brick across the right edge is one brick with the
    // one at the left edge: same tint, no seam when the texture repeats.
    const sx = (x + (row % 2) * 16) % size;
    const grain = 0.85 + 0.15 * random(x, y, 7);
    if (y % 16 < 2 or sx % 32 < 2) return Color.hex(0x9a9488).scale(grain * 0.9);
    const tint = 0.75 + 0.3 * random(sx / 32, row, 3); // each brick a bit different
    return Color.hex(0xb05a38).scale(@min(1, tint * grain * (0.8 + 0.3 * fractal(x, y, 11))));
}

/// Large stone blocks with dark seams.
fn stone(x: u32, y: u32) Color {
    const row = y / 32;
    const sx = (x + (row % 2) * 16) % size;
    if (y % 32 < 2 or sx % 32 < 2) return Color.hex(0x30303a);
    const tint = 0.8 + 0.2 * random(sx / 32, row, 5);
    return Color.hex(0x9c9ca8).scale(tint * (0.6 + 0.45 * fractal(x, y, 21)));
}

/// Square floor tiles.
fn flagstone(x: u32, y: u32) Color {
    if (x % 32 == 0 or y % 32 == 0) return Color.hex(0x282420);
    const tint = 0.85 + 0.15 * random(x / 32, y / 32, 9);
    return Color.hex(0x847868).scale(tint * (0.65 + 0.35 * fractal(x, y, 31)));
}

/// Wooden planks running along x, with grain.
fn planks(x: u32, y: u32) Color {
    if (y % 16 == 0) return Color.hex(0x1c140c);
    const plank = y / 16;
    const wave = @sin(@as(f32, @floatFromInt(y)) * 0.9 + 6 * noise(x, y, 16, plank + 40));
    const tint = 0.8 + 0.2 * random(plank, 0, 13);
    return Color.hex(0x6a4a30).scale(tint * (0.75 + 0.15 * wave + 0.1 * random(x, y, 2)));
}

const clear: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

/// A standing lamp: a glowing globe on a pole. Transparent elsewhere.
fn lamp(x: u32, y: u32) Color {
    const fx: f32 = @as(f32, @floatFromInt(x)) + 0.5;
    const fy: f32 = @as(f32, @floatFromInt(y)) + 0.5;
    const dx = fx - 32;
    const dy = fy - 14;
    const r = @sqrt(dx * dx + dy * dy);
    if (r < 8) return Color.hex(0xfff0b0).scale(1 - r / 30);
    if (r < 9.5) return Color.hex(0x404040);
    if (y >= 22 and x >= 30 and x < 34) return Color.hex(0x505058);
    if (y >= 60 and x >= 24 and x < 40) return Color.hex(0x404048);
    return clear;
}

/// A wooden barrel, shaded like a cylinder, with two iron bands.
fn barrel(x: u32, y: u32) Color {
    if (y < 30) return clear;
    const fy: f32 = @floatFromInt(y - 30);
    const bulge = 13 + 2 * @sin(fy / 34 * std.math.pi); // half-width
    const dx = @as(f32, @floatFromInt(x)) + 0.5 - 32;
    if (@abs(dx) > bulge) return clear;
    const light = 0.45 + 0.55 * @sqrt(1 - (dx / bulge) * (dx / bulge)); // round shading
    if ((y >= 36 and y < 39) or (y >= 56 and y < 59)) return Color.hex(0x707078).scale(light);
    const stave = 0.85 + 0.15 * random(@intFromFloat(@floor((dx + bulge) / 5)), 0, 17);
    return Color.hex(0x8a5a2c).scale(light * stave);
}

test "textures wrap" {
    const gpa = std.testing.allocator;
    var set: Set = try .generate(gpa);
    defer set.deinit(gpa);
    const brick_tex = set.get(.brick);
    try std.testing.expectEqual(brick_tex.texel(3, 5), brick_tex.texel(3 + size, 5 - size));
    try std.testing.expectEqual(brick_tex.texel(0, 0), brick_tex.sample(1.0, 2.0));
    // Sprites have transparent texels; walls do not.
    try std.testing.expectEqual(0, set.get(.lamp).texel(0, 0).a);
    try std.testing.expectEqual(255, set.get(.stone).texel(0, 0).a);
}
