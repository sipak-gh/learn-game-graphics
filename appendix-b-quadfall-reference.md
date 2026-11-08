# Appendix B — quadfall Reference

This appendix documents the finished `quadfall` from Part I, the snapshot in
[`project/ch08/`](project/ch08/). It covers how to build and run it, the controls and
command-line options, the rules with every number the game uses, the file formats, and a map
from each concept to the file that implements it. The chapters explain why each of these
works the way it does; this appendix is the place to look up what they are.

Previous: [Appendix A — Cheat Sheet](appendix-a-cheatsheet.md). Next:
[Appendix C — delve Reference](appendix-c-delve-reference.md).

## Build, run, test

```console
$ cd project/ch08
$ zig build run                          # play
$ zig build run -- --seed 7              # arguments after -- go to quadfall
$ zig build test --summary all           # 37/37 tests (35 core + 2 options)
$ zig build release                      # ReleaseSafe games for Linux and Windows
$ ./zig-out/bin/quadfall --help
```

`zig build release` writes `zig-out/release/x86_64-linux/quadfall` and
`zig-out/release/x86_64-windows/quadfall.exe`. The course cross-compiled the Windows
executable but never ran it.

To play without a screen, use a virtual X server. `--frames` makes the run reproducible
([Chapter 1](01-getting-started.md)):

```console
$ xvfb-run -a -s "-screen 0 1280x720x24" ./zig-out/bin/quadfall --frames 400 --seed 7 --mute --screenshot shot.png
```

## Controls

| Key | Button (`core.Input` field) | Does |
|---|---|---|
| ← / → | `left` / `right` | move one column. Holding a key repeats the move: wait 10 ticks, then move every 2 ticks (DAS/ARR) |
| ↓ | `down` | soft drop: fall 20× faster, 1 point per row |
| Space | `drop` | hard drop: fall all the way and lock now, 2 points per row |
| ↑ or X | `cw` | turn clockwise |
| Z or Left Ctrl | `ccw` | turn counter-clockwise |
| C or Left Shift | `hold` | put the piece aside or swap with the held one (once per piece) |
| Enter | `start` | start a game (title, game over); resume (pause) |
| Esc or P | `pause` | pause and resume (`SetExitKey(KEY_NULL)`, so Esc does not quit) |

Close the window to quit. All the buttons except `left`, `right` and `down` act on the press,
not while held.

## Command-line options

```text
usage: quadfall [OPTIONS]

options:
  --frames N         run N frames with a fixed 1/60 s frame time, then exit
  --screenshot PATH  save the last frame as a PNG before exiting
  --script STEPS     play scripted input instead of the keyboard
  --seed N           deal pieces from seed N instead of a random seed
  --save PATH        keep the high score in PATH (default: quadfall-save.zon)
  --mute             play no sound
  --record PATH      save the seed and every input to PATH on exit
  --replay PATH      play a recorded session from PATH
  --help             show this help
```

