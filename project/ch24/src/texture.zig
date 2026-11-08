//! Textures: small images that are painted onto walls, floors, and sprites.
//! delve has no image files; every texture is computed from noise and
//! simple shapes when the program starts.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const math = @import("math.zig");
const Vec3 = math.Vec3;

/// Every texture is size x size texels. A power of two, so wrapping a
/// coordinate is a bitwise AND.
pub const size = 64;
const mask = size - 1;

/// The mipmap levels of a texture: 64x64, 32x32, ... down to 1x1.
pub const level_count = std.math.log2_int(u32, size) + 1;

/// How a texture is read where a pixel falls between texels, or covers
/// many of them.
pub const Filter = enum {
    /// The one texel the point falls in.
    nearest,
    /// The four texels around the point, blended by how close each is.
    bilinear,
    /// Bilinear, from the mipmap level whose texels are nearest in size to
    /// the pixel.
    mipmap,
    /// Bilinear from the two levels around the pixel's size, blended:
    /// trilinear filtering.
    trilinear,
};

pub const Texture = struct {
    /// Level 0 is the texture itself; level k is size >> k texels square,
    /// each texel the average of four texels of level k - 1.
    levels: [level_count]Canvas,

    /// The texel at integer coordinates, wrapped so the texture repeats.
    pub fn texel(tex: Texture, x: i32, y: i32) Color {
        const ux: usize = @intCast(x & mask);
        const uy: usize = @intCast(y & mask);
        return tex.levels[0].pixels[uy * size + ux];
    }

    /// Nearest-texel sampling at texture coordinates (u, v); (0, 0) is the
    /// top-left corner and (1, 1) the bottom-right. Outside 0..1 the texture
    /// repeats.
    pub fn sample(tex: Texture, u: f32, v: f32) Color {
        return tex.texel(@intFromFloat(@floor(u * size)), @intFromFloat(@floor(v * size)));
    }

    /// Blends the four texels of mipmap `level` around (u, v). Texel
    /// centers are at half-texel positions, so a point exactly on a center
    /// gets that texel alone.
    pub fn bilinear(tex: Texture, level: usize, u: f32, v: f32) Vec3 {
        const n = levelSize(level);
        const x = u * @as(f32, @floatFromInt(n)) - 0.5;
        const y = v * @as(f32, @floatFromInt(n)) - 0.5;
        const x0 = @floor(x);
        const y0 = @floor(y);
        const fx = x - x0;
        const fy = y - y0;
        const pixels = tex.levels[level].pixels;
        const m: i32 = @intCast(n - 1);
        const ix: i32 = @intFromFloat(x0);
        const iy: i32 = @intFromFloat(y0);
        const left: usize = @intCast(ix & m);
        const right: usize = @intCast((ix + 1) & m);
        const top: usize = @intCast(iy & m);
        const bottom: usize = @intCast((iy + 1) & m);
        const above = math.lerp(rgb(pixels[top * n + left]), rgb(pixels[top * n + right]), fx);
        const below = math.lerp(rgb(pixels[bottom * n + left]), rgb(pixels[bottom * n + right]), fx);
        return math.lerp(above, below, fy);
    }

    /// The color at (u, v), 0 to 255 per channel, read with `filter`.
    /// `footprint` is how far u and v move from one pixel to the next:
    /// the size of the pixel on the texture.
    pub fn filtered(tex: Texture, u: f32, v: f32, footprint: f32, filter: Filter) Vec3 {
        switch (filter) {
            .nearest => return rgb(tex.sample(u, v)),
            .bilinear => return tex.bilinear(0, u, v),
            .mipmap => {
                const lod = std.math.clamp(levelOfDetail(footprint), 0, level_count - 1);
                return tex.bilinear(@intFromFloat(@round(lod)), u, v);
            },
            .trilinear => {
                const lod = std.math.clamp(levelOfDetail(footprint), 0, level_count - 1);
                const level: usize = @intFromFloat(@floor(lod));
                const finer = tex.bilinear(level, u, v);
                if (level == level_count - 1) return finer;
                return math.lerp(finer, tex.bilinear(level + 1, u, v), lod - @floor(lod));
            },
        }
    }
};

