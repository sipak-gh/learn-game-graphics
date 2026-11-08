const std = @import("std");

/// One pixel. The field order matches the bytes of raylib's
/// PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, so a `[]Color` can be uploaded to a
/// texture as it is. `extern` guarantees that order in memory.
pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };

    /// A color from a 0xRRGGBB literal, like in CSS: `Color.hex(0xff8000)`.
    pub fn hex(rgb: u24) Color {
        return .{ .r = @truncate(rgb >> 16), .g = @truncate(rgb >> 8), .b = @truncate(rgb) };
    }

    /// The color with red, green, and blue multiplied by `f` (0 to 1).
    pub fn scale(c: Color, f: f32) Color {
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(c.r)) * f),
            .g = @intFromFloat(@as(f32, @floatFromInt(c.g)) * f),
            .b = @intFromFloat(@as(f32, @floatFromInt(c.b)) * f),
            .a = c.a,
        };
    }
};

/// A software framebuffer: `width * height` pixels, stored row by row
/// from the top-left corner. Everything delve draws ends up here.
pub const Canvas = struct {
    width: usize,
    height: usize,
    pixels: []Color,

    pub fn init(gpa: std.mem.Allocator, width: usize, height: usize) !Canvas {
        const pixels = try gpa.alloc(Color, width * height);
        @memset(pixels, Color.black);
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    pub fn deinit(canvas: *Canvas, gpa: std.mem.Allocator) void {
        gpa.free(canvas.pixels);
        canvas.* = undefined;
    }

    pub fn clear(canvas: Canvas, color: Color) void {
        @memset(canvas.pixels, color);
    }

    /// The pixels of row `y`, left to right.
    pub fn row(canvas: Canvas, y: usize) []Color {
        return canvas.pixels[y * canvas.width ..][0..canvas.width];
    }

    /// Sets one pixel. Coordinates outside the canvas are ignored, so
    /// callers can draw shapes that are partly off-screen.
    pub fn set(canvas: Canvas, x: i32, y: i32, color: Color) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= canvas.width or uy >= canvas.height) return;
        canvas.pixels[uy * canvas.width + ux] = color;
    }

    pub fn get(canvas: Canvas, x: usize, y: usize) Color {
        return canvas.pixels[y * canvas.width + x];
    }

    /// Copies all of `src` onto this canvas with its top-left corner at
    /// (x, y), clipped to the edges.
    pub fn blit(canvas: Canvas, src: Canvas, x: i32, y: i32) void {
        for (0..src.height) |sy| {
            const dy = y + @as(i32, @intCast(sy));
            if (dy < 0 or dy >= canvas.height) continue;
            for (src.row(sy), 0..) |color, sx| canvas.set(x + @as(i32, @intCast(sx)), dy, color);
        }
    }
};

test "Color has the memory layout of an RGBA texture" {
    try std.testing.expectEqual(4, @sizeOf(Color));
    const c = Color.hex(0x112233);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 0xff }, std.mem.asBytes(&c));
}

test "scale darkens a color" {
    const c = Color.hex(0x80ff10).scale(0.5);
    try std.testing.expectEqual(Color.hex(0x407f08), c);
}

test "set ignores pixels outside the canvas" {
    var canvas = try Canvas.init(std.testing.allocator, 4, 3);
    defer canvas.deinit(std.testing.allocator);
    canvas.set(-1, 0, Color.white);
    canvas.set(4, 0, Color.white);
    canvas.set(0, 3, Color.white);
    canvas.set(3, 2, Color.white);
    try std.testing.expectEqual(Color.white, canvas.get(3, 2));
    try std.testing.expectEqual(Color.white, canvas.row(2)[3]);
    var lit: usize = 0;
    for (canvas.pixels) |p| lit += @intFromBool(p.r == 255);
    try std.testing.expectEqual(1, lit);
}
