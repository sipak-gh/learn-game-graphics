//! The six planes of the view volume as signed distances in clip space,
//! and the outcode of a point: the set of planes it is outside of.
const std = @import("std");

const Vec4 = @Vector(4, f32);

const Plane = enum {
    near,
    far,
    left,
    right,
    bottom,
    top,

    /// >= 0 inside the plane, < 0 outside.
    fn distance(plane: Plane, p: Vec4) f32 {
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

const Outcode = std.EnumSet(Plane);

fn outcode(p: Vec4) Outcode {
    var code: Outcode = .empty;
    for (std.enums.values(Plane)) |plane| {
        if (plane.distance(p) < 0) code.insert(plane);
    }
    return code;
}

pub fn main() void {
    const points = [_]struct { name: []const u8, p: Vec4 }{
        .{ .name = "inside", .p = .{ 0.2, -0.3, 0.5, 1 } },
        .{ .name = "left", .p = .{ -3, 0, 0.9, 2 } },
        .{ .name = "too close", .p = .{ 0, 0, -0.03, 0.02 } },
        .{ .name = "behind", .p = .{ -2, 0, -1.05, -1 } },
        .{ .name = "beyond far", .p = .{ 0, 0, 70, 65 } },
        .{ .name = "on the edge", .p = .{ 1, 1, 0.5, 1 } },
    };
    std.debug.print("{s:<13} {s:>6} {s:>6} {s:>6} {s:>6} {s:>6} {s:>6}  outside of\n", .{
        "point", "near", "far", "left", "right", "bottom", "top",
    });
    for (points) |pt| {
        std.debug.print("{s:<13}", .{pt.name});
        for (std.enums.values(Plane)) |plane| std.debug.print(" {d:>6.2}", .{plane.distance(pt.p)});
        const code = outcode(pt.p);
        std.debug.print("  {{", .{});
        var it = code.iterator();
        while (it.next()) |plane| std.debug.print(" {t}", .{plane});
        std.debug.print(" }}\n", .{});
    }

    // A triangle is rejected when all its corners are outside one plane:
    // the intersection of their outcodes is not empty.
    const tri = [3]Vec4{ .{ -3, 0, 0.9, 2 }, .{ -2, 1, 0.5, 1 }, .{ -5, -4, 0.7, 3 } };
    var any: Outcode = .empty;
    var all: Outcode = .full;
    for (tri) |p| {
        any = any.unionWith(outcode(p));
        all = all.intersectWith(outcode(p));
    }
    std.debug.print("triangle: union {d} plane(s), intersection {d} plane(s) -> {s}\n", .{
        any.count(), all.count(), if (all.count() > 0) "reject" else if (any.count() == 0) "accept" else "clip",
    });
}
