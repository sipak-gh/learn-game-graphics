//! The high score, kept between runs in a small ZON file.
const std = @import("std");

pub const default_path = "quadfall-save.zon";

pub const Save = struct {
    high_score: u32 = 0,
};

/// Reads the save file. A missing file is a first run; a broken one is
/// reported and ignored. Either way the game can start.
pub fn load(io: std.Io, gpa: std.mem.Allocator, path: []const u8) Save {
    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, gpa, .limited(4096), .of(u8), 0) catch |err| {
        if (err != error.FileNotFound) std.log.warn("cannot read {s}: {t}", .{ path, err });
        return .{};
    };
    defer gpa.free(source);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(Save, .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .source = source,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.OutOfMemory => .{},
        error.ParseZon => {
            diagnostics.log(path);
            return .{};
        },
    };
}

pub fn store(io: std.Io, path: []const u8, save: Save) !void {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.zon.stringify.serialize(save, .{}, &w);
    try w.writeByte('\n');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = w.buffered() });
}
