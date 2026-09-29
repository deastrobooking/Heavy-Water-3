const std = @import("std");
const FrameStats = @This();
pub const capacity = 4096;
samples: [capacity]f32 = undefined,
len: usize = 0,
next: usize = 0,
total: u64 = 0,
sum: f64 = 0,
worst: f32 = 0,
pub const Summary = struct { p50: f32, p95: f32, p99: f32, worst: f32, mean: f64 };

pub fn record(self: *FrameStats, ms: f32) void {
    if (!std.math.isFinite(ms) or ms < 0) return;
    self.samples[self.next] = ms;
    self.next = (self.next + 1) % capacity;
    self.len = @min(self.len + 1, capacity);
    self.total += 1;
    self.sum += ms;
    self.worst = @max(self.worst, ms);
}

pub fn summary(self: *const FrameStats) Summary {
    if (self.len == 0) return .{ .p50 = 0, .p95 = 0, .p99 = 0, .worst = 0, .mean = 0 };
    var scratch: [capacity]f32 = undefined;
    @memcpy(scratch[0..self.len], self.samples[0..self.len]);
    std.mem.sort(f32, scratch[0..self.len], {}, std.sort.asc(f32));
    return .{ .p50 = scratch[(self.len * 50 + 99) / 100 - 1], .p95 = scratch[(self.len * 95 + 99) / 100 - 1], .p99 = scratch[(self.len * 99 + 99) / 100 - 1], .worst = self.worst, .mean = self.sum / @as(f64, @floatFromInt(self.total)) };
}

test "nearest rank percentiles and bounded storage" {
    var stats: FrameStats = .{};
    for (1..101) |i| stats.record(@floatFromInt(i));
    const result = stats.summary();
    try std.testing.expectEqual(@as(f32, 50), result.p50);
    try std.testing.expectEqual(@as(f32, 95), result.p95);
    try std.testing.expectEqual(@as(f32, 99), result.p99);
    for (0..capacity + 2) |_| stats.record(1);
    try std.testing.expectEqual(@as(f32, 1), stats.summary().p99);
    try std.testing.expectEqual(@as(usize, capacity), stats.len);
}
