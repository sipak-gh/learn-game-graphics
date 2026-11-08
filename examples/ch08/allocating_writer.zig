//! std.Io.Writer.Allocating: a writer that grows a buffer on the heap, for
//! output whose size you do not know in advance.
const std = @import("std");

/// Writes to any writer: a file, a fixed buffer, or a growing one.
fn writeSteps(w: *std.Io.Writer, n: usize) std.Io.Writer.Error!void {
    for (0..n) |i| {
        if (i > 0) try w.writeByte(' ');
        try w.print("left:{d}", .{i + 1});
    }
}

pub fn main(init: std.process.Init) !void {
    // A fixed buffer is fine while the output is small...
    var small: [32]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&small);
    try writeSteps(&fixed, 3);
    std.debug.print("fixed:      \"{s}\"\n", .{fixed.buffered()});
    // ...and fails once it is full.
    fixed = .fixed(&small);
    writeSteps(&fixed, 100) catch |err| std.debug.print("fixed:      {t} after {d} bytes\n", .{ err, fixed.buffered().len });

    // The allocating writer just grows.
    var out: std.Io.Writer.Allocating = .init(init.gpa);
    defer out.deinit();
    try writeSteps(&out.writer, 100);
    const text = out.written();
    std.debug.print("allocating: {d} bytes, ends with \"{s}\"\n", .{ text.len, text[text.len - 9 ..] });

    // Take the bytes away from the writer; now they are ours to free.
    const owned = try out.toOwnedSlice();
    defer init.gpa.free(owned);
    std.debug.print("owned:      {d} bytes; writer now holds {d}\n", .{ owned.len, out.written().len });
}
