//! A PNG chunk is: length (u32, big-endian), a 4-letter type, the data,
//! and a CRC-32 of the type and data. Builds IEND and IHDR and prints them.
const std = @import("std");

/// Writes one chunk into `out` and returns the bytes written.
fn chunk(out: []u8, kind: *const [4]u8, data: []const u8) []u8 {
    std.mem.writeInt(u32, out[0..4], @intCast(data.len), .big);
    out[4..8].* = kind.*;
    @memcpy(out[8..][0..data.len], data);
    var crc: std.hash.Crc32 = .init();
    crc.update(kind);
    crc.update(data);
    std.mem.writeInt(u32, out[8 + data.len ..][0..4], crc.final(), .big);
    return out[0 .. 12 + data.len];
}

fn ihdr(width: u32, height: u32) [13]u8 {
    var data: [13]u8 = undefined;
    std.mem.writeInt(u32, data[0..4], width, .big);
    std.mem.writeInt(u32, data[4..8], height, .big);
    data[8..13].* = .{ 8, 2, 0, 0, 0 }; // 8 bits, RGB, zlib, filter set 0, no interlace
    return data;
}

pub fn main() void {
    std.debug.print("crc32(\"IEND\") = 0x{X:0>8}\n", .{std.hash.Crc32.hash("IEND")});

    var buffer: [64]u8 = undefined;
    const iend = chunk(&buffer, "IEND", "");
    std.debug.print("IEND chunk ({d} bytes): {x}\n", .{ iend.len, iend });

    const data = ihdr(640, 400);
    const header = chunk(&buffer, "IHDR", &data);
    std.debug.print("IHDR chunk ({d} bytes):\n", .{header.len});
    std.debug.print("  length {x}\n  type   {x} ({s})\n  data   {x}\n  crc    {x}\n", .{
        header[0..4], header[4..8], header[4..8], header[8..21], header[21..25],
    });
}

test "the CRC of IEND is the well-known constant" {
    try std.testing.expectEqual(0xAE426082, std.hash.Crc32.hash("IEND"));
}

test "a chunk is 12 bytes plus its data" {
    var buffer: [64]u8 = undefined;
    const data = ihdr(2, 2);
    const c = chunk(&buffer, "IHDR", &data);
    try std.testing.expectEqual(25, c.len);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 13 }, c[0..4]);
    try std.testing.expectEqualStrings("IHDR", c[4..8]);
}
