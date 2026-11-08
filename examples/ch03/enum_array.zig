//! std.enums.EnumArray: a fixed-size array indexed by an enum instead of a number.
const std = @import("std");

const Kind = enum { i, o, t, s, z, j, l };

pub fn main() void {
    // init takes a struct with one field per tag, so none can be forgotten.
    var box_size: std.enums.EnumArray(Kind, u8) = .init(.{
        .i = 4,
        .o = 2,
        .t = 3,
        .s = 3,
        .z = 3,
        .j = 3,
        .l = 3,
    });
    std.debug.print("len {d}, {d} bytes\n", .{ @TypeOf(box_size).len, @sizeOf(@TypeOf(box_size)) });
    std.debug.print("get(.i) = {d}, get(.o) = {d}\n", .{ box_size.get(.i), box_size.get(.o) });

    // getPtr gives a pointer into the array; set does the same in one call.
    box_size.getPtr(.o).* += 1;
    box_size.set(.t, 9);
    std.debug.print("after: o = {d}, t = {d}\n", .{ box_size.get(.o), box_size.get(.t) });

    // The iterator yields entries in declaration order: a key and a value pointer.
    var it = box_size.iterator();
    while (it.next()) |entry| {
        std.debug.print("{t}={d} ", .{ entry.key, entry.value.* });
    }
    std.debug.print("\n", .{});

    // initFill sets every slot to one value.
    const zeros: std.enums.EnumArray(Kind, u8) = .initFill(0);
    std.debug.print("values: {any}\n", .{zeros.values});
}
