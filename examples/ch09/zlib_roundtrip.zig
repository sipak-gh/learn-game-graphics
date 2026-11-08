//! Compresses bytes into a zlib stream with std.compress.flate and
//! decompresses them again: the API the PNG writer uses for IDAT.
const std = @import("std");
const flate = std.compress.flate;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Two inputs of 64 KiB: a smooth ramp and the XOR pattern.
    var ramp: [256 * 256]u8 = undefined;
    var xor: [256 * 256]u8 = undefined;
    for (0..256) |y| for (0..256) |x| {
        ramp[y * 256 + x] = @intCast(x);
        xor[y * 256 + x] = @intCast(x ^ y);
    };

    for ([_][]const u8{ &ramp, &xor }, [_][]const u8{ "ramp", "xor" }) |input, name| {
        // Compress. The output writer needs a buffer bigger than 8 bytes.
        var out: std.Io.Writer.Allocating = try .initCapacity(gpa, 1024);
        defer out.deinit();
        const window = try gpa.alloc(u8, flate.max_window_len);
        defer gpa.free(window);
        var zlib: flate.Compress = try .init(&out.writer, window, .zlib, .level_4);
        try zlib.writer.writeAll(input);
        try zlib.finish();
        const compressed = out.written();

        // Decompress and compare.
        var in: std.Io.Reader = .fixed(compressed);
        var unzip_window: [flate.max_window_len]u8 = undefined;
        var unzip: flate.Decompress = .init(&in, .zlib, &unzip_window);
        const back = try unzip.reader.allocRemaining(gpa, .unlimited);
        defer gpa.free(back);

        const ok = std.mem.eql(u8, back, input);
        std.debug.print("{s:<4}: {d} bytes -> {d} compressed, header {x}, round trip {s}\n", .{
            name, input.len, compressed.len, compressed[0..2], if (ok) "ok" else "BROKEN",
        });
    }
}
