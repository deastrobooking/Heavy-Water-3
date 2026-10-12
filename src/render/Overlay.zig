const std = @import("std");
const Overlay = @This();
pub const Vertex = extern struct { position: [2]f32, color: [4]f32, uv: [2]f32 };
pub const FontGlyph = struct {
    uv: [4]f32 = .{ 0, 0, 0, 0 },
    bearing_x: f32 = 0,
    bearing_y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
    advance: f32 = 16,
};
pub const capacity = 120000;
/// Fixed-capacity text published from the application thread.
pub const Line = struct {
    text: [96]u8 = undefined,
    len: u8 = 0,

    pub fn set(self: *Line, comptime fmt: []const u8, args: anytype) void {
        const written = std.fmt.bufPrint(&self.text, fmt, args) catch self.text[0..];
        self.len = @intCast(written.len);
    }

    pub fn slice(self: *const Line) []const u8 {
        return self.text[0..self.len];
    }
};
/// Heap storage of `capacity` vertices, allocated by the renderer. Kept off the struct: Mach
/// holds module state (and copies it during init) on the main thread's stack, where 2.9 MB of
/// inline vertices overflowed it in Debug builds.
vertices: []Vertex = &.{},
len: usize = 0,
width: f32 = 1,
height: f32 = 1,
font_glyphs: [128]FontGlyph = @splat(.{}),
font_ascent: f32 = 25,

pub fn rect(self: *Overlay, x: f32, y: f32, w: f32, h: f32, color: [4]f32) void {
    if (self.len + 6 > self.vertices.len) return;
    const x0 = x / self.width * 2 - 1;
    const y0 = 1 - y / self.height * 2;
    const x1 = (x + w) / self.width * 2 - 1;
    const y1 = 1 - (y + h) / self.height * 2;
    for ([_][2]f32{ .{ x0, y0 }, .{ x0, y1 }, .{ x1, y0 }, .{ x1, y0 }, .{ x0, y1 }, .{ x1, y1 } }) |p| {
        self.vertices[self.len] = .{ .position = p, .color = color, .uv = .{ -1, -1 } };
        self.len += 1;
    }
}

pub fn text(self: *Overlay, x: f32, y: f32, value: []const u8, color: [4]f32) void {
    self.textScaled(x, y, value, color, 2);
}

/// Fira Sans glyphs are sampled from the shared font atlas. `cell` preserves the old UI scale:
/// two virtual pixels render at a font scale of one-half.
pub fn textScaled(self: *Overlay, x: f32, y: f32, value: []const u8, color: [4]f32, cell: f32) void {
    const scale = cell / 4;
    var cursor = x;
    const baseline = y + self.font_ascent * scale;
    for (value) |raw| {
        const ch: u8 = if (raw < self.font_glyphs.len) raw else '?';
        const glyph = self.font_glyphs[ch];
        if (glyph.width > 2 and glyph.height > 2 and self.len + 6 <= self.vertices.len) {
            const left = cursor + (glyph.bearing_x - 1) * scale;
            const top = baseline - (glyph.bearing_y + 1) * scale;
            const w = glyph.width * scale;
            const h = glyph.height * scale;
            const uv_left = glyph.uv[0];
            const v0 = glyph.uv[1];
            const uv_right = uv_left + glyph.uv[2];
            const v1 = v0 + glyph.uv[3];
            self.glyphQuad(left, top, w, h, .{ uv_left, v0 }, .{ uv_right, v1 }, color);
        }
        cursor += glyph.advance * scale;
    }
}

fn glyphQuad(self: *Overlay, x: f32, y: f32, w: f32, h: f32, uv0: [2]f32, uv1: [2]f32, color: [4]f32) void {
    if (self.len + 6 > self.vertices.len) return;
    const x0 = x / self.width * 2 - 1;
    const y0 = 1 - y / self.height * 2;
    const x1 = (x + w) / self.width * 2 - 1;
    const y1 = 1 - (y + h) / self.height * 2;
    const points = [_]struct { p: [2]f32, uv: [2]f32 }{
        .{ .p = .{ x0, y0 }, .uv = .{ uv0[0], uv0[1] } },
        .{ .p = .{ x0, y1 }, .uv = .{ uv0[0], uv1[1] } },
        .{ .p = .{ x1, y0 }, .uv = .{ uv1[0], uv0[1] } },
        .{ .p = .{ x1, y0 }, .uv = .{ uv1[0], uv0[1] } },
        .{ .p = .{ x0, y1 }, .uv = .{ uv0[0], uv1[1] } },
        .{ .p = .{ x1, y1 }, .uv = .{ uv1[0], uv1[1] } },
    };
    for (points) |point| {
        self.vertices[self.len] = .{ .position = point.p, .color = color, .uv = point.uv };
        self.len += 1;
    }
}

test "screen text emits atlas-backed glyph quads at the requested scale" {
    var storage: [256]Vertex = undefined;
    var o: Overlay = .{ .width = 100, .height = 100, .vertices = &storage };
    o.font_glyphs['A'] = .{ .uv = .{ 0.1, 0.2, 0.05, 0.1 }, .bearing_y = 20, .width = 18, .height = 24, .advance = 19 };
    o.textScaled(4, 6, "A", .{ 1, 1, 1, 1 }, 2);
    try std.testing.expectEqual(@as(usize, 6), o.len);
    try std.testing.expect(o.vertices[0].uv[0] >= 0);
}
