//! Building a table at compile time and keeping a slice of it. The index
//! list of a strip of quads (two triangles each) is filled in a `var` array
//! inside a comptime block; the finished array is copied into a `const`
//! before the slice is taken, so no comptime `var` escapes into the global.
const std = @import("std");

/// A row of `quads` squares has 2 * (quads + 1) vertices: bottom row
/// 0..quads, top row quads+1..2*quads+1.
fn stripIndices(comptime quads: u16) []const u16 {
    return comptime blk: {
        var indices: [quads * 6]u16 = undefined;
        for (0..quads) |q| {
            const b: u16 = @intCast(q); // bottom left
            const t: u16 = b + quads + 1; // top left
            indices[q * 6 ..][0..6].* = .{ b, b + 1, t + 1, b, t + 1, t };
        }
        const final = indices;
        break :blk &final;
    };
}

const strip = stripIndices(3);

pub fn main() void {
    std.debug.print("{d} indices, {d} triangles\n", .{ strip.len, strip.len / 3 });
    var i: usize = 0;
    while (i < strip.len) : (i += 3) std.debug.print("{any}\n", .{strip[i..][0..3].*});
}
