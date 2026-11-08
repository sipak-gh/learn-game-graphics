//! Replay files: a seed and every tick's input, as ZON. Because the core is
//! deterministic, that is all it takes to play a whole session again.
const std = @import("std");

pub const Replay = struct {
    seed: u64,
    /// The inputs, in the script language of core/script.zig.
    script: []const u8,
};

/// Reads a replay. Its script is allocated in `arena`.
pub fn load(io: std.Io, gpa: std.mem.Allocator, arena: std.mem.Allocator, path: []const u8) !Replay {
    const source = try std.Io.Dir.cwd().readFileAllocOptions(io, path, gpa, .limited(16 << 20), .of(u8), 0);
    defer gpa.free(source);
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(Replay, .{
        .gpa = gpa,
        .arena = arena,
        .source = source,
        .diagnostics = &diagnostics,
    }) catch |err| {
        if (err == error.ParseZon) diagnostics.log(path);
        return err;
    };
}

pub fn store(io: std.Io, gpa: std.mem.Allocator, path: []const u8, replay: Replay) !void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.zon.stringify.serialize(replay, .{}, &out.writer);
    try out.writer.writeByte('\n');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.written() });
}
