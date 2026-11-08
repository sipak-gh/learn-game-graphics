//! Parsing a small text map into a grid of tiles, with errors for bad input.
const std = @import("std");

const Tile = enum { floor, wall };

const width = 5;
const height = 4;

const ParseError = error{ WrongSize, RaggedRows, UnknownTile };

fn parse(text: []const u8) ParseError![height][width]Tile {
    var grid: [height][width]Tile = undefined;
    var rows = std.mem.tokenizeScalar(u8, text, '\n');
    var y: usize = 0;
    while (rows.next()) |row| : (y += 1) {
        if (y == height) return error.WrongSize;
        if (row.len != width) return error.RaggedRows;
        for (row, &grid[y]) |char, *tile| {
            tile.* = switch (char) {
                '.' => .floor,
                '#' => .wall,
                else => return error.UnknownTile,
            };
        }
    }
    if (y != height) return error.WrongSize;
    return grid;
}

fn report(name: []const u8, text: []const u8) void {
    const grid = parse(text) catch |err| {
        std.debug.print("{s}: error.{t}\n", .{ name, err });
        return;
    };
    var walls: usize = 0;
    for (grid) |row| {
        for (row) |tile| walls += @intFromBool(tile == .wall);
    }
    std.debug.print("{s}: ok, {d} walls, grid[1][2] = .{t}\n", .{ name, walls, grid[1][2] });
}

pub fn main() void {
    report("good",
        \\#####
        \\#.#.#
        \\#...#
        \\#####
    );
    report("ragged", "#####\n#..#\n#...#\n#####");
    report("unknown", "#####\n#.x.#\n#...#\n#####");
    report("short", "#####\n#...#\n#####");
    // tokenizeScalar skips empty lines, so a trailing newline is harmless.
    report("trailing newline", "#####\n#...#\n#...#\n#####\n");
}
