//! The viewport transform: normalized device coordinates (-1 to 1, y up)
//! to pixel coordinates (0 to width, y down) on a 640x400 screen.
const std = @import("std");

const width: f32 = 640;
const height: f32 = 400;

fn toPixels(x: f32, y: f32) [2]f32 {
    return .{ (x + 1) / 2 * width, (1 - y) / 2 * height };
}

fn toNdc(sx: f32, sy: f32) [2]f32 {
    return .{ sx / width * 2 - 1, 1 - sy / height * 2 };
}

pub fn main() void {
    const points = [_]struct { []const u8, [2]f32 }{
        .{ "top left", .{ -1, 1 } },
        .{ "top right", .{ 1, 1 } },
        .{ "bottom left", .{ -1, -1 } },
        .{ "bottom right", .{ 1, -1 } },
        .{ "center", .{ 0, 0 } },
        .{ "halfway up", .{ 0, 0.5 } },
    };
    for (points) |p| {
        const name, const ndc = p;
        const s = toPixels(ndc[0], ndc[1]);
        std.debug.print("{s:<13} ndc ({d:5.2}, {d:5.2}) -> pixels ({d:6.1}, {d:6.1})\n", .{ name, ndc[0], ndc[1], s[0], s[1] });
    }
    // Pixel (x, y) covers [x, x+1) x [y, y+1); its center is at +0.5.
    for ([_][2]f32{ .{ 0, 0 }, .{ 639, 399 } }) |px| {
        const c = toNdc(px[0] + 0.5, px[1] + 0.5);
        std.debug.print("center of pixel ({d}, {d}) is ndc ({d:.7}, {d:.7})\n", .{ px[0], px[1], c[0], c[1] });
    }
    // Which pixel contains a point: floor of the pixel coordinate.
    const s = toPixels(0.5, 0.5);
    std.debug.print("ndc (0.5, 0.5) is pixel ({d}, {d})\n", .{ @floor(s[0]), @floor(s[1]) });
}
