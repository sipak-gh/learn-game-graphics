//! What `@import("rl")` gives you: raylib.h translated into Zig declarations.
//! No window is opened.
const std = @import("std");
const rl = @import("rl");

pub fn main() void {
    // #define RAYLIB_VERSION "6.2" becomes a Zig string constant.
    std.debug.print("RAYLIB_VERSION   = {s}\n", .{rl.RAYLIB_VERSION});
    std.debug.print("version numbers  = {d}.{d}.{d}\n", .{
        rl.RAYLIB_VERSION_MAJOR, rl.RAYLIB_VERSION_MINOR, rl.RAYLIB_VERSION_PATCH,
    });

    // typedef struct Color { unsigned char r, g, b, a; } Color;
    std.debug.print("@sizeOf(rl.Color) = {d} bytes\n", .{@sizeOf(rl.Color)});
    const red = rl.RED; // #define RED CLITERAL(Color){ 230, 41, 55, 255 }
    std.debug.print("rl.RED           = {d} {d} {d} {d}\n", .{ red.r, red.g, red.b, red.a });

    // The KeyboardKey enum's values become plain integer constants.
    std.debug.print("KEY_SPACE={d} KEY_ESCAPE={d} KEY_LEFT={d} KEY_A={d}\n", .{
        rl.KEY_SPACE, rl.KEY_ESCAPE, rl.KEY_LEFT, rl.KEY_A,
    });

    // Functions keep their C names and C types.
    std.debug.print("InitWindow : {s}\n", .{@typeName(@TypeOf(rl.InitWindow))});
    std.debug.print("DrawText   : {s}\n", .{@typeName(@TypeOf(rl.DrawText))});
}
