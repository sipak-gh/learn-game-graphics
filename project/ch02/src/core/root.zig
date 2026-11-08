//! The game logic of quadfall. Nothing under src/core/ may use raylib: this
//! module is built without the "rl" import, so the compiler enforces it.

pub const board = @import("board.zig");
pub const Board = board.Board;
pub const Cell = board.Cell;
pub const Pos = board.Pos;

test {
    @import("std").testing.refAllDecls(@This());
}
