//! Test blocks. `zig test tests.zig` compiles the file in test mode and
//! runs every `test` block; `zig run` and `zig build` skip them.
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const cols = 10;

/// Counts the filled cells in one row picture such as "##..#.....".
fn countFilled(line: []const u8) error{ WrongWidth, BadChar }!u32 {
    if (line.len != cols) return error.WrongWidth;
    var n: u32 = 0;
    for (line) |c| switch (c) {
        '.' => {},
        '#' => n += 1,
        else => return error.BadChar,
    };
    return n;
}

test "an empty row has no filled cells" {
    try expectEqual(0, try countFilled(".........."));
}

test "counts every #" {
    try expectEqual(3, try countFilled("##..#....."));
    try expectEqual(10, try countFilled("##########"));
}

test "rejects a row of the wrong width" {
    try expectError(error.WrongWidth, countFilled("###"));
    try expectError(error.WrongWidth, countFilled(""));
}

test "rejects unknown characters" {
    try expectError(error.BadChar, countFilled("#x........"));
}

test "a full row is full" {
    const full = try countFilled("##########") == cols;
    try expect(full);
}
