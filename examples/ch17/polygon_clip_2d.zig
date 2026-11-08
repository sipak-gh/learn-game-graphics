//! Sutherland-Hodgman in 2D: clip a triangle to a rectangle, one side at a
//! time, printing the polygon after each side and a picture at the end.
const std = @import("std");

const Vec2 = @Vector(2, f32);

/// A polygon with room for the 3 + 4 vertices a triangle can grow to.
const Polygon = struct {
    buffer: [7]Vec2 = undefined,
    len: usize = 0,

    fn append(p: *Polygon, v: Vec2) void {
        p.buffer[p.len] = v;
        p.len += 1;
    }

    fn vertices(p: *const Polygon) []const Vec2 {
        return p.buffer[0..p.len];
    }
};

/// A side of the rectangle as a signed distance, >= 0 inside.
const Side = enum {
    left,
    right,
    top,
    bottom,

    fn distance(side: Side, p: Vec2) f32 {
        return switch (side) {
            .left => p[0] - 0,
            .right => 20 - p[0],
            .top => p[1] - 0,
            .bottom => 10 - p[1],
        };
    }
};

fn clip(in: Polygon, side: Side) Polygon {
    var out: Polygon = .{};
    const vs = in.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        const da = side.distance(a);
        const db = side.distance(b);
        if (da >= 0) out.append(a);
        // The edge crosses the side: add the crossing, interpolated from
        // the inside end.
        if ((da >= 0) != (db >= 0)) {
            const in_v, const out_v, const d_in, const d_out = if (da >= 0) .{ a, b, da, db } else .{ b, a, db, da };
            const t = d_in / (d_in - d_out);
            out.append(in_v + (out_v - in_v) * @as(Vec2, @splat(t)));
        }
    }
    return out;
}

fn print(label: []const u8, p: Polygon) void {
    std.debug.print("{s:<14} {d} vertices:", .{ label, p.len });
    for (p.vertices()) |v| std.debug.print(" ({d:.1},{d:.1})", .{ v[0], v[1] });
    std.debug.print("\n", .{});
}

/// Inside a convex polygon whose corners go clockwise on a y-down grid.
fn inside(p: Polygon, q: Vec2) bool {
    const vs = p.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        if ((b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0]) < 0) return false;
    }
    return vs.len >= 3;
}

pub fn main() void {
    var tri: Polygon = .{};
    for ([_]Vec2{ .{ -6, 4 }, .{ 14, -4 }, .{ 26, 13 } }) |v| tri.append(v);
    print("triangle", tri);
    var poly = tri;
    for (std.enums.values(Side)) |side| {
        poly = clip(poly, side);
        var label: [16]u8 = undefined;
        print(std.fmt.bufPrint(&label, "after {t}", .{side}) catch unreachable, poly);
    }

    // '#' kept, 'o' clipped away, ':' in the rectangle but not in the
    // triangle, '.' in neither. The rectangle is x 0..20, y 0..10, and y
    // grows downward as on a screen.
    var y: f32 = -5;
    while (y < 14) : (y += 1) {
        var x: f32 = -7;
        while (x < 27) : (x += 1) {
            const q: Vec2 = .{ x + 0.5, y + 0.5 };
            const ch: u8 = if (inside(poly, q)) '#' else if (inside(tri, q)) 'o' else if (Side.left.distance(q) >= 0 and
                Side.right.distance(q) >= 0 and Side.top.distance(q) >= 0 and Side.bottom.distance(q) >= 0) ':' else '.';
            std.debug.print("{c}", .{ch});
        }
        std.debug.print("\n", .{});
    }
}
