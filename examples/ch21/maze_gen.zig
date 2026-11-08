//! Makes a maze in delve's map format and prints it. The maze is a grid
//! of W x H cells with walls between them: in the map, cells sit at odd
//! coordinates and walls at even ones, so the map is 2W+1 by 2H+1. A
//! recursive backtracker (depth-first search) carves a perfect maze, one
//! with exactly one path between any two cells. Then some walls are
//! knocked out to make loops, and some rectangles are cleared into rooms
//! with stone walls, pillars, a lamp, and barrels.
//!
//!   zig run examples/ch21/maze_gen.zig -- W H SEED [LOOPS] [ROOMS] > maze.txt
const std = @import("std");

const Grid = struct {
    width: usize, // in map tiles
    height: usize,
    tiles: []u8,

    fn at(g: Grid, x: usize, y: usize) *u8 {
        return &g.tiles[y * g.width + x];
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const number = struct {
        fn get(a: []const [:0]const u8, i: usize, default: usize) !usize {
            return if (a.len > i) try std.fmt.parseInt(usize, a[i], 10) else default;
        }
    }.get;
    const cells_x = try number(args, 1, 15);
    const cells_y = try number(args, 2, 8);
    const seed = try number(args, 3, 1);
    const loop_tries = try number(args, 4, cells_x * cells_y / 10);
    const room_count = try number(args, 5, 1);

    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();

    const g: Grid = .{ .width = 2 * cells_x + 1, .height = 2 * cells_y + 1, .tiles = undefined };
    const tiles = try arena.alloc(u8, g.width * g.height);
    var grid = g;
    grid.tiles = tiles;
    @memset(tiles, '#');

    // The recursive backtracker, with an explicit stack instead of
    // recursion: from the cell on top, go to a random unvisited neighbor
    // and knock out the wall between; at a dead end, back up.
    var stack: std.ArrayList([2]usize) = .empty;
    try stack.append(arena, .{ 0, 0 });
    grid.at(1, 1).* = '.';
    const steps = [4][2]isize{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
    while (stack.items.len > 0) {
        const cell = stack.items[stack.items.len - 1];
        var options: [4][2]usize = undefined;
        var count: usize = 0;
        for (steps) |d| {
            const nx = @as(isize, @intCast(cell[0])) + d[0];
            const ny = @as(isize, @intCast(cell[1])) + d[1];
            if (nx < 0 or ny < 0 or nx >= cells_x or ny >= cells_y) continue;
            const next: [2]usize = .{ @intCast(nx), @intCast(ny) };
            if (grid.at(2 * next[0] + 1, 2 * next[1] + 1).* == '#') {
                options[count] = next;
                count += 1;
            }
        }
        if (count == 0) {
            _ = stack.pop();
            continue;
        }
        const next = options[random.uintLessThan(usize, count)];
        grid.at(cell[0] + next[0] + 1, cell[1] + next[1] + 1).* = '.'; // the wall between
        grid.at(2 * next[0] + 1, 2 * next[1] + 1).* = '.';
        try stack.append(arena, next);
    }

    // Loops: a random wall between two cells, knocked out if it is still
    // there. Each one adds a second way around.
    for (0..loop_tries) |_| {
        const horizontal = random.boolean();
        const x = if (horizontal) 2 + 2 * random.uintLessThan(usize, cells_x - 1) else 1 + 2 * random.uintLessThan(usize, cells_x);
        const y = if (horizontal) 1 + 2 * random.uintLessThan(usize, cells_y) else 2 + 2 * random.uintLessThan(usize, cells_y - 1);
        grid.at(x, y).* = '.';
    }

    // Rooms: a rectangle of 3 to 5 cells each way, cleared inside. Its
    // outline turns to stone where it was a wall; where a corridor crossed
    // it, the opening stays as a door. Clearing never closes a path, so
    // the maze stays connected.
    for (0..room_count) |_| {
        if (cells_x < 7 or cells_y < 7) break;
        const w = 3 + random.uintLessThan(usize, 3);
        const h = 3 + random.uintLessThan(usize, 3);
        const left = 2 * (1 + random.uintLessThan(usize, cells_x - w - 1));
        const top = 2 * (1 + random.uintLessThan(usize, cells_y - h - 1));
        const right = left + 2 * w;
        const bottom = top + 2 * h;
        for (top..bottom + 1) |y| {
            for (left..right + 1) |x| {
                const edge = x == left or x == right or y == top or y == bottom;
                const tile = grid.at(x, y);
                if (!edge) tile.* = '.' else if (tile.* != '.') tile.* = '%';
            }
        }
        // Stone pillars every 4 tiles inside, a lamp in the middle, and a
        // pair of barrels in a corner.
        var y = top + 4;
        while (y + 4 <= bottom) : (y += 4) {
            var x = left + 4;
            while (x + 4 <= right) : (x += 4) grid.at(x, y).* = '%';
        }
        grid.at(left + w | 1, top + h | 1).* = '*';
        grid.at(right - 1, top + 1).* = 'o';
        grid.at(right - 2, top + 1).* = 'o';
    }

    // The outer wall is stone, and the player starts in the top-left
    // cell, facing an open side.
    for (0..g.height) |y| {
        for (0..g.width) |x| {
            if (x == 0 or y == 0 or x == g.width - 1 or y == g.height - 1) grid.at(x, y).* = '%';
        }
    }
    grid.at(1, 1).* = if (grid.at(2, 1).* != '#' and grid.at(2, 1).* != '%') '>' else 'v';

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    const out = &writer.interface;
    for (0..g.height) |y| {
        try out.writeAll(tiles[y * g.width ..][0..g.width]);
        try out.writeAll("\n");
    }
    try out.flush();
}
