//! Run-length encoding: a stream of values becomes (value, count) runs,
//! and decoding the runs gives the stream back. The replay recorder uses
//! the same idea on one Input per tick.
const std = @import("std");

const Run = struct { value: u8, count: u32 };

/// Encodes `values` into `out`; returns the runs written.
fn encode(values: []const u8, out: []Run) []Run {
    var n: usize = 0;
    for (values) |v| {
        if (n > 0 and out[n - 1].value == v) {
            out[n - 1].count += 1;
        } else {
            out[n] = .{ .value = v, .count = 1 };
            n += 1;
        }
    }
    return out[0..n];
}

fn decode(runs: []const Run, out: []u8) []u8 {
    var n: usize = 0;
    for (runs) |r| {
        @memset(out[n..][0..r.count], r.value);
        n += r.count;
    }
    return out[0..n];
}

test "repeats become one run" {
    var runs: [16]Run = undefined;
    const got = encode("___LLc__", &runs);
    try std.testing.expectEqual(4, got.len);
    try std.testing.expectEqual(Run{ .value = '_', .count = 3 }, got[0]);
    try std.testing.expectEqual(Run{ .value = 'L', .count = 2 }, got[1]);
    try std.testing.expectEqual(Run{ .value = 'c', .count = 1 }, got[2]);
    try std.testing.expectEqual(Run{ .value = '_', .count = 2 }, got[3]);
}

test "decoding gives the stream back" {
    // 300 ticks of nothing, Left for 4, nothing for 60, then a drop.
    var stream: [365]u8 = undefined;
    @memset(stream[0..300], '_');
    @memset(stream[300..304], 'L');
    @memset(stream[304..364], '_');
    stream[364] = 'd';
    var runs: [16]Run = undefined;
    var back: [stream.len]u8 = undefined;
    const encoded = encode(&stream, &runs);
    try std.testing.expectEqual(4, encoded.len); // 365 values, 4 runs
    try std.testing.expectEqualStrings(&stream, decode(encoded, &back));
}

test "a stream that never repeats does not shrink" {
    var runs: [16]Run = undefined;
    try std.testing.expectEqual(6, encode("LRLRLR", &runs).len);
}
