//! The maze: a grid of square cells, each one unit wide. Cell (x, y)
//! covers the square from (x, y) to (x + 1, y + 1); y grows downward on
//! the map, like rows of text.
const std = @import("std");
const math = @import("math.zig");
const Vec2 = math.Vec2;

pub const Tile = enum {
    floor,
    brick,
    stone,

    pub fn isWall(tile: Tile) bool {
        return tile != .floor;
    }
};

/// Things that stand in the maze without filling a cell. The ray caster
/// draws them as sprites.
pub const Thing = enum { lamp, barrel };

pub const Sprite = struct {
    pos: Vec2,
    thing: Thing,
};

pub const Map = struct {
    width: usize,
    height: usize,
    tiles: []Tile,
    sprites: []Sprite,
    /// Where the player starts: a cell center, and an angle in radians.
    start: Vec2,
    start_yaw: f32,

    pub const ParseError = error{ RaggedRows, UnknownTile, NoStart, TwoStarts, Empty } || std.mem.Allocator.Error;

    /// Parses a map drawn as text, one row per line:
    /// `#` brick wall, `%` stone wall, `.` floor, `*` a lamp, `o` a barrel,
    /// and one of `>` `v` `<` `^` for the player start, pointing east,
    /// south, west, or north.
    pub fn parse(gpa: std.mem.Allocator, text: []const u8) ParseError!Map {
        var width: usize = 0;
        var height: usize = 0;
        var rows = std.mem.tokenizeScalar(u8, text, '\n');
        while (rows.next()) |row| : (height += 1) {
            if (height == 0) width = row.len;
            if (row.len != width) return error.RaggedRows;
        }
        if (width == 0) return error.Empty;

        const tiles = try gpa.alloc(Tile, width * height);
        errdefer gpa.free(tiles);
        var sprites: std.ArrayList(Sprite) = .empty;
        defer sprites.deinit(gpa);
        var start: ?Vec2 = null;
        var start_yaw: f32 = 0;

        rows.reset();
        var y: usize = 0;
        while (rows.next()) |row| : (y += 1) {
            for (row, 0..) |char, x| {
                const center: Vec2 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5 };
                tiles[y * width + x] = switch (char) {
                    '.' => .floor,
                    '*', 'o' => blk: {
                        try sprites.append(gpa, .{ .pos = center, .thing = if (char == '*') .lamp else .barrel });
                        break :blk .floor;
                    },
                    '#' => .brick,
                    '%' => .stone,
                    '>', 'v', '<', '^' => blk: {
                        if (start != null) return error.TwoStarts;
                        start = center;
                        // Angles turn from east (+x) toward south (+y).
                        const quarter = std.math.pi / 2.0;
                        start_yaw = switch (char) {
                            '>' => 0,
                            'v' => quarter,
                            '<' => 2 * quarter,
                            else => 3 * quarter,
                        };
                        break :blk .floor;
                    },
                    else => return error.UnknownTile,
                };
            }
        }
        return .{
            .width = width,
            .height = height,
            .tiles = tiles,
            .start = start orelse return error.NoStart,
            .start_yaw = start_yaw,
            .sprites = try sprites.toOwnedSlice(gpa),
        };
    }

    pub fn deinit(map: *Map, gpa: std.mem.Allocator) void {
        gpa.free(map.tiles);
        gpa.free(map.sprites);
        map.* = undefined;
    }

    /// The tile at cell (x, y). Everything outside the map is solid brick,
    /// so nothing can walk or look out of it.
    pub fn at(map: Map, x: i32, y: i32) Tile {
        if (x < 0 or y < 0 or x >= map.width or y >= map.height) return .brick;
        return map.tiles[@as(usize, @intCast(y)) * map.width + @as(usize, @intCast(x))];
    }

    /// True if point `p` is inside a wall cell.
    pub fn isWallAt(map: Map, p: Vec2) bool {
        const cell = @floor(p);
        return map.at(@intFromFloat(cell[0]), @intFromFloat(cell[1])).isWall();
    }
};

test "parse a small map" {
    const gpa = std.testing.allocator;
    var map = try Map.parse(gpa,
        \\####
        \\#v*%
        \\####
    );
    defer map.deinit(gpa);
    try std.testing.expectEqual(4, map.width);
    try std.testing.expectEqual(3, map.height);
    try std.testing.expectEqual(.stone, map.at(3, 1));
    try std.testing.expectEqual(.floor, map.at(1, 1));
    try std.testing.expectEqual(.brick, map.at(-1, 1)); // outside
    try std.testing.expect(math.approxEq(map.start, Vec2{ 1.5, 1.5 }));
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, map.start_yaw, 1e-6);
    try std.testing.expect(map.isWallAt(.{ 0.9, 1.5 }));
    try std.testing.expect(!map.isWallAt(.{ 2.9, 1.5 }));
    try std.testing.expectEqual(1, map.sprites.len);
    try std.testing.expectEqual(.lamp, map.sprites[0].thing);
    try std.testing.expectEqual(Vec2{ 2.5, 1.5 }, map.sprites[0].pos);
}

test "parse errors" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.RaggedRows, Map.parse(gpa, "###\n#>\n###"));
    try std.testing.expectError(error.UnknownTile, Map.parse(gpa, "#?>#"));
    try std.testing.expectError(error.NoStart, Map.parse(gpa, "####"));
    try std.testing.expectError(error.TwoStarts, Map.parse(gpa, "#>>#"));
}
