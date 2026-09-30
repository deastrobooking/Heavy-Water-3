//! Split-screen view rectangles, as fractions of the window.
const std = @import("std");
pub const max_views = 4;
/// A view's rectangle as fractions of the window.
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

/// Starfall's split: two players stack (wide views), three put P3 across the bottom, four
/// use quadrants.
pub fn viewRect(index: usize, count: usize) Rect {
    return switch (count) {
        0, 1 => .{ .x = 0, .y = 0, .w = 1, .h = 1 },
        2 => .{ .x = 0, .y = @as(f32, @floatFromInt(index)) * 0.5, .w = 1, .h = 0.5 },
        3 => if (index == 2) .{ .x = 0, .y = 0.5, .w = 1, .h = 0.5 } else .{ .x = @as(f32, @floatFromInt(index)) * 0.5, .y = 0, .w = 0.5, .h = 0.5 },
        else => .{ .x = @as(f32, @floatFromInt(index % 2)) * 0.5, .y = @as(f32, @floatFromInt(index / 2)) * 0.5, .w = 0.5, .h = 0.5 },
    };
}

test "split-screen layouts tile the window without overlap for one to four players" {
    for (1..max_views + 1) |count| {
        var area: f32 = 0;
        for (0..count) |i| {
            const a = viewRect(i, count);
            area += a.w * a.h;
            try std.testing.expect(a.x >= 0 and a.y >= 0 and a.x + a.w <= 1 and a.y + a.h <= 1);
            for (0..i) |j| {
                const b = viewRect(j, count);
                const overlap_x = @min(a.x + a.w, b.x + b.w) - @max(a.x, b.x);
                const overlap_y = @min(a.y + a.h, b.y + b.h) - @max(a.y, b.y);
                try std.testing.expect(overlap_x <= 0 or overlap_y <= 0);
            }
        }
        try std.testing.expectApproxEqAbs(@as(f32, 1), area, 1e-6);
    }
    // Two players stack into wide views; P1 is always top-left.
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0.5, .w = 1, .h = 0.5 }, viewRect(1, 2));
    try std.testing.expectEqual(Rect{ .x = 0, .y = 0.5, .w = 1, .h = 0.5 }, viewRect(2, 3));
    try std.testing.expectEqual(Rect{ .x = 0.5, .y = 0.5, .w = 0.5, .h = 0.5 }, viewRect(3, 4));
}
