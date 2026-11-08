//! What the player wants to do during one tick. The platform layer fills
//! it in from the keyboard; the game only ever sees this struct.

pub const Input = struct {
    /// -1 (backward) to 1 (forward).
    forward: f32 = 0,
    /// -1 (left) to 1 (right).
    strafe: f32 = 0,
    /// -1 (turn left) to 1 (turn right).
    turn: f32 = 0,
};

/// Both inputs at once, as if two sets of keys were held.
pub fn combine(a: Input, b: Input) Input {
    return .{
        .forward = @max(-1, @min(1, a.forward + b.forward)),
        .strafe = @max(-1, @min(1, a.strafe + b.strafe)),
        .turn = @max(-1, @min(1, a.turn + b.turn)),
    };
}