| Option | Since | Notes |
|---|---|---|
| `--frames N` | ch01 | skips `SetTargetFPS`; every frame counts as exactly 1/60 s, so the same N gives the same picture |
| `--screenshot PATH` | ch01 | raylib's `TakeScreenshot` after the last frame; logs `info: saved PATH` |
| `--script STEPS` | ch04 | see [Script language](#script-language) |
| `--seed N` | ch06 | fixes the 7-bag; each new game in one run takes the next seed |
| `--save PATH`, `--mute` | ch07 | the high score file; no audio device needed |
| `--record PATH`, `--replay PATH` | ch08 | see [Files](#files); `--replay` cannot be combined with `--script` or `--seed` |

Errors and exit codes:
- `0` means a normal exit.
- `1` means a runtime error: a replay that cannot be read, or a record file that cannot be
  written.
- `2` means a usage error. The program logs `error: UnknownOption: --x` (or `MissingValue`,
  `InvalidValue`, `Conflict`) and prints the usage.
- A script that does not parse gives `error: --script: UnknownButton` (or `BadCount`), also
  with exit code 2.

## Script language

Scripts drive the game in tests, screenshots and replays. A script is a list of steps
separated by spaces ([Chapter 4](04-input-and-movement.md)):

| Step | Meaning |
|---|---|
| `left` | hold Left for 1 tick |
| `left:20` | hold Left for 20 ticks |
| `left*3` | tap Left three times (one tick down, one tick up, each) |
| `right+cw:2` | hold Right and turn-clockwise together for 2 ticks |
| `_:30` | hold nothing for 30 ticks |

Button names are the field names of `core.Input`: `left`, `right`, `down`, `cw`, `ccw`, `drop`,
`hold`, `start`, `pause`. When the script ends, the input is `none`. For example,
`start _:10 left*3 cw drop` starts a game, waits, moves the first piece three columns left,
turns it and hard-drops it.

## Rules

### The board and the pieces

- The board is 10 columns by 22 rows: 20 visible and 2 hidden above them. Row 0 is the
  bottom row, and rows count upward.
- There are seven pieces, `i o t s z j l`. Each turns in a square box: 4×4 for I, 2×2 for O,
  3×3 for the rest. The rotation states are `spawn`, `right`, `flip`, `left`.
- A piece spawns centered, rounding to the left (column 3, or 4 for O), with its top row in
  the first hidden row.
- Turning uses the Super Rotation System. The game tries the five kicks of `jlstz_kicks` (or
  `i_kicks` for I) in order and keeps the first one that fits. O does not kick.

### Randomizer, preview, hold

- **7-bag:** each bag holds all seven pieces, shuffled. The shuffle uses
  `std.Random.DefaultPrng` (Xoshiro256) and `shuffleWithIndex(Kind, &kinds, u32)`, so a seed
  deals the same pieces on 32-bit and 64-bit machines. The game never deals more than 12
  pieces between two of the same kind.
- **Preview:** the next 5 pieces.
- **Hold:** once per piece. Holding swaps the current piece with the held one, which then
  spawns fresh. If nothing is held yet, the next piece from the queue spawns instead. Hold is
  allowed again after the piece locks.

### Time, gravity, locking

- The game ticks 60 times a second. One tick is one call of `Game.tick(input)`. The platform
  runs as many ticks per frame as real time asks for (a fixed timestep with a `lag`
  accumulator, capped at 0.25 s per frame).
- **Gravity** is fixed point: `one_row = 1 << 16` per row. The game adds `gravityAt(level)`
  to `fall` each tick, and the piece drops one row for every whole `one_row`. A table built at
  compile time follows the guideline curve, (0.8 − (L−1)·0.007)^(L−1) seconds per row,
  rounded up, and is capped at 20 rows per tick ("20G"):

  | Level | 1 | 2 | 3 | 5 | 8 | 10 | 13 | 15 | 19–20 |
  |---|---|---|---|---|---|---|---|---|---|
  | `gravity_table` | 1093 | 1378 | 1769 | 3076 | 8107 | 17027 | 60169 | 154743 | 1310720 |
  | ticks per row | 60 | 47.6 | 37.0 | 21.3 | 8.1 | 3.8 | 1.1 | 0.42 | 0.05 (20G) |

  Levels above 20 use level 20's gravity.
- **Soft drop:** gravity × 20 while ↓ is held.
- **Lock delay:** a piece resting on the stack locks after 30 ticks. A move or turn restarts
  the delay, at most 15 times; the count starts again whenever the piece reaches a new lowest
  row. Falling a row also restarts it.
- **Line clear:** full rows flash for 20 ticks, then they are removed and the next piece
  spawns.
- **Game over** happens in two ways. Either a piece locks entirely in the hidden rows, or a
  new piece does not fit where it spawns.

### Scoring and levels

| Event | Points |
|---|---|
| 1 / 2 / 3 / 4 rows at once | 100 / 300 / 500 / 800 × level |
| soft drop | 1 per row fallen while ↓ is held |
| hard drop | 2 per row |

`level = 1 + lines / 10`, so the level goes up every 10 lines. The high score is saved when a
game beats it.

### Scenes

`core.App` holds the scene: `title` → (Enter) → `play` ⇄ (Esc/P, or Enter to resume) `pause`;
`play` → (the stack reaches the top) → `over` → (Enter) → `play` with the next seed. While
paused, the board is hidden. `over` shows `NEW HIGH SCORE!` when it applies.

### Events

Each tick, `Game` records what happened in `Events`. Effects and sounds react to them, and
the rules never wait for them:

```zig
pub const Events = packed struct {
    moved: bool = false,
    turned: bool = false,
    held: bool = false,
    hard_drop: bool = false,
    locked: bool = false,
    /// Rows cleared by the lock, 0 to 4.
    cleared: u3 = 0,
    level_up: bool = false,
    game_over: bool = false,
};
```

There are sounds for `move turn hold drop lock clear four level_up game_over`: square waves
generated at startup, with no sound files. The screen shakes for 8 ticks after a hard
drop and for 20 after a four-row clear. A banner announces a level up for 90 ticks.

## Screen

The window is 800×720. The well is 320×640 at (240, 40), with 32-pixel cells. HOLD, SCORE,
LEVEL and LINES are on the left; NEXT is on the right. A ghost outline shows where the piece
would land. The piece colors are I cyan, O yellow, T purple, S green, Z red, J blue and
L orange.

## Files

- **Save** (`quadfall-save.zon` in the working directory, or `--save PATH`):
  ```zig
  .{ .high_score = 214 }
  ```
  A missing file counts as a first run. A broken file is reported, using the ZON parser's
  diagnostics, and ignored.
- **Replay** (`--record PATH`, `--replay PATH`): the seed plus every tick's input, written in
  the script language. Because the core is deterministic, this is enough to play a whole
  session again:
  ```zig
  .{ .seed = 7, .script = "_:30 start hold left _ left _ left _ drop _ right _ right _ right _ drop ..." }
  ```
  Replaying a recording gives the same frames, pixel for pixel: `cmp` finds no difference
  between the live screenshot and the replayed one ([Chapter 8](08-organizing-a-game.md)).

## Architecture

Two layers. The **core** (`src/core/`) is the game's rules. It does not import raylib, so its
tests run without a window. The **platform** (`src/*.zig`) reads keys, plays sounds, and
draws. `build.zig` enforces the boundary: the core module has no `rl` import, so using raylib
in the core is a compile error.

```text
build.zig            addGame(target, optimize); run, test, release steps
build.zig.zon        raylib 6.2, pinned to its commit
src/main.zig         platform: options → app loop (fixed timestep) → draw; keyboard → core.Input
src/options.zig      command-line parsing (plain Zig, tested)
src/draw.zig         all raylib drawing: board, pieces, ghost, panels, HUD, scenes
src/effects.zig      juice: screen shake and level banner, reacting to core events
src/sound.zig        procedural square-wave sounds; silent without an audio device
src/save.zig         high score as ZON (quadfall-save.zon)
src/replay.zig       replay files as ZON: seed + recorded script
src/core/root.zig    the core module's public surface (no raylib)
src/core/board.zig   Board, Cell, Pos, fits, fullRows/removeRows, parse/format
src/core/piece.zig   Kind, Rotation, comptime shape tables, SRS kick tables, Piece
src/core/input.zig   Input (packed struct of buttons), AutoRepeat (DAS/ARR)
src/core/script.zig  Script (scripted input) and Recorder (the inverse)
src/core/bag.zig     7-bag randomizer over std.Random.DefaultPrng
src/core/game.zig    Game: gravity, lock delay, hold, drop, clears, scoring, levels, events
src/core/app.zig     App: scenes title/play/pause/over, high score, seeds per game
```

`project/ch08/` has 2138 lines of Zig: 2060 in `src/` and 78 in `build.zig`.
The snapshots grow chapter by chapter:

| Snapshot | Lines in `src/` | Tests | Adds |
|---|---|---|---|
| [`ch01`](project/ch01/) | 127 | — | window, game loop, `--frames`/`--screenshot` |
| [`ch02`](project/ch02/) | 327 | 5 | the core module, `Board`, drawing cells |
| [`ch03`](project/ch03/) | 558 | 9 | pieces, comptime shape tables, rotation |
| [`ch04`](project/ch04/) | 979 | 19 | `Input`, scripts, `Game`, SRS kicks, DAS/ARR |
| [`ch05`](project/ch05/) | 1240 | 26 | gravity, lock delay, line clears, game over |
| [`ch06`](project/ch06/) | 1477 | 31 | 7-bag, preview, hold, score, levels, gravity table |
| [`ch07`](project/ch07/) | 1886 | 33 | scenes, events, effects, sounds, high score |
| [`ch08`](project/ch08/) | 2060 | 37 | record/replay, golden test, release builds |

## Concept → code

| Concept | Chapter | Where |
|---|---|---|
| game loop, headless runs | [1](01-getting-started.md) | `main.zig` |
| board as data, `format`/`parse`, core module | [2](02-the-board.md) | `core/board.zig`, `build.zig` |
| comptime shape tables, rotation | [3](03-tetrominoes.md) | `core/piece.zig` `shapes` |
| input as data, scripts, SRS | [4](04-input-and-movement.md) | `core/input.zig`, `core/script.zig`, `core/piece.zig` `jlstz_kicks`, `i_kicks` |
| DAS/ARR | [4](04-input-and-movement.md) | `core/input.zig` `AutoRepeat` |
| fixed timestep | [5](05-time.md) | `main.zig` loop (`lag`) |
| fixed-point gravity, lock delay | [5](05-time.md), [6](06-rules-and-progression.md) | `core/game.zig` `one_row`, `gravity_table`, `lock_timer`, `lock_resets`, `lowest` |
| 7-bag | [6](06-rules-and-progression.md) | `core/bag.zig` |
| scenes | [7](07-scenes-and-ui.md) | `core/app.zig` |
| events and juice | [7](07-scenes-and-ui.md) | `core/game.zig` `Events`, `effects.zig`, `sound.zig` |
| persistence | [7](07-scenes-and-ui.md) | `save.zig` |
| replays, golden test | [8](08-organizing-a-game.md) | `core/script.zig` `Recorder`, `replay.zig`, `core/app.zig` tests |
| module boundary, release builds | [8](08-organizing-a-game.md) | `build.zig` |

---

Sources for this appendix: [REFERENCES.md](REFERENCES.md#primary-references)
