//! Why draw nearest first? The depth test runs before the shader: a pixel
//! behind something already drawn is rejected before it costs any shading.
//! Draws 200 random rectangles, each at one random depth, into a small
//! depth buffer three times: in random order, far to near, and near to
//! far. Counts the pixels covered (depth tested) and the pixels shaded
//! (passed the test), per pixel of the screen.
const std = @import("std");

const w = 160;
const h = 100;

const Rect = struct { x: usize, y: usize, rw: usize, rh: usize, depth: f32 };

fn draw(rects: []const Rect, name: []const u8) void {
    var depth: [w * h]f32 = @splat(1);
    var covered: usize = 0;
    var shaded: usize = 0;
    for (rects) |r| {
        for (r.y..r.y + r.rh) |y| {
            for (r.x..r.x + r.rw) |x| {
                covered += 1;
                const i = y * w + x;
                if (r.depth >= depth[i]) continue;
                depth[i] = r.depth;
                shaded += 1; // here a shader would run
            }
        }
    }
    // Pixels no rectangle covers stay at depth 1.
    var seen: usize = 0;
    for (depth) |z| seen += @intFromBool(z < 1);
    const screen: f32 = w * h;
    std.debug.print("{s:<14} covered {d:.2}x  shaded {d:.2}x  shaded per pixel seen {d:.2}x\n", .{
        name,
        @as(f32, @floatFromInt(covered)) / screen,
        @as(f32, @floatFromInt(shaded)) / screen,
        @as(f32, @floatFromInt(shaded)) / @as(f32, @floatFromInt(seen)),
    });
}

fn nearer(_: void, a: Rect, b: Rect) bool {
    return a.depth < b.depth;
}

fn farther(_: void, a: Rect, b: Rect) bool {
    return a.depth > b.depth;
}

pub fn main() void {
    var prng: std.Random.DefaultPrng = .init(23);
    const random = prng.random();
    var rects: [200]Rect = undefined;
    for (&rects) |*r| {
        const rw = random.intRangeAtMost(usize, 10, 60);
        const rh = random.intRangeAtMost(usize, 6, 40);
        r.* = .{
            .x = random.uintLessThan(usize, w - rw + 1),
            .y = random.uintLessThan(usize, h - rh + 1),
            .rw = rw,
            .rh = rh,
            .depth = random.float(f32),
        };
    }
    draw(&rects, "random order");
    std.mem.sort(Rect, &rects, {}, farther);
    draw(&rects, "far to near");
    std.mem.sort(Rect, &rects, {}, nearer);
    draw(&rects, "near to far");
}