/// The width and height of mipmap `level`, in texels.
pub fn levelSize(level: usize) usize {
    return @as(usize, size) >> @intCast(level);
}

/// Which mipmap level has texels the size of a pixel that covers
/// `footprint` of the texture: level k has texels 2^k times wider than
/// level 0's, so it is log2 of the pixel's size in level-0 texels.
/// Below 0 the texture is magnified, and level 0 is the best there is.
pub fn levelOfDetail(footprint: f32) f32 {
    return fastLog2(footprint * size);
}

/// log2(x) for x > 0, read off the bits of the float: x is 2^e times a
/// mantissa m from 1 to 2, so log2(x) = e + log2(m), and log2(m) is
/// close to m - 1 (exact at both ends, at most 0.09 off between). A
/// library log2 costs several times more, and the level of detail does
/// not need to be exact; GPUs approximate it too.
pub fn fastLog2(x: f32) f32 {
    const bits: u32 = @bitCast(x);
    const exponent: f32 = @floatFromInt(@as(i32, @intCast(bits >> 23)) - 127);
    const mantissa: f32 = @bitCast((bits & 0x7fffff) | 0x3f800000); // 1 to 2
    return exponent + mantissa - 1;
}

/// A color per mipmap level, to see which level each pixel reads.
pub fn levelColor(lod: f32) Vec3 {
    const colors = [level_count]Vec3{
        .{ 255, 64, 64 }, .{ 255, 200, 64 }, .{ 64, 220, 64 },   .{ 64, 220, 255 },
        .{ 64, 96, 255 }, .{ 220, 64, 255 }, .{ 255, 255, 255 },
    };
    const l = std.math.clamp(lod, 0, level_count - 1);
    const level: usize = @intFromFloat(@floor(l));
    return math.lerp(colors[level], colors[@min(level + 1, level_count - 1)], l - @floor(l));
}

/// A color as a vector of red, green, and blue, 0 to 255. The four bytes
/// of a color convert to floats in one go, as a vector.
pub fn rgb(c: Color) Vec3 {
    const bytes: @Vector(4, u8) = @as(*const [4]u8, @ptrCast(&c)).*;
    const all: @Vector(4, f32) = @floatFromInt(bytes);
    return .{ all[0], all[1], all[2] };
}

