//! Playing a synthesized sound with raylib, and carrying on without one
//! when there is no audio device.
const std = @import("std");
const rl = @import("rl");
const Demo = @import("demo").Demo;

const sample_rate = 22050;

pub fn main(init: std.process.Init) !void {
    var demo: Demo = .init(try init.minimal.args.toSlice(init.arena.allocator()));
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.InitWindow(320, 180, "beep");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    rl.InitAudioDevice();
    const audio = rl.IsAudioDeviceReady();
    defer if (audio) rl.CloseAudioDevice();
    std.debug.print("audio device ready: {}\n", .{audio});

    // A quarter second of 440 Hz square wave, fading out.
    var samples: [sample_rate / 4]i16 = undefined;
    for (&samples, 0..) |*s, i| {
        const fade = 1 - @as(f32, @floatFromInt(i)) / samples.len;
        // Two half-cycles per cycle: the level flips 880 times a second.
        const high = (i * 2 * 440 / sample_rate) % 2 == 0;
        s.* = @intFromFloat((if (high) @as(f32, 0.2) else -0.2) * fade * std.math.maxInt(i16));
    }
    const sound: ?rl.Sound = if (audio) rl.LoadSoundFromWave(.{
        .frameCount = samples.len,
        .sampleRate = sample_rate,
        .sampleSize = 16,
        .channels = 1,
        .data = &samples,
    }) else null;
    defer if (sound) |s| rl.UnloadSound(s);

    if (sound) |s| rl.PlaySound(s);
    while (demo.running()) {
        if (demo.frame == 2) {
            const playing = if (sound) |s| rl.IsSoundPlaying(s) else false;
            std.debug.print("frame 2: playing {}\n", .{playing});
        }
        rl.BeginDrawing();
        defer rl.EndDrawing();
        rl.ClearBackground(rl.DARKBLUE);
        rl.DrawText(if (audio) "beep" else "no sound", 20, 20, 30, rl.RAYWHITE);
    }
    std.debug.print("done after {d} frames\n", .{demo.frame});
}
