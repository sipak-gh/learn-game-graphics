//! Reflection: turn a button name typed by a person into a struct field.
const std = @import("std");

const Input = packed struct {
    left: bool = false,
    right: bool = false,
    down: bool = false,
    cw: bool = false,
    ccw: bool = false,
};

/// Sets the field called `name`. The names exist only at compile time, so
/// `inline for` unrolls one comparison per field.
fn press(input: *Input, name: []const u8) bool {
    inline for (@typeInfo(Input).@"struct".field_names) |field| {
        if (std.mem.eql(u8, name, field)) {
            @field(input, field) = true;
            return true;
        }
    }
    return false;
}

pub fn main() void {
    const names = @typeInfo(Input).@"struct".field_names;
    std.debug.print("{d} fields:", .{names.len});
    for (names) |name| std.debug.print(" {s}", .{name});
    std.debug.print("\n", .{});

    var input: Input = .{};
    for ([_][]const u8{ "left", "cw", "jump" }) |name| {
        std.debug.print("press {s}: {}\n", .{ name, press(&input, name) });
    }
    std.debug.print("{any}\n", .{input});

    // A labelled continue skips to the next word from inside the inner loop.
    var unknown: u32 = 0;
    next_word: for ([_][]const u8{ "down", "up", "ccw", "fire" }) |word| {
        inline for (names) |field| {
            if (std.mem.eql(u8, word, field)) continue :next_word;
        }
        std.debug.print("not a button: {s}\n", .{word});
        unknown += 1;
    }
    std.debug.print("{d} unknown\n", .{unknown});
}
