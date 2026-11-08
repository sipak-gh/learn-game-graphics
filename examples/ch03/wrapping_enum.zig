//! An enum with a 2-bit backing integer, turned with wrapping arithmetic.
const std = @import("std");

/// The four rotation states in clockwise order.
const Rotation = enum(u2) {
    spawn,
    right,
    flip,
    left,

    fn cw(r: Rotation) Rotation {
        return @fromBackingInt(@backingInt(r) +% 1);
    }

    fn ccw(r: Rotation) Rotation {
        return @fromBackingInt(@backingInt(r) -% 1);
    }
};

pub fn main() void {
    std.debug.print("@sizeOf(Rotation) = {d}, @bitSizeOf = {d}\n", .{ @sizeOf(Rotation), @bitSizeOf(Rotation) });

    var r: Rotation = .spawn;
    for (0..5) |_| {
        std.debug.print("{t}({d}) ", .{ r, @backingInt(r) });
        r = r.cw();
    }
    std.debug.print("\n", .{});
    for (0..5) |_| {
        std.debug.print("{t}({d}) ", .{ r, @backingInt(r) });
        r = r.ccw();
    }
    std.debug.print("\n", .{});

    // Wrapping operators on plain integers: they never trap.
    const top: u2 = 3;
    const bottom: u2 = 0;
    std.debug.print("3 +% 1 = {d}, 0 -% 1 = {d}, 3 +% 2 = {d}\n", .{ top +% 1, bottom -% 1, top +% 2 });
}
