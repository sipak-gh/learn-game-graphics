//! A five-piece preview queue, two ways. Shifting moves four items per
//! take; a ring buffer moves none but needs a start index and modulo math.
//! For five items the shift is simpler, and just as fast in practice.
const std = @import("std");

const n = 5;

const ShiftQueue = struct {
    items: [n]u8,

    fn take(q: *ShiftQueue, refill: u8) u8 {
        const first = q.items[0];
        // The ranges overlap; copyForwards copies from the front, which is
        // safe when the destination starts before the source.
        std.mem.copyForwards(u8, q.items[0 .. n - 1], q.items[1..]);
        q.items[n - 1] = refill;
        return first;
    }
};

const RingQueue = struct {
    items: [n]u8,
    start: usize = 0,

    fn take(q: *RingQueue, refill: u8) u8 {
        const first = q.items[q.start];
        q.items[q.start] = refill; // the old front slot becomes the back
        q.start = (q.start + 1) % n;
        return first;
    }

    /// The i-th upcoming item, for drawing the preview.
    fn peek(q: *const RingQueue, i: usize) u8 {
        return q.items[(q.start + i) % n];
    }
};

test "both queues deal in order and show the same preview" {
    var shift: ShiftQueue = .{ .items = "ABCDE".* };
    var ring: RingQueue = .{ .items = "ABCDE".* };
    const refills = "FGHIJKL";
    for (refills) |r| {
        try std.testing.expectEqual(shift.take(r), ring.take(r));
        for (0..n) |i| try std.testing.expectEqual(shift.items[i], ring.peek(i));
    }
    try std.testing.expectEqualStrings("HIJKL", &shift.items);
}

test "the preview of a shift queue is just the array" {
    var q: ShiftQueue = .{ .items = "STIZJ".* };
    try std.testing.expectEqual('S', q.take('L'));
    try std.testing.expectEqualStrings("TIZJL", &q.items);
}
