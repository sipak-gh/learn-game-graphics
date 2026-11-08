//! The program's state and drawing, independent of any window. main.zig
//! calls `update` once per tick and `render` once per frame.
const std = @import("std");
const Canvas = @import("canvas.zig").Canvas;
const Color = @import("canvas.zig").Color;
const draw = @import("draw.zig");
const font = @import("font.zig");
const Point = draw.Point;

pub const App = struct {
    /// Seconds of simulated time.
    time: f32 = 0,
    ticks: u32 = 0,

    pub fn update(app: *App, dt: f32) void {
        app.time += dt;
        app.ticks += 1;
    }

    /// A test card: every 2D primitive, some of them animated, and a HUD.
    pub fn render(app: App, canvas: Canvas) void {
        canvas.clear(.hex(0x1c1c28));

        // A starburst of lines in every octant, turning slowly.
        const center: Point = .{ .x = 120, .y = 150 };
        for (0..24) |i| {
            const angle = app.time * 0.5 + @as(f32, @floatFromInt(i)) * (std.math.tau / 24.0);
            const tip = polar(center, 90, angle);
            draw.line(canvas, center, tip, if (i % 2 == 0) .hex(0xf0c040) else .hex(0x40c0f0));
        }

        // Rectangles: filled, outlined, and one hanging off the left edge.
        draw.fillRect(canvas, 250, 70, 120, 70, .hex(0x3060c0));
        draw.rect(canvas, 240, 60, 140, 90, Color.white);
        draw.fillRect(canvas, -30, 330, 80, 50, .hex(0xc04040));

        // Circles: outlined rings and a filled disc that pulses.
        draw.circle(canvas, .{ .x = 470, .y = 105 }, 45, .hex(0x60e060));
        draw.circle(canvas, .{ .x = 470, .y = 105 }, 30, .hex(0x60e060));
        const r: i32 = 15 + @as(i32, @intFromFloat(10 * @sin(app.time * 3)));
        draw.fillCircle(canvas, .{ .x = 570, .y = 105 }, r, .hex(0xe08040));

        // A spinning filled triangle.
        const tri: Point = .{ .x = 310, .y = 280 };
        draw.fillTriangle(
            canvas,
            polar(tri, 70, app.time),
            polar(tri, 70, app.time + std.math.tau / 3.0),
            polar(tri, 70, app.time + 2 * std.math.tau / 3.0),
            .hex(0xa050e0),
        );

        // A hexagon made of six triangles with shared edges.
        const hex: Point = .{ .x = 500, .y = 280 };
        for (0..6) |i| {
            const a = @as(f32, @floatFromInt(i)) * (std.math.tau / 6.0);
            const shade: u8 = @intCast(80 + i * 30);
            draw.fillTriangle(canvas, hex, polar(hex, 70, a), polar(hex, 70, a + std.math.tau / 6.0), .{ .r = shade, .g = shade, .b = 255 });
        }

        // The HUD: text drawn with the bitmap font.
        _ = font.drawText(canvas, 8, 8, "delve test card", 2, Color.white);
        var buffer: [64]u8 = undefined;
        const status = std.fmt.bufPrint(&buffer, "tick {d}  time {d:.2}s", .{ app.ticks, app.time }) catch unreachable;
        const w: i32 = @intCast(canvas.width);
        _ = font.drawText(canvas, w - 8 - font.textWidth(status, 1), 12, status, 1, .hex(0xc0c0c0));
        _ = font.drawText(canvas, 120, 372, "abcdefghijklmnopqrstuvwxyz 0123456789 !\"#%'()*+,-./:;<=>?[]_|", 1, .hex(0xc0c0c0));
    }
};

/// The point `radius` pixels from `center` in direction `angle` (radians,
/// clockwise on screen because y points down).
fn polar(center: Point, radius: f32, angle: f32) Point {
    return .{
        .x = center.x + @as(i32, @intFromFloat(@round(radius * @cos(angle)))),
        .y = center.y + @as(i32, @intFromFloat(@round(radius * @sin(angle)))),
    };
}
