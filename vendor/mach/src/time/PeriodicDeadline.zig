const std = @import("std");

const PeriodicDeadline = @This();

deadline: ?std.Io.Timestamp = null,
target: u32 = 0,

/// Returns the next periodic deadline. Calls made before the deadline do not advance it.
pub fn next(p: *PeriodicDeadline, io: std.Io, target_frequency: u32) ?std.Io.Clock.Timestamp {
    const period_ns: i96 = if (target_frequency == 0) 0 else @intCast(std.time.ns_per_s / target_frequency);
    if (period_ns == 0) {
        p.* = .{ .target = target_frequency };
        return null;
    }

    if (p.target != target_frequency) p.* = .{ .target = target_frequency };

    const now = std.Io.Timestamp.now(io, .awake);
    var deadline = p.deadline orelse now;
    if (deadline.nanoseconds > now.nanoseconds) return deadline.withClock(.awake);

    const periods = @divFloor(
        now.nanoseconds - deadline.nanoseconds,
        period_ns,
    ) + 1;
    deadline.nanoseconds += periods * period_ns;
    p.deadline = deadline;
    return deadline.withClock(.awake);
}

test "calls before the deadline preserve it" {
    const io = std.testing.io;
    const now = std.Io.Timestamp.now(io, .awake);
    const future = now.addDuration(.{ .nanoseconds = std.time.ns_per_hour });
    var p: PeriodicDeadline = .{
        .deadline = future,
        .target = 100,
    };

    const deadline = p.next(io, 100).?;
    try std.testing.expectEqual(future.nanoseconds, deadline.raw.nanoseconds);
    try std.testing.expectEqual(future.nanoseconds, p.deadline.?.nanoseconds);
}

test "missed deadlines advance by whole periods" {
    const io = std.testing.io;
    const period_ns: i96 = 10 * std.time.ns_per_ms;
    const now = std.Io.Timestamp.now(io, .awake);
    const previous = now.subDuration(.{ .nanoseconds = 35 * std.time.ns_per_ms });
    var p: PeriodicDeadline = .{
        .deadline = previous,
        .target = 100,
    };

    const deadline = p.next(io, 100).?;
    const advanced_ns = deadline.raw.nanoseconds - previous.nanoseconds;
    try std.testing.expect(deadline.raw.nanoseconds > now.nanoseconds);
    try std.testing.expect(advanced_ns >= 4 * period_ns);
    try std.testing.expectEqual(0, @mod(advanced_ns, period_ns));
}

test "changing or disabling the target resets the deadline" {
    const io = std.testing.io;
    const now = std.Io.Timestamp.now(io, .awake);
    const previous = now.addDuration(.{ .nanoseconds = std.time.ns_per_hour });
    var p: PeriodicDeadline = .{
        .deadline = previous,
        .target = 100,
    };

    const changed = p.next(io, 50).?;
    try std.testing.expectEqual(50, p.target);
    try std.testing.expect(changed.raw.nanoseconds < previous.nanoseconds);
    try std.testing.expectEqual(changed.raw.nanoseconds, p.deadline.?.nanoseconds);

    try std.testing.expectEqual(null, p.next(io, 0));
    try std.testing.expectEqual(0, p.target);
    try std.testing.expectEqual(null, p.deadline);
}
