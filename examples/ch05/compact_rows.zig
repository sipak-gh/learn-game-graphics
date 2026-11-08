//! Removing marked rows from an array in place, with two indices: `from`
//! reads every row, `to` writes the rows that are kept. Row 0 is the bottom.
const std = @import("std");

const rows = 6;

fn removeRows(grid: *[rows][]const u8, remove: std.bit_set.IntegerBitSet(rows)) void {
    var to: usize = 0;
    for (0..rows) |from| {
        if (remove.isSet(from)) continue;
        grid[to] = grid[from]; // to <= from, so nothing is overwritten unread
        to += 1;
    }
    // The top fills with empty rows.
    while (to < rows) : (to += 1) grid[to] = "....";
}

test "the rows above each removed row fall into the gap" {
    var grid: [rows][]const u8 = .{ "####", "#.##", "####", ".#..", "####", "...." };
    var remove: std.bit_set.IntegerBitSet(rows) = .empty;
    remove.set(0);
    remove.set(2);
    remove.set(4);
    removeRows(&grid, remove);
    const expected: [rows][]const u8 = .{ "#.##", ".#..", "....", "....", "....", "...." };
    for (expected, grid) |e, g| try std.testing.expectEqualStrings(e, g);
}

test "removing nothing changes nothing" {
    var grid: [rows][]const u8 = .{ "a...", "b...", "c...", "d...", "e...", "f..." };
    const before = grid;
    removeRows(&grid, .empty);
    for (before, grid) |b, g| try std.testing.expectEqualStrings(b, g);
}

test "removing every row empties the grid" {
    var grid: [rows][]const u8 = @splat("####");
    removeRows(&grid, .full);
    for (grid) |g| try std.testing.expectEqualStrings("....", g);
}
