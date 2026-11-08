//! The seven pieces in their spawn state, in a row, each in its color.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const Kind = enum { i, o, t, s, z, j, l };

/// Spawn pictures, top row first (the same as quadfall's core/piece.zig).
const pictures: std.enums.EnumArray(Kind, []const u8) = .init(.{
    .i = "....\nXXXX\n....\n....",
    .o = "XX\nXX",
    .t = ".X.\nXXX\n...",
    .s = ".XX\nXX.\n...",
    .z = "XX.\n.XX\n...",
    .j = "X..\nXXX\n...",
    .l = "..X\nXXX\n...",
});

const colors: std.enums.EnumArray(Kind, rl.Color) = .init(.{
    .i = .{ .r = 0, .g = 200, .b = 230, .a = 255 },
    .o = .{ .r = 240, .g = 210, .b = 0, .a = 255 },
    .t = .{ .r = 170, .g = 60, .b = 220, .a = 255 },
    .s = .{ .r = 60, .g = 200, .b = 70, .a = 255 },
    .z = .{ .r = 230, .g = 50, .b = 60, .a = 255 },
    .j = .{ .r = 40, .g = 90, .b = 230, .a = 255 },
    .l = .{ .r = 240, .g = 140, .b = 20, .a = 255 },
});

const cell = 32;

fn block(x: i32, y: i32, color: rl.Color) void {
    const edge = cell / 8;
    rl.DrawRectangle(x, y, cell, cell, rl.ColorBrightness(color, -0.35));
    rl.DrawRectangle(x, y, cell - edge, cell - edge, rl.ColorBrightness(color, 0.35));
    rl.DrawRectangle(x + edge, y + edge, cell - 2 * edge, cell - 2 * edge, color);
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(816, 200, "draw_pieces");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(.{ .r = 24, .g = 24, .b = 32, .a = 255 });

        var x: i32 = 24;
        for (std.meta.tags(Kind)) |kind| {
            const picture = pictures.get(kind);
            const size: i32 = @intCast(std.mem.findScalar(u8, picture, '\n').?);
            // The box outline: every piece turns inside this square.
            rl.DrawRectangleLines(x, 40, size * cell, size * cell, rl.DARKGRAY);
            var lines = std.mem.splitScalar(u8, picture, '\n');
            var y: i32 = 40;
            while (lines.next()) |line| : (y += cell) {
                for (line, 0..) |c, col| {
                    if (c == 'X') block(x + @as(i32, @intCast(col)) * cell, y, colors.get(kind));
                }
            }
            rl.DrawText(@tagName(kind), x, 170, 20, rl.LIGHTGRAY);
            x += size * cell + 16;
        }
    }
    std.debug.print("ran {d} frames\n", .{demo.frame});
}
