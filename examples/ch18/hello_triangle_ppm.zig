//! A complete little rasterizer: fixed point, the top-left rule, edge
//! functions stepped from pixel to pixel, and barycentric colors. It fills
//! a hexagon cut into four triangles and checks that no pixel is written
//! twice, then saves the picture as hexagon.ppm.
const std = @import("std");

const width = 160;
const height = 120;
const one = 16;
const Point = struct { x: i32, y: i32 };
const Vec3 = @Vector(3, f32);
const Vec3i = @Vector(3, i32);

fn edge(a: Point, b: Point, p: Point) i32 {
    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

fn px(x: f32, y: f32) Point {
    return .{ .x = @intFromFloat(@round(x * one)), .y = @intFromFloat(@round(y * one)) };
}

fn isTopLeft(a: Point, b: Point) bool {
    return b.y < a.y or (b.y == a.y and b.x > a.x);
}

/// Calls visitor.pixel(x, y, weights) for each pixel center in the
/// clockwise triangle v.
fn fillTriangle(v: [3]Point, top_left: bool, visitor: anytype) void {
    const a, const b, const c = v;
    std.debug.assert(edge(a, b, c) > 0);
    const min_x = @max(@divFloor(@min(a.x, b.x, c.x), one), 0);
    const min_y = @max(@divFloor(@min(a.y, b.y, c.y), one), 0);
    const max_x = @min(@divFloor(@max(a.x, b.x, c.x), one), width - 1);
    const max_y = @min(@divFloor(@max(a.y, b.y, c.y), one), height - 1);

    const bias: Vec3i = if (top_left) .{
        if (isTopLeft(b, c)) 0 else -1,
        if (isTopLeft(c, a)) 0 else -1,
        if (isTopLeft(a, b)) 0 else -1,
    } else @splat(0);
    const start: Point = .{ .x = min_x * one + one / 2, .y = min_y * one + one / 2 };
    var row = Vec3i{ edge(b, c, start), edge(c, a, start), edge(a, b, start) } + bias;
    const step_x: Vec3i = .{ (b.y - c.y) * one, (c.y - a.y) * one, (a.y - b.y) * one };
    const step_y: Vec3i = .{ (c.x - b.x) * one, (a.x - c.x) * one, (b.x - a.x) * one };
    const inv_area: Vec3 = @splat(1 / @as(f32, @floatFromInt(edge(a, b, c))));

    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var e = row;
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            if (@reduce(.Or, e) >= 0) {
                visitor.pixel(@intCast(x), @intCast(y), @as(Vec3, @floatFromInt(e - bias)) * inv_area);
            }
            e += step_x;
        }
        row += step_y;
    }
}

/// Blends the corner colors of one triangle into the picture.
const Painter = struct {
    rgb: *[height][width]Vec3,
    writes: *[height][width]u8,
    colors: [3]Vec3,

    pub fn pixel(p: Painter, x: usize, y: usize, w: Vec3) void {
        p.rgb[y][x] = p.colors[0] * @as(Vec3, @splat(w[0])) +
            p.colors[1] * @as(Vec3, @splat(w[1])) + p.colors[2] * @as(Vec3, @splat(w[2]));
        p.writes[y][x] += 1;
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // A hexagon, corners clockwise on the screen, each with its own color.
    // The corners are pixel centers, so the inner edges of the fan pass
    // through many pixel centers too.
    const corners = [6]Point{
        px(40.5, 10.5),   px(120.5, 10.5), px(150.5, 60.5),
        px(120.5, 110.5), px(40.5, 110.5), px(10.5, 60.5),
    };
    const colors = [6]Vec3{
        .{ 255, 64, 64 },  .{ 255, 200, 40 }, .{ 80, 220, 80 },
        .{ 40, 200, 255 }, .{ 80, 80, 255 },  .{ 230, 80, 230 },
    };

    var rgb: [height][width]Vec3 = @splat(@splat(@splat(24)));
    for ([_]bool{ false, true }) |top_left| {
        var writes: [height][width]u8 = @splat(@splat(0));
        // A fan around corner 0: (0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 5).
        for (1..5) |k| {
            const painter: Painter = .{
                .rgb = &rgb,
                .writes = &writes,
                .colors = .{ colors[0], colors[k], colors[k + 1] },
            };
            fillTriangle(.{ corners[0], corners[k], corners[k + 1] }, top_left, painter);
        }
        var counts: [3]usize = .{ 0, 0, 0 };
        for (writes) |line| for (line) |n| {
            counts[@min(n, 2)] += 1;
        };
        std.debug.print("{s:<14} pixels written once: {d}, twice: {d}\n", .{
            if (top_left) "top-left rule:" else "e >= 0:", counts[1], counts[2],
        });
    }

    var buffer: [4096]u8 = undefined;
    const file = try std.Io.Dir.cwd().createFile(io, "hexagon.ppm", .{});
    defer file.close(io);
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.print("P6\n{d} {d}\n255\n", .{ width, height });
    for (rgb) |line| for (line) |c| {
        const r: @Vector(3, u8) = @intFromFloat(@round(std.math.clamp(c, @as(Vec3, @splat(0)), @as(Vec3, @splat(255)))));
        try out.writeAll(&@as([3]u8, r));
    };
    try out.flush();
    std.debug.print("wrote hexagon.ppm\n", .{});
}
