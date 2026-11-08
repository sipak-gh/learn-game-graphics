//! Cohen-Sutherland line clipping: 4-bit outcodes decide most segments at
//! once; the rest are cut at one rectangle side at a time.
const std = @import("std");

const xmin = 0.0;
const xmax = 20.0;
const ymin = 0.0;
const ymax = 10.0;

const left: u4 = 0b0001;
const right: u4 = 0b0010;
const top: u4 = 0b0100; // y < ymin (screen y grows down)
const bottom: u4 = 0b1000;

const Point = struct { x: f32, y: f32 };

fn outcode(p: Point) u4 {
    var code: u4 = 0;
    if (p.x < xmin) code |= left else if (p.x > xmax) code |= right;
    if (p.y < ymin) code |= top else if (p.y > ymax) code |= bottom;
    return code;
}

/// The visible part of the segment, or null.
fn clipLine(a_in: Point, b_in: Point, rounds: *u32) ?[2]Point {
    var a = a_in;
    var b = b_in;
    var ca = outcode(a);
    var cb = outcode(b);
    while (true) {
        if (ca | cb == 0) return .{ a, b }; // both inside: accept
        if (ca & cb != 0) return null; // both outside one side: reject
        rounds.* += 1;
        // Move an outside end onto the side it is outside of.
        const code = if (ca != 0) ca else cb;
        var p: Point = undefined;
        if (code & left != 0) {
            p = .{ .x = xmin, .y = a.y + (b.y - a.y) * (xmin - a.x) / (b.x - a.x) };
        } else if (code & right != 0) {
            p = .{ .x = xmax, .y = a.y + (b.y - a.y) * (xmax - a.x) / (b.x - a.x) };
        } else if (code & top != 0) {
            p = .{ .x = a.x + (b.x - a.x) * (ymin - a.y) / (b.y - a.y), .y = ymin };
        } else {
            p = .{ .x = a.x + (b.x - a.x) * (ymax - a.y) / (b.y - a.y), .y = ymax };
        }
        if (code == ca) {
            a = p;
            ca = outcode(a);
        } else {
            b = p;
            cb = outcode(b);
        }
    }
}

pub fn main() void {
    const segments = [_][2]Point{
        .{ .{ .x = 2, .y = 2 }, .{ .x = 18, .y = 8 } }, // inside
        .{ .{ .x = -5, .y = 1 }, .{ .x = -1, .y = 9 } }, // left of the box
        .{ .{ .x = 3, .y = -4 }, .{ .x = 30, .y = -1 } }, // above it
        .{ .{ .x = -5, .y = 5 }, .{ .x = 10, .y = 5 } }, // enters from the left
        .{ .{ .x = -4, .y = -6 }, .{ .x = 26, .y = 14 } }, // through two corners' regions
        .{ .{ .x = -6, .y = 4 }, .{ .x = 4, .y = -6 } }, // misses the corner
    };
    for (segments) |s| {
        var rounds: u32 = 0;
        const ca = outcode(s[0]);
        const cb = outcode(s[1]);
        std.debug.print("({d},{d})-({d},{d})  codes {b:0>4} {b:0>4}: ", .{ s[0].x, s[0].y, s[1].x, s[1].y, ca, cb });
        if (clipLine(s[0], s[1], &rounds)) |c| {
            std.debug.print("visible ({d:.2},{d:.2})-({d:.2},{d:.2}) after {d} cut(s)\n", .{ c[0].x, c[0].y, c[1].x, c[1].y, rounds });
        } else {
            std.debug.print("rejected after {d} cut(s)\n", .{rounds});
        }
    }
}
