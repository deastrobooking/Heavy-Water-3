const std = @import("std");
const Overlay = @This();
pub const Vertex = extern struct { position: [2]f32, color: [4]f32 };
pub const capacity = 120000;
/// Fixed-capacity text published from the application thread.
pub const Line = struct {
    text: [96]u8 = undefined,
    len: u8 = 0,

    pub fn set(self: *Line, comptime fmt: []const u8, args: anytype) void {
        const written = std.fmt.bufPrint(&self.text, fmt, args) catch self.text[0..];
        // The bitmap font has no lowercase glyphs.
        for (written) |*c| c.* = std.ascii.toUpper(c.*);
        self.len = @intCast(written.len);
    }

    pub fn slice(self: *const Line) []const u8 {
        return self.text[0..self.len];
    }
};
vertices: [capacity]Vertex = undefined,
len: usize = 0,
width: f32 = 1,
height: f32 = 1,

pub fn rect(self: *Overlay, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
    if (self.len + 6 > capacity) return;
    const x0 = x / self.width * 2 - 1;
    const y0 = 1 - y / self.height * 2;
    const x1 = (x + w) / self.width * 2 - 1;
    const y1 = 1 - (y + h) / self.height * 2;
    for ([_][2]f32{ .{ x0, y0 }, .{ x0, y1 }, .{ x1, y0 }, .{ x1, y0 }, .{ x0, y1 }, .{ x1, y1 } }) |p| {
        self.vertices[self.len] = .{ .position = p, .color = color };
        self.len += 1;
    }
}

pub fn text(self: *Overlay, x: f32, y: f32, value: []const u8, color: [4]f32) void {
    self.textScaled(x, y, value, color, 2);
}

/// Text with glyph cells `cell` pixels square (a character advances 4 cells). Lit cells in a
/// glyph row merge into one rectangle, so long dialogue stays within the vertex budget.
pub fn textScaled(self: *Overlay, x: f32, y: f32, value: []const u8, color: [4]f32, cell: f32) void {
    for (value, 0..) |ch, i| {
        const bits = glyph(ch);
        const left = x + @as(f32, @floatFromInt(i)) * 4 * cell;
        for (0..5) |row| {
            var col: usize = 0;
            while (col < 3) {
                const shift: u4 = @intCast(14 - (row * 3 + col));
                if ((bits >> shift) & 1 == 0) {
                    col += 1;
                    continue;
                }
                var end = col + 1;
                while (end < 3 and (bits >> @as(u4, @intCast(14 - (row * 3 + end)))) & 1 == 1) end += 1;
                self.rect(left + @as(f32, @floatFromInt(col)) * cell, y + @as(f32, @floatFromInt(row)) * cell, @as(f32, @floatFromInt(end - col)) * cell, cell, color);
                col = end;
            }
        }
    }
}

fn glyph(raw: u8) u15 {
    // The font has no lowercase glyphs; lowercase text draws as capitals.
    const ch = std.ascii.toUpper(raw);
    return switch (ch) {
        'A' => 0b010_101_111_101_101,
        'B' => 0b110_101_110_101_110,
        'C' => 0b111_100_100_100_111,
        'D' => 0b110_101_101_101_110,
        'E' => 0b111_100_110_100_111,
        'F' => 0b111_100_110_100_100,
        'G' => 0b111_100_101_101_111,
        'H' => 0b101_101_111_101_101,
        'I' => 0b111_010_010_010_111,
        'J' => 0b001_001_001_101_111,
        'K' => 0b101_101_110_101_101,
        'L' => 0b100_100_100_100_111,
        'M' => 0b101_111_111_101_101,
        'N' => 0b101_111_111_111_101,
        'O' => 0b111_101_101_101_111,
        'P' => 0b111_101_111_100_100,
        'Q' => 0b111_101_101_111_001,
        'R' => 0b110_101_110_101_101,
        'S' => 0b111_100_111_001_111,
        'T' => 0b111_010_010_010_010,
        'U' => 0b101_101_101_101_111,
        'V' => 0b101_101_101_101_010,
        'W' => 0b101_101_111_111_101,
        'X' => 0b101_101_010_101_101,
        'Y' => 0b101_101_010_010_010,
        'Z' => 0b111_001_010_100_111,
        '0' => 0b111_101_101_101_111,
        '1' => 0b010_110_010_010_111,
        '2' => 0b111_001_111_100_111,
        '3' => 0b111_001_111_001_111,
        '4' => 0b101_101_111_001_001,
        '5' => 0b111_100_111_001_111,
        '6' => 0b111_100_111_101_111,
        '7' => 0b111_001_010_010_010,
        '8' => 0b111_101_111_101_111,
        '9' => 0b111_101_111_001_111,
        '.' => 0b000_000_000_000_010,
        ':' => 0b000_010_000_010_000,
        '-' => 0b000_000_111_000_000,
        '/' => 0b001_001_010_100_100,
        '%' => 0b101_001_010_100_101,
        '>' => 0b100_010_001_010_100,
        '_' => 0b000_000_000_000_111,
        ',' => 0b000_000_000_010_100,
        '=' => 0b000_111_000_111_000,
        '!' => 0b010_010_010_000_010,
        '?' => 0b111_001_010_000_010,
        '\'' => 0b010_010_000_000_000,
        '"' => 0b101_101_000_000_000,
        '(' => 0b001_010_010_010_001,
        ')' => 0b100_010_010_010_100,
        '+' => 0b000_010_111_010_000,
        '<' => 0b001_010_100_010_001,
        '[' => 0b110_100_100_100_110,
        ']' => 0b011_001_001_001_011,
        ';' => 0b000_010_000_010_100,
        '*' => 0b101_010_101_000_000,
        '#' => 0b101_111_101_111_101,
        else => 0,
    };
}

test "scaled text merges lit runs and draws lowercase as capitals" {
    var o: Overlay = .{ .width = 100, .height = 100 };
    o.textScaled(0, 0, "t", .{ 1, 1, 1, 1 }, 3);
    // T: one merged top bar plus four stem cells.
    try std.testing.expectEqual(@as(usize, 5 * 6), o.len);
    const upper = o.len;
    o.len = 0;
    o.text(0, 0, "T?", .{ 1, 1, 1, 1 });
    try std.testing.expect(o.len > upper);
}
