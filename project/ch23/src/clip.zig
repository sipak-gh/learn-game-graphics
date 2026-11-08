//! Clipping: cutting a triangle down to the part that is inside the view
//! volume, before anything is divided by w.
//!
//! In clip space a point is visible when
//!     -w <= x <= w,   -w <= y <= w,   0 <= z <= w.
//! Each of these six inequalities is one plane of the view volume. Written
//! as a distance d(p) that is >= 0 on the inside, d is linear in p, so
//! along an edge from a to b it changes linearly and crosses zero at
//! t = d(a) / (d(a) - d(b)).
const std = @import("std");
const math = @import("math.zig");
const Vec4 = math.Vec4;

/// Values that travel with a vertex and are interpolated across the
/// triangle, such as a color or a texture coordinate. Clipping cuts them
/// exactly like the position.
pub const Varyings = @Vector(16, f32);

pub const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

    /// How far inside the plane `p` is (in clip-space units): negative
    /// means outside.
    pub fn distance(plane: Plane, p: Vec4) f32 {
        const x, const y, const z, const w = p;
        return switch (plane) {
            .near => z,
            .far => w - z,
            .left => w + x,
            .right => w - x,
            .bottom => w + y,
            .top => w - y,
        };
    }
};

/// The set of planes a point is outside of.
pub const Outcode = std.EnumSet(Plane);

pub fn outcode(p: Vec4) Outcode {
    var code: Outcode = .empty;
    for (std.enums.values(Plane)) |plane| {
        if (plane.distance(p) < 0) code.insert(plane);
    }
    return code;
}

pub const Vertex = struct {
    pos: Vec4,
    vary: Varyings = @splat(0),
    /// The plane that made the edge from this vertex to the next one, or
    /// null if that edge is (part of) an edge of the original triangle.
    edge: ?Plane = null,
};

/// Each plane cuts at most one corner off a convex polygon, adding at
/// most one vertex: a triangle clipped by six planes has at most 9.
pub const max_vertices = 3 + 6;

/// A convex polygon, its vertices in the order of the triangle's.
pub const Polygon = struct {
    buffer: [max_vertices]Vertex = undefined,
    len: usize = 0,

    pub fn vertices(poly: *const Polygon) []const Vertex {
        return poly.buffer[0..poly.len];
    }

    fn append(poly: *Polygon, v: Vertex) void {
        poly.buffer[poly.len] = v;
        poly.len += 1;
    }
};

/// Clips the triangle against each plane in `planes`, one after another
/// (the Sutherland-Hodgman algorithm). Planes no corner is outside of
/// cannot cut anything, so pass the union of the corners' outcodes. The
/// result is empty, or a convex polygon of 3 to 9 vertices.
pub fn clipTriangle(tri: [3]Vertex, planes: Outcode) Polygon {
    var poly: Polygon = .{};
    for (tri) |v| poly.append(v);
    var it = planes.iterator();
    while (it.next()) |plane| {
        poly = clipPolygon(poly, plane);
        if (poly.len < 3) return .{};
    }
    return poly;
}

/// Walks around the polygon once, keeping what is inside `plane`. For
/// each edge a->b:
///   a inside,  b inside:  keep a
///   a inside,  b outside: keep a, then the crossing (the edge from it
///                         to the next vertex runs along the plane)
///   a outside, b inside:  the crossing
///   both outside:         nothing
fn clipPolygon(in: Polygon, plane: Plane) Polygon {
    var out: Polygon = .{};
    const vs = in.vertices();
    for (vs, 0..) |a, i| {
        const b = vs[(i + 1) % vs.len];
        const a_in = plane.distance(a.pos) >= 0;
        const b_in = plane.distance(b.pos) >= 0;
        if (a_in) out.append(a);
        if (a_in and !b_in) {
            var v = crossing(a, b, plane);
            v.edge = plane;
            out.append(v);
        } else if (!a_in and b_in) {
            var v = crossing(b, a, plane);
            v.edge = a.edge;
            out.append(v);
        }
    }
    return out;
}

/// Where the edge from `inside` to `outside` crosses the plane. Always
/// going from the inside corner means that two triangles sharing an edge
/// get exactly the same crossing, whatever order their corners are in,
/// and no crack opens between them.
fn crossing(inside: Vertex, outside: Vertex, plane: Plane) Vertex {
    const d_in = plane.distance(inside.pos);
    const d_out = plane.distance(outside.pos);
    const t = d_in / (d_in - d_out);
    return .{
        .pos = math.lerp(inside.pos, outside.pos, t),
        .vary = math.lerp(inside.vary, outside.vary, t),
    };
}

const testing = std.testing;

