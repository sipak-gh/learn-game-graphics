//! Writes gradient.ppm: 256x256 pixels, red grows to the right and green
//! grows downward. PPM is a tiny text header followed by raw RGB bytes.
const std = @import("std");

const size = 256;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "gradient.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;

    try w.print("P6\n{d} {d}\n255\n", .{ size, size });
    for (0..size) |y| {
        for (0..size) |x| {
            // x and y run 0..255, exactly the range of one byte.
            try w.writeAll(&.{ @intCast(x), @intCast(y), 0 });
        }
    }
    try w.flush();

    const stat = try file.stat(io);
    std.debug.print("wrote gradient.ppm: {d} bytes = {d} header + {d} x {d} x 3\n", .{
        stat.size, stat.size - size * size * 3, size, size,
    });
}