/// Each texel of the smaller level is the average of the 2x2 texels it
/// covers in the larger one (a box filter), rounded to the nearest.
fn halve(big: Canvas, small: Canvas) void {
    for (0..small.height) |y| {
        for (small.row(y), 0..) |*p, x| {
            var sum: @Vector(4, u32) = @splat(0);
            for ([_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |d| {
                const c = big.get(2 * x + d[0], 2 * y + d[1]);
                sum += @Vector(4, u32){ c.r, c.g, c.b, c.a };
            }
            const avg = (sum + @as(@Vector(4, u32), @splat(2))) / @as(@Vector(4, u32), @splat(4));
            p.* = .{ .r = @intCast(avg[0]), .g = @intCast(avg[1]), .b = @intCast(avg[2]), .a = @intCast(avg[3]) };
        }
    }
}

pub const Kind = enum { brick, stone, floor, ceiling, lamp, barrel, staves };

pub const Set = struct {
    textures: std.EnumArray(Kind, Texture),

    pub fn generate(gpa: std.mem.Allocator) !Set {
        var set: Set = .{ .textures = undefined };
        var done: usize = 0;
        errdefer for (set.textures.values[0..done]) |*t| freeLevels(gpa, &t.levels);
        inline for (comptime std.enums.values(Kind)) |kind| {
            var levels: [level_count]Canvas = undefined;
            var made: usize = 0;
            errdefer freeLevels(gpa, levels[0..made]);
            for (&levels, 0..) |*level, k| {
                level.* = try Canvas.init(gpa, levelSize(k), levelSize(k));
                made += 1;
            }
            for (0..size) |y| {
                for (levels[0].row(y), 0..) |*p, x| p.* = paint(kind, @intCast(x), @intCast(y));
            }
            for (1..level_count) |k| halve(levels[k - 1], levels[k]);
            set.textures.set(kind, .{ .levels = levels });
            done += 1;
        }
        return set;
    }

    fn freeLevels(gpa: std.mem.Allocator, levels: []Canvas) void {
        for (levels) |*level| level.deinit(gpa);
    }

    pub fn deinit(set: *Set, gpa: std.mem.Allocator) void {
        for (&set.textures.values) |*t| freeLevels(gpa, &t.levels);
    }

    pub fn get(set: *const Set, kind: Kind) Texture {
        return set.textures.get(kind);
    }

    pub fn ptr(set: *const Set, kind: Kind) *const Texture {
        return set.textures.getPtrConst(kind);
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
        .staves => staves(x, y),
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

/// The side of a barrel, unrolled: eight staves running down, held by two
/// iron bands. The barrel model wraps it once around.
fn staves(x: u32, y: u32) Color {
    if ((y >= 9 and y < 14) or (y >= 50 and y < 55)) {
        return Color.hex(0x5c5c64).scale(0.8 + 0.2 * random(x / 4, y, 19));
    }
    if (x % 8 == 0) return Color.hex(0x2a1a0e);
    const tint = 0.8 + 0.2 * random(x / 8, 0, 17);
    const grain = 0.85 + 0.15 * noise(x, y, 4, x / 8 + 50);
    return Color.hex(0x8a5a2c).scale(tint * grain);
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

test "each mipmap level is the average of the one above" {
    const gpa = std.testing.allocator;
    var set: Set = try .generate(gpa);
    defer set.deinit(gpa);
    const tex = set.get(.brick);
    try std.testing.expectEqual(1, tex.levels[level_count - 1].width);
    // The last level is a single texel: the average color of the texture,
    // give or take the rounding at each level.
    var sum: Vec3 = @splat(0);
    for (tex.levels[0].pixels) |p| sum += rgb(p);
    const average = math.scale(sum, 1.0 / @as(f32, size * size));
    const last = rgb(tex.levels[level_count - 1].pixels[0]);
    inline for (0..3) |i| try std.testing.expectApproxEqAbs(average[i], last[i], 3);
}

test "bilinear filtering blends the texels around the point" {
    const gpa = std.testing.allocator;
    var set: Set = try .generate(gpa);
    defer set.deinit(gpa);
    const tex = set.get(.stone);
    // On a texel center: that texel alone.
    try std.testing.expect(math.approxEq(rgb(tex.texel(5, 9)), tex.bilinear(0, 5.5 / @as(f32, size), 9.5 / @as(f32, size))));
    // Halfway between two centers: their average, also across the
    // texture's edge, where it wraps.
    const between = math.scale(rgb(tex.texel(size - 1, 0)) + rgb(tex.texel(0, 0)), 0.5);
    try std.testing.expect(math.approxEq(between, tex.bilinear(0, 0, 0.5 / @as(f32, size))));
}

test "the fast log2 is exact at powers of two and close between" {
    for ([_]f32{ 0.125, 1, 2, 64, 1024 }) |x| try std.testing.expectEqual(@log2(x), fastLog2(x));
    var x: f32 = 0.01;
    while (x < 100) : (x *= 1.07) try std.testing.expectApproxEqAbs(@log2(x), fastLog2(x), 0.09);
}

test "the level of detail is log2 of the pixel size in texels" {
    try std.testing.expectEqual(0, levelOfDetail(1.0 / @as(f32, size)));
    try std.testing.expectEqual(3, levelOfDetail(8.0 / @as(f32, size)));
    try std.testing.expectEqual(-1, levelOfDetail(0.5 / @as(f32, size)));
}
