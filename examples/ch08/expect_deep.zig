//! Comparing whole values in tests: expectEqual, expectEqualDeep, and
//! std.meta.eql. They differ on what they do with pointers and slices.
const std = @import("std");
const testing = std.testing;

const Board = struct { cells: [3][4]u8 };

const Replay = struct {
    seed: u64,
    script: []const u8,
};

test "arrays inside structs compare by value" {
    var a: Board = .{ .cells = @splat(@splat('.')) };
    var b = a; // a copy
    try testing.expectEqual(a, b);
    try testing.expect(std.meta.eql(a, b));
    b.cells[2][1] = '#';
    try testing.expect(!std.meta.eql(a, b));
    a.cells[2][1] = '#';
    try testing.expect(std.meta.eql(a, b));
}

test "slices: expectEqualDeep looks at the bytes" {
    var buf: [11]u8 = "left:3 drop".*;
    const a: Replay = .{ .seed = 7, .script = "left:3 drop" };
    const b: Replay = .{ .seed = 7, .script = &buf }; // same text, other memory
    try testing.expectEqualDeep(a, b);
    // std.meta.eql compares the slices' pointers, not their contents.
    try testing.expect(!std.meta.eql(a, b));
}

test "expectEqualDeep shows where two values differ" {
    const a: Replay = .{ .seed = 7, .script = "left:3 drop" };
    const b: Replay = .{ .seed = 8, .script = "left:3 drop" };
    try testing.expectError(error.TestExpectedEqual, testing.expectEqualDeep(a, b));
}
