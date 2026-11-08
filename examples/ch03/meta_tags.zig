//! Looping over every tag of an enum: `for` versus `inline for`.
const std = @import("std");

const Kind = enum { i, o, t, s, z, j, l };
const Cell = enum(u8) { empty, i, o, t, s, z, j, l, garbage };

/// The same name in another enum. `inline else` makes `k` comptime-known
/// in each prong, so @tagName(k) can pick a field.
fn cellOf(kind: Kind) Cell {
    return switch (kind) {
        inline else => |k| @field(Cell, @tagName(k)),
    };
}

pub fn main() void {
    // std.meta.tags returns a pointer to a comptime array of every tag.
    const all = std.meta.tags(Kind);
    std.debug.print("{d} kinds: {any}\n", .{ all.len, all.* });

    // A plain for loop runs at run time; `kind` is an ordinary value.
    for (all) |kind| {
        std.debug.print("{t}->{t} ", .{ kind, cellOf(kind) });
    }
    std.debug.print("\n", .{});

    // `inline for` unrolls the loop: each copy has a comptime-known `kind`,
    // so it can go where only comptime values are allowed, such as into a
    // format string, which must be known at compile time.
    inline for (comptime std.meta.tags(Kind)) |kind| {
        std.debug.print(@tagName(kind) ++ "! ", .{});
    }
    std.debug.print("\n", .{});
}
