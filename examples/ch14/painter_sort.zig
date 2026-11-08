//! The painter's algorithm in one dimension: three sprites cover parts of
//! a 24-column screen. Drawing far to near leaves the nearest one on top;
//! drawing near to far lets the farthest one paint over everything.
const std = @import("std");

const Sprite = struct { name: u8, dist: f32, x0: usize, x1: usize };

fn fartherFirst(_: void, a: Sprite, b: Sprite) bool {
    return a.dist > b.dist;
}

fn nearerFirst(_: void, a: Sprite, b: Sprite) bool {
    return a.dist < b.dist;
}

fn paint(sprites: []const Sprite) [24]u8 {
    var screen: [24]u8 = @splat('.');
    for (sprites) |s| {
        for (s.x0..s.x1) |x| screen[x] = s.name;
    }
    return screen;
}

pub fn main() void {
    var sprites = [_]Sprite{
        .{ .name = 'B', .dist = 2.0, .x0 = 6, .x1 = 16 }, // barrel, near: wide
        .{ .name = 'L', .dist = 6.0, .x0 = 2, .x1 = 8 }, // lamp, far
        .{ .name = 'C', .dist = 4.0, .x0 = 12, .x1 = 20 }, // crate, middle
    };
    std.mem.sort(Sprite, &sprites, {}, fartherFirst);
    const good = paint(&sprites);
    std.debug.print("far to near: {s}   order ", .{&good});
    for (sprites) |s| std.debug.print("{c}", .{s.name});
    std.debug.print("\n", .{});

    std.mem.sort(Sprite, &sprites, {}, nearerFirst);
    const bad = paint(&sprites);
    std.debug.print("near to far: {s}   order ", .{&bad});
    for (sprites) |s| std.debug.print("{c}", .{s.name});
    std.debug.print("\n", .{});
}
