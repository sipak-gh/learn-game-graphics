//! The XOR pattern: the brightness of pixel (x, y) is x ^ y. Writes xor.ppm.
const std = @import("std");

const size = 256;

pub fn main(init: std.process.Init) !void {
    std.debug.print("x ^ y for the top-left 8x8 pixels:\n", .{});
    for (0..8) |y| {
        for (0..8) |x| std.debug.print("{d:>3}", .{x ^ y});
        std.debug.print("\n", .{});
    }

    const io = init.io;
    const file = try std.Io.Dir.cwd().createFile(io, "xor.ppm", .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;
    try w.print("P6\n{d} {d}\n255\n", .{ size, size });
    for (0..size) |y| {
        for (0..size) |x| {
            const v: u8 = @intCast(x ^ y); // both < 256, so the XOR is too
            try w.writeAll(&.{ v, v, v }); // equal red, green, blue: gray
        }
    }
    try w.flush();
    std.debug.print("wrote xor.ppm\n", .{});
}
