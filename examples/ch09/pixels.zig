//! A framebuffer is one flat array: pixel (x, y) is element y * width + x.
const std = @import("std");

const width = 4;
const height = 3;

pub fn main(init: std.process.Init) !void {
    // Three bytes per pixel (red, green, blue), all zero: black.
    const pixels = try init.gpa.alloc(u8, width * height * 3);
    defer init.gpa.free(pixels);
    @memset(pixels, 0);

    setPixel(pixels, 0, 0, .{ 0xff, 0x00, 0x00 }); // top-left: red
    setPixel(pixels, 3, 0, .{ 0x00, 0xff, 0x00 }); // top-right: green
    setPixel(pixels, 1, 2, .{ 0x00, 0x00, 0xff }); // bottom row, second pixel: blue

    for (0..height) |y| {
        std.debug.print("row {d}:", .{y});
        for (0..width) |x| {
            const i = (y * width + x) * 3;
            std.debug.print(" {x:0>2}{x:0>2}{x:0>2}", .{ pixels[i], pixels[i + 1], pixels[i + 2] });
        }
        std.debug.print("\n", .{});
    }
    std.debug.print("pixel (1, 2) starts at byte {d} of {d}\n", .{ (2 * width + 1) * 3, pixels.len });
}

fn setPixel(pixels: []u8, x: usize, y: usize, rgb: [3]u8) void {
    const i = (y * width + x) * 3;
    pixels[i..][0..3].* = rgb;
}
