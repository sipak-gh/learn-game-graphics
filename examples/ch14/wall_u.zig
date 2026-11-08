//! Which column of a texture does a ray see? Rays hit each of the four
//! faces of the wall cell (5, 5) at three points: on the viewer's left,
//! in the middle, and on the viewer's right. After the flip, u always
//! grows from left to right as the viewer sees it, so nothing is mirrored.
const std = @import("std");

const Face = struct { name: []const u8, ray: [2]f32, hits: [3][2]f32, side_x: bool };

pub fn main() void {
    const faces = [_]Face{
        // Looking east at the west face (x = 5). The viewer's right is south (+y).
        .{ .name = "west  (looking east) ", .ray = .{ 1, 0 }, .side_x = true, .hits = .{ .{ 5, 5.2 }, .{ 5, 5.5 }, .{ 5, 5.8 } } },
        // Looking west at the east face (x = 6). The viewer's right is north (-y).
        .{ .name = "east  (looking west) ", .ray = .{ -1, 0 }, .side_x = true, .hits = .{ .{ 6, 5.8 }, .{ 6, 5.5 }, .{ 6, 5.2 } } },
        // Looking south at the north face (y = 5). The viewer's right is west (-x).
        .{ .name = "north (looking south)", .ray = .{ 0, 1 }, .side_x = false, .hits = .{ .{ 5.8, 5 }, .{ 5.5, 5 }, .{ 5.2, 5 } } },
        // Looking north at the south face (y = 6). The viewer's right is east (+x).
        .{ .name = "south (looking north)", .ray = .{ 0, -1 }, .side_x = false, .hits = .{ .{ 5.2, 6 }, .{ 5.5, 6 }, .{ 5.8, 6 } } },
    };
    std.debug.print("face                   left to right: wall_x -> u (texel column)\n", .{});
    for (faces) |f| {
        std.debug.print("{s} ", .{f.name});
        for (f.hits) |p| {
            const along = if (f.side_x) p[1] else p[0];
            const wall_x = along - @floor(along);
            const flip = (f.side_x and f.ray[0] < 0) or (!f.side_x and f.ray[1] > 0);
            const u = if (flip) 1 - wall_x else wall_x;
            const column: u32 = @intFromFloat(@floor(u * 64));
            std.debug.print("  {d:.1} -> {d:.1} ({d:>2})", .{ wall_x, u, column });
        }
        std.debug.print("\n", .{});
    }
}
