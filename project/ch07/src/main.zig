const std = @import("std");
const rl = @import("rl");
const core = @import("core");
const draw = @import("draw.zig");
const options = @import("options.zig");
const save = @import("save.zig");
const Sounds = @import("sound.zig").Sounds;
const Effects = @import("effects.zig").Effects;

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var bad: []const u8 = "";
    const opts = options.parse(args[1..], &bad) catch |err| {
        std.log.err("{t}: {s}", .{ err, bad });
        std.debug.print("{s}", .{options.usage});
        return 2;
    };
    if (opts.help) {
        std.debug.print("{s}", .{options.usage});
        return 0;
    }
    var script: ?core.Script = null;
    if (opts.script) |text| {
        core.Script.validate(text) catch |err| {
            std.log.err("--script: {t}", .{err});
            return 2;
        };
        script = .init(text);
    }

    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(draw.screen_width, draw.screen_height, "quadfall");
    defer rl.CloseWindow();
    // A scripted run (--frames) goes as fast as it can and pretends that
    // every frame took exactly 1/60 s, so it gives the same result every time.
    if (opts.frames == null) rl.SetTargetFPS(60);
    // Esc pauses the game instead of closing the window.
    rl.SetExitKey(rl.KEY_NULL);

    var sounds: Sounds = if (opts.mute) .{} else .init();
    defer sounds.deinit();
    var effects: Effects = .{};
    const save_path = opts.save orelse save.default_path;
    const saved = save.load(init.io, init.gpa, save_path);

    const seed = opts.seed orelse blk: {
        var bytes: [8]u8 = undefined;
        init.io.random(&bytes);
        break :blk std.mem.readInt(u64, &bytes, .little);
    };
    var app: core.App = .init(seed, saved.high_score);
    // Fixed timestep: the game always advances in ticks of exactly 1/60 s,
    // however long a frame took. `lag` is real time not yet simulated.
    const tick_seconds = 1.0 / @as(f64, core.game.ticks_per_second);
    var lag: f64 = 0;
    var frame: u32 = 0;
    while (!rl.WindowShouldClose()) : (frame += 1) {
        if (opts.frames) |n| if (frame == n) break;
        const frame_seconds: f64 = if (opts.frames != null) tick_seconds else rl.GetFrameTime();
        // After a long stall (a dragged window, a debugger), skip ahead
        // rather than run hundreds of ticks to catch up.
        lag += @min(frame_seconds, 0.25);
        while (lag >= tick_seconds) : (lag -= tick_seconds) {
            // The script was validated above, so next() cannot fail here.
            const input: core.Input = if (script) |*s| (s.next() catch unreachable) orelse .none else readKeyboard();
            const scene = app.scene;
            app.tick(input);
            effects.tick();
            effects.react(app.game.events);
            playSounds(&sounds, app.game.events);
            if (scene == .play and app.scene == .over and app.new_high_score) {
                save.store(init.io, save_path, .{ .high_score = app.high_score }) catch |err| {
                    std.log.warn("cannot save {s}: {t}", .{ save_path, err });
                };
            }
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(draw.background);
        draw.drawApp(&app, &effects);
    }

    if (opts.screenshot) |path| {
        rl.TakeScreenshot(path);
        std.log.info("saved {s}", .{path});
    }
    return 0;
}

/// The buttons held right now. Keys are a platform detail: the game only
/// ever sees `core.Input`.
fn readKeyboard() core.Input {
    return .{
        .left = rl.IsKeyDown(rl.KEY_LEFT),
        .right = rl.IsKeyDown(rl.KEY_RIGHT),
        .down = rl.IsKeyDown(rl.KEY_DOWN),
        .cw = rl.IsKeyDown(rl.KEY_UP) or rl.IsKeyDown(rl.KEY_X),
        .ccw = rl.IsKeyDown(rl.KEY_Z) or rl.IsKeyDown(rl.KEY_LEFT_CONTROL),
        .drop = rl.IsKeyDown(rl.KEY_SPACE),
        .hold = rl.IsKeyDown(rl.KEY_C) or rl.IsKeyDown(rl.KEY_LEFT_SHIFT),
        .start = rl.IsKeyDown(rl.KEY_ENTER),
        .pause = rl.IsKeyDown(rl.KEY_ESCAPE) or rl.IsKeyDown(rl.KEY_P),
    };
}

fn playSounds(sounds: *const Sounds, events: core.game.Events) void {
    if (events.game_over) sounds.play(.game_over) else if (events.level_up) sounds.play(.level_up) else if (events.cleared == 4) sounds.play(.four) else if (events.cleared > 0) sounds.play(.clear) else if (events.hard_drop) sounds.play(.drop) else if (events.locked) sounds.play(.lock);
    if (events.held) sounds.play(.hold);
    if (events.turned) sounds.play(.turn);
    if (events.moved) sounds.play(.move);
}
