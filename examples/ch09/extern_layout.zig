//! `extern struct` fixes the field order in memory; a plain struct does not.
const std = @import("std");

/// The layout raylib's R8G8B8A8 textures expect: r, g, b, a, one byte each.
const Color = extern struct { r: u8, g: u8, b: u8, a: u8 = 255 };

/// Mixed sizes show the difference: Zig may reorder a plain struct's fields
/// to save padding; an extern struct keeps the C rules.
const Plain = struct { tag: u8, value: u32, flag: u8 };
const Extern = extern struct { tag: u8, value: u32, flag: u8 };

pub fn main() void {
    std.debug.print("Color: size {d}, offsets r={d} g={d} b={d} a={d}\n", .{
        @sizeOf(Color),        @offsetOf(Color, "r"), @offsetOf(Color, "g"),
        @offsetOf(Color, "b"), @offsetOf(Color, "a"),
    });
    const orange: Color = .{ .r = 0xff, .g = 0x80, .b = 0x00 };
    std.debug.print("orange as bytes: {any}\n", .{std.mem.asBytes(&orange)});

    inline for (.{ Plain, Extern }) |T| {
        std.debug.print("{s}: size {d}, offsets tag={d} value={d} flag={d}\n", .{
            @typeName(T),          @sizeOf(T),           @offsetOf(T, "tag"),
            @offsetOf(T, "value"), @offsetOf(T, "flag"),
        });
    }
}