fn allOutcodes(tri: [3]Vertex) [2]Outcode {
    const a, const b, const c = .{ outcode(tri[0].pos), outcode(tri[1].pos), outcode(tri[2].pos) };
    return .{ a.unionWith(b).unionWith(c), a.intersectWith(b).intersectWith(c) };
}

test "outcodes accept a triangle inside and reject one outside" {
    const inside = [3]Vertex{
        .{ .pos = .{ 0, 0, 0.5, 1 } },
        .{ .pos = .{ 0.5, 0, 0.5, 1 } },
        .{ .pos = .{ 0, 0.5, 0.5, 1 } },
    };
    const any, _ = allOutcodes(inside);
    try testing.expectEqual(Outcode.empty, any);
    const poly = clipTriangle(inside, any);
    try testing.expectEqual(3, poly.len);
    try testing.expectEqual(inside[1], poly.vertices()[1]);

    // All three corners are right of x = w: nothing of it can be visible,
    // though each corner is inside the other five planes.
    const right = [3]Vertex{
        .{ .pos = .{ 2, 0, 0.5, 1 } },
        .{ .pos = .{ 3, -0.5, 0.5, 1 } },
        .{ .pos = .{ 3, 0.5, 0.5, 1 } },
    };
    _, const all = allOutcodes(right);
    try testing.expect(all.eql(.initOne(.right)));
}

test "one corner behind the near plane turns the triangle into a quad" {
    const tri = [3]Vertex{
        .{ .pos = .{ 0, 0, -1, 0.5 } }, // behind
        .{ .pos = .{ 0.5, 0, 1, 2 } },
        .{ .pos = .{ -0.5, 0, 1, 2 } },
    };
    const poly = clipTriangle(tri, .initOne(.near));
    try testing.expectEqual(4, poly.len);
    var on_plane: usize = 0;
    var near_edges: usize = 0;
    for (poly.vertices()) |v| {
        try testing.expect(v.pos[2] >= 0);
        if (v.pos[2] == 0) on_plane += 1;
        if (v.edge == .near) near_edges += 1;
    }
    // The cut leaves two new corners on the plane, joined by one new edge.
    try testing.expectEqual(2, on_plane);
    try testing.expectEqual(1, near_edges);
}

test "two corners behind the near plane leave a smaller triangle" {
    const tri = [3]Vertex{
        .{ .pos = .{ 0, 0, 1, 2 } },
        .{ .pos = .{ 1, 0, -1, 0.5 } },
        .{ .pos = .{ -1, 0, -1, 0.5 } },
    };
    const poly = clipTriangle(tri, .initOne(.near));
    try testing.expectEqual(3, poly.len);
    // The first corner is kept, the other two are halfway down their edges.
    try testing.expectEqual(tri[0].pos, poly.vertices()[0].pos);
    try testing.expectEqual(Vec4{ 0.5, 0, 0, 1.25 }, poly.vertices()[1].pos);
    try testing.expectEqual(Vec4{ -0.5, 0, 0, 1.25 }, poly.vertices()[2].pos);
}

test "varyings are cut exactly like the position" {
    // Each vertex carries its own position as varyings, so after clipping
    // the two must still agree.
    var tri: [3]Vertex = .{
        .{ .pos = .{ -3, 0.2, 0.5, 1 } },
        .{ .pos = .{ 2, -2, -0.4, 1.5 } },
        .{ .pos = .{ 0.3, 4, 0.9, 1 } },
    };
    for (&tri) |*v| v.vary = .{ v.pos[0], v.pos[1], v.pos[2], v.pos[3], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const any, _ = allOutcodes(tri);
    const poly = clipTriangle(tri, any);
    try testing.expect(poly.len >= 3);
    for (poly.vertices()) |v| {
        const pos: Vec4 = .{ v.vary[0], v.vary[1], v.vary[2], v.vary[3] };
        try testing.expect(math.approxEq(pos, v.pos));
        try testing.expectEqual(Outcode.empty, outcode(v.pos + Vec4{ 0, 0, 1e-5, 1e-5 }));
    }
}

test "two triangles sharing an edge are cut at the same point" {
    const a: Vertex = .{ .pos = .{ 0.3, 0.1, -0.7, 0.2 } }; // behind
    const b: Vertex = .{ .pos = .{ -0.2, 0.4, 0.9, 3.1 } };
    const left = clipTriangle(.{ a, b, .{ .pos = .{ -1, 0, 0.5, 2 } } }, .initOne(.near));
    const right = clipTriangle(.{ b, a, .{ .pos = .{ 1, 0, 0.5, 2 } } }, .initOne(.near));
    // The corners the two polygons have in common, bit for bit: b, and
    // the crossing on edge a-b.
    var shared: usize = 0;
    for (left.vertices()) |u| {
        for (right.vertices()) |v| shared += @intFromBool(@reduce(.And, u.pos == v.pos));
    }
    try testing.expectEqual(2, shared);
}
