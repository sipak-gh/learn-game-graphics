//! The quadfall palette drawn as bevelled blocks, at three sizes.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const background: rl.Color = .{ .r = 24, .g = 24, .b = 32, .a = 255 };

const palette = [_]struct { name: [:0]const u8, color: rl.Color }{
    .{ .name = "I", .color = .{ .r = 0, .g = 200, .b = 230, .a = 255 } },
    .{ .name = "O", .color = .{ .r = 240, .g = 210, .b = 0, .a = 255 } },
    .{ .name = "T", .color = .{ .r = 170, .g = 60, .b = 220, .a = 255 } },
    .{ .name = "S", .color = .{ .r = 60, .g = 200, .b = 70, .a = 255 } },
    .{ .name = "Z", .color = .{ .r = 230, .g = 50, .b = 60, .a = 255 } },
    .{ .name = "J", .color = .{ .r = 40, .g = 90, .b = 230, .a = 255 } },
    .{ .name = "L", .color = .{ .r = 240, .g = 140, .b = 20, .a = 255 } },
    .{ .name = "#", .color = .{ .r = 110, .g = 110, .b = 120, .a = 255 } },
};

/// A dark square, a light square 1/8 smaller, then the color in the middle:
/// a light top-left edge and a dark bottom-right edge.
fn block(x: i32, y: i32, size: i32, color: rl.Color) void {
    const edge = @divTrunc(size, 8);
    rl.DrawRectangle(x, y, size, size, rl.ColorBrightness(color, -0.35));
    rl.DrawRectangle(x, y, size - edge, size - edge, rl.ColorBrightness(color, 0.35));
    rl.DrawRectangle(x + edge, y + edge, size - 2 * edge, size - 2 * edge, color);
}

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(640, 360, "blocks");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (demo.running()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(background);

        for (palette, 0..) |entry, i| {
            const x: i32 = 40 + @as(i32, @intCast(i)) * 72;
            rl.DrawText(entry.name, x + 24, 30, 20, rl.LIGHTGRAY);
            block(x, 70, 64, entry.color); // large, to see the bevel
            block(x + 16, 160, 32, entry.color); // the game's cell size
            rl.DrawRectangle(x + 16, 220, 32, 32, entry.color); // flat, for comparison
            block(x + 24, 280, 16, entry.color);
        }
    }
}
