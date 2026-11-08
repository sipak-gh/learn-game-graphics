//! What the compiler is building for: @import("builtin") describes the
//! target and the optimize mode, at compile time.
const std = @import("std");
const builtin = @import("builtin");

pub fn main() void {
    const t = builtin.target;
    std.debug.print("arch {t}, os {t}, abi {t}\n", .{ t.cpu.arch, t.os.tag, t.abi });
    std.debug.print("pointer size {d} bytes, {t} endian\n", .{ @sizeOf(usize), t.cpu.arch.endian() });
    std.debug.print("optimize mode {t}\n", .{builtin.mode});
    // Comptime-known, so the other branch is not even compiled.
    const save_dir = if (t.os.tag == .windows) "%APPDATA%" else "$HOME/.local/share";
    std.debug.print("a save file would go under {s}\n", .{save_dir});
}
