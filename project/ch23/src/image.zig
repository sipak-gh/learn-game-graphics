const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;

/// Writes `canvas` as a binary PPM ("P6"): a text header, then three bytes
/// (red, green, blue) per pixel. The simplest image format there is.
pub fn writePpm(w: *std.Io.Writer, canvas: Canvas) !void {
    try w.print("P6\n{d} {d}\n255\n", .{ canvas.width, canvas.height });
    for (canvas.pixels) |p| try w.writeAll(&.{ p.r, p.g, p.b });
}

const png_signature = "\x89PNG\r\n\x1a\n";

/// Writes `canvas` as an 8-bit RGB PNG. A PNG is a signature followed by
/// chunks; we need three: IHDR (size and format), IDAT (the pixels,
/// zlib-compressed), and IEND.
pub fn writePng(gpa: std.mem.Allocator, w: *std.Io.Writer, canvas: Canvas) !void {
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(canvas.width), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(canvas.height), .big);
    ihdr[8..13].* = .{
        8, // bits per channel
        2, // color type 2: RGB
        0, // compression method: zlib
        0, // filter method: adaptive (we always use filter type 0, "none")
        0, // no interlacing
    };

    // Each row is one filter-type byte followed by the row's RGB bytes.
    var idat: std.Io.Writer.Allocating = try .initCapacity(gpa, 64 * 1024);
    defer idat.deinit();
    const window = try gpa.alloc(u8, std.compress.flate.max_window_len);
    defer gpa.free(window);
    var zlib: std.compress.flate.Compress = try .init(&idat.writer, window, .zlib, .level_4);
    for (0..canvas.height) |y| {
        try zlib.writer.writeByte(0);
        for (canvas.row(y)) |p| try zlib.writer.writeAll(&.{ p.r, p.g, p.b });
    }
    try zlib.finish();

    try w.writeAll(png_signature);
    try writeChunk(w, "IHDR", &ihdr);
    try writeChunk(w, "IDAT", idat.written());
    try writeChunk(w, "IEND", "");
}

/// A chunk is: length (big-endian u32), 4-byte type, data, and a CRC-32 of
/// the type and data.
fn writeChunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    var crc: std.hash.Crc32 = .init();
    crc.update(kind);
    crc.update(data);
    try w.writeAll(kind);
    try w.writeAll(data);
    try w.writeInt(u32, crc.final(), .big);
}

/// Saves `canvas` to `path`. The extension picks the format: `.ppm` or `.png`.
pub fn save(gpa: std.mem.Allocator, io: std.Io, path: []const u8, canvas: Canvas) !void {
    const Format = enum { ppm, png };
    const format: Format = if (std.mem.endsWith(u8, path, ".ppm"))
        .ppm
    else if (std.mem.endsWith(u8, path, ".png"))
        .png
    else
        return error.UnknownImageFormat;

    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [64 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const w = &file_writer.interface;
    switch (format) {
        .ppm => try writePpm(w, canvas),
        .png => try writePng(gpa, w, canvas),
    }
    try w.flush();
}

test "PPM header and pixels" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 2, 1);
    defer canvas.deinit(gpa);
    canvas.pixels[1] = .hex(0x0a0b0c);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try writePpm(&out.writer, canvas);
    try std.testing.expectEqualSlices(u8, "P6\n2 1\n255\n\x00\x00\x00\x0a\x0b\x0c", out.written());
}

test "PNG round trip through std's zlib decompressor" {
    const gpa = std.testing.allocator;
    var canvas = try Canvas.init(gpa, 3, 2);
    defer canvas.deinit(gpa);
    canvas.pixels[4] = .hex(0x102030);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try writePng(gpa, &out.writer, canvas);
    const png = out.written();

    try std.testing.expectEqualStrings(png_signature, png[0..8]);
    try std.testing.expectEqualStrings("IHDR", png[12..16]);
    // The IDAT chunk follows IHDR (8 + 4 + 4 + 13 + 4 bytes in).
    const idat_len = std.mem.readInt(u32, png[33..37], .big);
    try std.testing.expectEqualStrings("IDAT", png[37..41]);
    var compressed: std.Io.Reader = .fixed(png[41..][0..idat_len]);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var zlib: std.compress.flate.Decompress = .init(&compressed, .zlib, &window);
    const raw = try zlib.reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(raw);
    // Row 1 is: filter byte, pixel (0,1), pixel (1,1) = 0x102030, pixel (2,1).
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0x10, 0x20, 0x30, 0, 0, 0 }, raw[10..20]);
    try std.testing.expectEqualStrings("IEND", png[png.len - 8 ..][0..4]);
}
