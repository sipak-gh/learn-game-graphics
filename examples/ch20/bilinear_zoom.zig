//! Magnification: an 8x8 checkerboard texture drawn 16 times larger, once
//! with nearest sampling and once with bilinear filtering, side by side in
//! zoom.ppm. Also prints one row of each, so the difference shows in text.
const std = @import("std");

const n = 8; // texels per side
const zoom = 16; // pixels per texel
const out_size = n * zoom;

const Rgb = @Vector(3, f32);

/// The checkerboard: dark and light texels, plus one red texel in the
/// top-left corner so the wrap at the edges is easy to see.
fn texel(x: i32, y: i32) Rgb {
    const ux = x & (n - 1);
    const uy = y & (n - 1);
    if (ux == 0 and uy == 0) return .{ 220, 40, 40 };
    return if ((ux + uy) & 1 == 0) .{ 200, 200, 190 } else .{ 40, 40, 60 };
}

fn nearest(u: f32, v: f32) Rgb {
    return texel(@intFromFloat(@floor(u * n)), @intFromFloat(@floor(v * n)));
}

fn lerp(a: Rgb, b: Rgb, t: f32) Rgb {
    return a + (b - a) * @as(Rgb, @splat(t));
}

/// Texel centers sit at half-texel positions, so shift by half a texel,
/// then blend the four texels around the point.
fn bilinear(u: f32, v: f32) Rgb {
    const x = u * n - 0.5;
    const y = v * n - 0.5;
    const x0 = @floor(x);
    const y0 = @floor(y);
    const ix: i32 = @intFromFloat(x0);
    const iy: i32 = @intFromFloat(y0);
    const above = lerp(texel(ix, iy), texel(ix + 1, iy), x - x0);
    const below = lerp(texel(ix, iy + 1), texel(ix + 1, iy + 1), x - x0);
    return lerp(above, below, y - y0);
}

/// The texture coordinate at the center of output pixel i.
fn coord(i: usize) f32 {
    return (@as(f32, @floatFromInt(i)) + 0.5) / out_size;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gap = 8;
    const width = 2 * out_size + gap;

    std.debug.print("row 40, red channel, every 4th pixel from x = 0 to 60:\n", .{});
    inline for (.{ "nearest ", "bilinear" }, .{ nearest, bilinear }) |name, sampler| {
        std.debug.print("{s} ", .{name});
        var x: usize = 0;
        while (x <= 60) : (x += 4) std.debug.print("{d:>4.0}", .{sampler(coord(x), coord(40))[0]});
        std.debug.print("\n", .{});
    }
    std.debug.print("bilinear at the top-left pixel (wraps to texels 7 and 0): {d:.0}\n", .{bilinear(coord(0), coord(0))});

    var buffer: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "zoom.ppm", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.print("P6\n{d} {d}\n255\n", .{ width, out_size });
    for (0..out_size) |y| {
        for (0..width) |x| {
            const c: Rgb = if (x < out_size)
                nearest(coord(x), coord(y))
            else if (x < out_size + gap)
                .{ 255, 255, 255 }
            else
                bilinear(coord(x - out_size - gap), coord(y));
            const bytes: @Vector(3, u8) = @intFromFloat(@round(c));
            try out.writeAll(&@as([3]u8, bytes));
        }
    }
    try out.flush();
    std.debug.print("wrote zoom.ppm ({d}x{d}): nearest on the left, bilinear on the right\n", .{ width, out_size });
}
