//! Counts what it costs to draw a map as cubes (chapter 20) and as a built
//! world (chapter 21). Cubes: 12 triangles for every wall cell next to a
//! floor cell, plus a floor and a ceiling square (4 triangles) per floor
//! cell. World: per floor cell a floor and a ceiling square, plus one
//! square for each side of it that borders a wall.
//!
//!   zig run examples/ch21/count_faces.zig -- project/ch21/src/maps/labyrinth.txt
const std = @import("std");

fn isWall(c: u8) bool {
    return c == '#' or c == '%';
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const path = if (args.len > 1) args[1] else "project/ch21/src/maps/cellar.txt";
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.arena.allocator(), .limited(1 << 20));

    var rows: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| try rows.append(init.arena.allocator(), line);
    const height = rows.items.len;
    const width = rows.items[0].len;

    // Outside the map counts as wall, as in delve's Map.at.
    const at = struct {
        fn wall(r: []const []const u8, x: isize, y: isize) bool {
            if (x < 0 or y < 0 or y >= r.len or x >= r[0].len) return true;
            return isWall(r[@intCast(y)][@intCast(x)]);
        }
    }.wall;
    const sides = [_][2]isize{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };

    var floor_cells: usize = 0;
    var wall_cells: usize = 0;
    var wall_cubes: usize = 0; // wall cells next to a floor cell
    var wall_sides: usize = 0; // floor-cell sides that border a wall
    for (0..height) |yu| {
        for (0..width) |xu| {
            const x: isize = @intCast(xu);
            const y: isize = @intCast(yu);
            if (at(rows.items, x, y)) {
                wall_cells += 1;
                for (sides) |d| {
                    if (!at(rows.items, x + d[0], y + d[1])) {
                        wall_cubes += 1;
                        break;
                    }
                }
            } else {
                floor_cells += 1;
                for (sides) |d| {
                    if (at(rows.items, x + d[0], y + d[1])) wall_sides += 1;
                }
            }
        }
    }
    const cube_triangles = 12 * wall_cubes + 4 * floor_cells;
    const world_triangles = 2 * (2 * floor_cells + wall_sides);
    std.debug.print("{s}: {d}x{d}\n", .{ path, width, height });
    std.debug.print("floor cells       {d:>6}\n", .{floor_cells});
    std.debug.print("wall cells        {d:>6} ({d} next to floor)\n", .{ wall_cells, wall_cubes });
    std.debug.print("wall sides        {d:>6}\n", .{wall_sides});
    std.debug.print("cube triangles    {d:>6} (12 x {d} + 4 x {d})\n", .{ cube_triangles, wall_cubes, floor_cells });
    std.debug.print("world triangles   {d:>6} (2 x (2 x {d} + {d}))\n", .{ world_triangles, floor_cells, wall_sides });
    const saved = 100 * @as(f32, @floatFromInt(cube_triangles - world_triangles)) / @as(f32, @floatFromInt(cube_triangles));
    std.debug.print("saved             {d:>5.0}%\n", .{saved});
}
