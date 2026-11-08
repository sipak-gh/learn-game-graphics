//! A packed struct of bools: five buttons in one byte.
const std = @import("std");

const Input = packed struct {
    left: bool = false,
    right: bool = false,
    down: bool = false,
    cw: bool = false,
    ccw: bool = false,

    /// No buttons held. Used as a decl literal: `.none`.
    pub const none: Input = .{};
};

pub fn main() void {
    std.debug.print("@sizeOf = {d} byte, @bitSizeOf = {d} bits\n", .{ @sizeOf(Input), @bitSizeOf(Input) });
    std.debug.print("backing integer: {s}\n", .{@typeName(@typeInfo(Input).@"struct".backing_integer.?)});

    const a: Input = .{ .left = true, .cw = true };
    const b: Input = .{ .cw = true, .left = true };
    const c: Input = .none;

    // The first field is the lowest bit.
    const bits: u5 = @bitCast(a);
    std.debug.print("a as bits: 0b{b:0>5}\n", .{bits});
    std.debug.print("a == b: {}, a == none: {}, c == none: {}\n", .{ a == b, a == Input.none, c == Input.none });

    // Any 5-bit pattern is a valid Input.
    const all: Input = @bitCast(@as(u5, 0b11111));
    std.debug.print("all: {any}\n", .{all});
}
