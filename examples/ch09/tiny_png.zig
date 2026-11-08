//! The smallest useful PNG writer: a 2x2 RGB image, filter type 0 on every
//! row. Writes tiny.png, then reads its IHDR back.
const std = @import("std");
const flate = std.compress.flate;

const width = 2;
const height = 2;
const pixels = [height][width][3]u8{
    .{ .{ 255, 0, 0 }, .{ 0, 255, 0 } }, // red, green
    .{ .{ 0, 0, 255 }, .{ 255, 255, 255 } }, // blue, white
};

fn writeChunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    var crc: std.hash.Crc32 = .init();
    crc.update(kind);
    crc.update(data);
    try w.writeAll(kind);
    try w.writeAll(data);
    try w.writeInt(u32, crc.final(), .big);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // IDAT: every row is a filter byte (0 = none) and then its RGB bytes.
    var idat: std.Io.Writer.Allocating = try .initCapacity(gpa, 256);
    defer idat.deinit();
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    var zlib: flate.Compress = try .init(&idat.writer, window, .zlib, .level_4);
    for (pixels) |row| {
        try zlib.writer.writeByte(0);
        for (row) |rgb| try zlib.writer.writeAll(&rgb);
    }
    try zlib.finish();

    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8..13].* = .{ 8, 2, 0, 0, 0 };

    var png: std.Io.Writer.Allocating = .init(gpa);
    defer png.deinit();
    const w = &png.writer;
    try w.writeAll("\x89PNG\r\n\x1a\n");
    try writeChunk(w, "IHDR", &ihdr);
    try writeChunk(w, "IDAT", idat.written());
    try writeChunk(w, "IEND", "");

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "tiny.png", .data = png.written() });
    std.debug.print("wrote tiny.png: {d} bytes (IDAT {d})\n", .{ png.written().len, idat.written().len });

    // Read the header back from the bytes we wrote.
    const bytes = png.written();
    const w_read = std.mem.readInt(u32, bytes[16..20], .big);
    const h_read = std.mem.readInt(u32, bytes[20..24], .big);
    std.debug.print("{s}: {d} x {d}, {d}-bit, color type {d}\n", .{ bytes[12..16], w_read, h_read, bytes[24], bytes[25] });
}
