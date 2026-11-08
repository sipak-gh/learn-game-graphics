//! A struct saved as ZON and read back: a first run (no file), a normal
//! run, and two broken files. Writes and deletes zon-demo.zon in the
//! current directory.
const std = @import("std");

const Save = struct {
    high_score: u32 = 0,
    games: u32 = 0,
};

const path = "zon-demo.zon";

fn load(io: std.Io, gpa: std.mem.Allocator) Save {
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

fn store(io: std.Io, save: Save) !void {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.zon.stringify.serialize(save, .{}, &w);
    try w.writeByte('\n');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = w.buffered() });
}

fn show(label: []const u8, s: Save) void {
    std.debug.print("{s}: high_score={d} games={d}\n", .{ label, s.high_score, s.games });
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, path) catch {};

    show("first run", load(io, init.gpa));

    try store(io, .{ .high_score = 214, .games = 3 });
    var buf: [256]u8 = undefined;
    std.debug.print("file: {s}", .{try cwd.readFile(io, path, &buf)});
    show("loaded", load(io, init.gpa));

    // A file from an older version, before `games` existed: the default fills in.
    try cwd.writeFile(io, .{ .sub_path = path, .data = ".{ .high_score = 9 }\n" });
    show("old file", load(io, init.gpa));

    try cwd.writeFile(io, .{ .sub_path = path, .data = ".{ .high_score = \"lots\" }\n" });
    show("wrong type", load(io, init.gpa));

    try cwd.writeFile(io, .{ .sub_path = path, .data = ".{ .high_score = 9, .level = 3 }\n" });
    show("unknown field", load(io, init.gpa));

    try cwd.deleteFile(io, path);
}
