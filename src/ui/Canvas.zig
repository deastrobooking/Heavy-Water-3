//! Fixed-capacity GUI display list, built by the application each frame and replayed by the
//! renderer into the overlay. Coordinates are virtual units: the window is `height` units tall
//! (720 at UI scale 1) and as wide as its aspect allows, so layouts are resolution independent.
//! Clickable areas are recorded as hits, which the application tests mouse positions against.
const std = @import("std");
const Canvas = @This();

pub const capacity = 640;
pub const hit_capacity = 64;
pub const text_capacity = 120;
/// A character advances four glyph cells; at scale 1 a cell is 2 units.
pub const char_width: f32 = 8;
pub const line_height: f32 = 10;

pub const Color = [4]f32;
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    pub fn contains(r: Rect, px: f32, py: f32) bool {
        return px >= r.x and py >= r.y and px < r.x + r.w and py < r.y + r.h;
    }
    pub fn inset(r: Rect, d: f32) Rect {
        return .{ .x = r.x + d, .y = r.y + d, .w = @max(0, r.w - 2 * d), .h = @max(0, r.h - 2 * d) };
    }
};
pub const Command = struct {
    kind: enum { rect, text } = .rect,
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    color: Color = .{ 1, 1, 1, 1 },
    /// Text: glyph-cell size in units (2 = normal).
    cell: f32 = 2,
    len: u8 = 0,
    text: [text_capacity]u8 = undefined,
};
/// A clickable area: `id` is screen-specific (a row, a button).
pub const Hit = struct { rect: Rect, id: u16 };

width: f32 = 1280,
height: f32 = 720,
commands: [capacity]Command = undefined,
len: usize = 0,
hits: [hit_capacity]Hit = undefined,
hit_len: usize = 0,

pub fn reset(self: *Canvas, width: f32, height: f32) void {
    self.width = width;
    self.height = height;
    self.len = 0;
    self.hit_len = 0;
}

pub fn rect(self: *Canvas, r: Rect, color: Color) void {
    if (self.len == capacity or r.w <= 0 or r.h <= 0) return;
    self.commands[self.len] = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h, .color = color };
    self.len += 1;
}

/// A rectangle outline `t` units thick.
pub fn frame(self: *Canvas, r: Rect, t: f32, color: Color) void {
    self.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = t }, color);
    self.rect(.{ .x = r.x, .y = r.y + r.h - t, .w = r.w, .h = t }, color);
    self.rect(.{ .x = r.x, .y = r.y + t, .w = t, .h = r.h - 2 * t }, color);
    self.rect(.{ .x = r.x + r.w - t, .y = r.y + t, .w = t, .h = r.h - 2 * t }, color);
}

/// Text at `scale` (1 = 10 units tall). Longer text is cut at `text_capacity`.
pub fn text(self: *Canvas, x: f32, y: f32, value: []const u8, scale: f32, color: Color) void {
    if (self.len == capacity or value.len == 0) return;
    const n = @min(value.len, text_capacity);
    var c: Command = .{ .kind = .text, .x = x, .y = y, .color = color, .cell = 2 * scale, .len = @intCast(n) };
    @memcpy(c.text[0..n], value[0..n]);
    self.commands[self.len] = c;
    self.len += 1;
}

pub fn print(self: *Canvas, x: f32, y: f32, scale: f32, color: Color, comptime fmt: []const u8, args: anytype) void {
    var buffer: [text_capacity]u8 = undefined;
    self.text(x, y, std.fmt.bufPrint(&buffer, fmt, args) catch buffer[0..], scale, color);
}

pub fn textWidth(value: []const u8, scale: f32) f32 {
    // The last character has no trailing gap (one cell).
    if (value.len == 0) return 0;
    return (@as(f32, @floatFromInt(value.len)) * char_width - 2) * scale;
}

pub fn centered(self: *Canvas, cx: f32, y: f32, value: []const u8, scale: f32, color: Color) void {
    self.text(cx - textWidth(value, scale) / 2, y, value, scale, color);
}

pub fn hit(self: *Canvas, r: Rect, id: u16) void {
    if (self.hit_len == hit_capacity) return;
    self.hits[self.hit_len] = .{ .rect = r, .id = id };
    self.hit_len += 1;
}

/// The topmost hit under a point (later hits are drawn above earlier ones).
pub fn hitAt(self: *const Canvas, x: f32, y: f32) ?u16 {
    var i = self.hit_len;
    while (i > 0) {
        i -= 1;
        if (self.hits[i].rect.contains(x, y)) return self.hits[i].id;
    }
    return null;
}

/// Splits `value` into lines of at most `columns` characters at spaces, writing slices into
/// `out`; returns the line count. A word longer than a line is cut.
pub fn wrap(value: []const u8, columns: usize, out: [][]const u8) usize {
    var n: usize = 0;
    var start: usize = 0;
    while (start < value.len and n < out.len) {
        while (start < value.len and value[start] == ' ') start += 1;
        if (start == value.len) break;
        var end = @min(value.len, start + columns);
        if (end < value.len and value[end] != ' ') {
            var cut = end;
            while (cut > start and value[cut] != ' ') cut -= 1;
            if (cut > start) end = cut;
        }
        out[n] = std.mem.trimEnd(u8, value[start..end], " ");
        n += 1;
        start = end;
    }
    return n;
}

test "wrap breaks at spaces, keeps every word, and cuts only overlong words" {
    var lines: [8][]const u8 = undefined;
    const n = wrap("the arbors drink the river and breathe the sky", 16, &lines);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("the arbors drink", lines[0]);
    try std.testing.expectEqualStrings("the river and", lines[1]);
    try std.testing.expectEqualStrings("breathe the sky", lines[2]);
    try std.testing.expectEqual(@as(usize, 2), wrap("abcdefghij", 6, &lines));
    try std.testing.expectEqualStrings("abcdef", lines[0]);
}

test "hits resolve topmost first and text is measured in units" {
    var c: Canvas = .{};
    c.reset(1280, 720);
    c.hit(.{ .x = 0, .y = 0, .w = 100, .h = 100 }, 1);
    c.hit(.{ .x = 50, .y = 50, .w = 100, .h = 100 }, 2);
    try std.testing.expectEqual(@as(?u16, 2), c.hitAt(60, 60));
    try std.testing.expectEqual(@as(?u16, 1), c.hitAt(10, 10));
    try std.testing.expectEqual(@as(?u16, null), c.hitAt(300, 300));
    try std.testing.expectApproxEqAbs(@as(f32, 22), textWidth("ABC", 1), 1e-6);
    c.text(0, 0, "x" ** 200, 1, .{ 1, 1, 1, 1 });
    try std.testing.expectEqual(@as(u8, text_capacity), c.commands[0].len);
}
