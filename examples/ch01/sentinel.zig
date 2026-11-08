//! C strings end with a 0 byte. Zig writes that in the type: [:0]const u8.
const std = @import("std");

pub fn main() void {
    // A string literal is a pointer to a 0-terminated array.
    const literal = "QUADFALL";
    std.debug.print("literal: {s}, type {s}\n", .{ literal, @typeName(@TypeOf(literal)) });

    // Coerces to a sentinel slice: the length, plus a promise of a 0 after it.
    const text: [:0]const u8 = literal;
    std.debug.print("text.len = {d}, text[text.len] = {d}\n", .{ text.len, text[text.len] });

    // Formatting into a stack buffer, with a 0 written after the text.
    var buf: [32]u8 = undefined;
    const frame: u32 = 99;
    const dt: f32 = 1.0 / 60.0;
    const info = std.mem.printSentinel(&buf, "frame {d} dt {d:.1} ms", .{ frame, dt * 1000 }, 0) catch unreachable;
    std.debug.print("info: \"{s}\" ({d} bytes + the 0), type {s}\n", .{ info, info.len, @typeName(@TypeOf(info)) });

    // If the buffer is too small, printSentinel fails instead of overflowing it.
    var small: [8]u8 = undefined;
    if (std.mem.printSentinel(&small, "frame {d}", .{frame}, 0)) |s| {
        std.debug.print("fits: {s}\n", .{s});
    } else |err| {
        std.debug.print("8-byte buffer: {t}\n", .{err});
    }
}
