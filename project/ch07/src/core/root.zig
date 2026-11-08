//! The game logic of quadfall. Nothing under src/core/ may use raylib: this
//! module is built without the "rl" import, so the compiler enforces it.

pub const board = @import("board.zig");
pub const Board = board.Board;
pub const Cell = board.Cell;
pub const Pos = board.Pos;
pub const piece = @import("piece.zig");
pub const Kind = piece.Kind;
pub const Rotation = piece.Rotation;
pub const Piece = piece.Piece;
pub const Bag = @import("bag.zig").Bag;
pub const input = @import("input.zig");
pub const Input = input.Input;
pub const script = @import("script.zig");
pub const Script = script.Script;
pub const game = @import("game.zig");
pub const Game = game.Game;
pub const app = @import("app.zig");
pub const App = app.App;

test {
    @import("std").testing.refAllDecls(@This());
}
