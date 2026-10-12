//! Runtime rasterization of Mach's bundled Fira Sans face for the screen-space overlay.
//! One 32 px atlas is shared by all menus, prompts, HUD labels, and diagnostics.
const std = @import("std");
const mach = @import("mach");
const Overlay = @import("Overlay.zig");

pub const width: u32 = 640;
pub const height: u32 = 240;
const cell: u32 = 40;
const columns: u32 = width / cell;
const size_px: f32 = 32;

pub const Atlas = struct {
    pixels: []u8,
    glyphs: [128]Overlay.FontGlyph,
    ascent: f32 = 25,
};

pub fn rasterize(allocator: std.mem.Allocator) !Atlas {
    const pixels = try allocator.alloc(u8, width * height * 4);
    errdefer allocator.free(pixels);
    @memset(pixels, 0);
    var glyphs: [128]Overlay.FontGlyph = @splat(.{});

    var font = try mach.gfx.Font.initBytes(mach.gfx.default_font);
    defer font.deinit(allocator);
    var run = try mach.gfx.TextRun.init();
    defer run.deinit();
    run.font_size_px = size_px;
    run.px_density = 1;

    var chars: [95]u8 = undefined;
    for (&chars, 0..) |*ch, i| ch.* = @intCast(i + 32);
    run.addText(&chars);
    try font.shape(&run);
    while (run.next()) |item| {
        if (item.cluster >= chars.len) continue;
        const ch = chars[item.cluster];
        const rendered = try font.render(allocator, item.glyph_index, .{ .font_size_px = size_px });
        const col: u32 = @as(u32, ch - 32) % columns;
        const row: u32 = @as(u32, ch - 32) / columns;
        const ox = col * cell;
        const oy = row * cell;
        if (rendered.width > cell or rendered.height > cell) return error.GlyphTooLarge;
        if (rendered.bitmap) |bitmap| for (0..rendered.height) |y| {
            for (0..rendered.width) |x| {
                const source = bitmap[y * rendered.width + x];
                const at: usize = (@as(usize, oy + @as(u32, @intCast(y))) * width + ox + @as(u32, @intCast(x))) * 4;
                pixels[at + 0] = source.r;
                pixels[at + 1] = source.g;
                pixels[at + 2] = source.b;
                pixels[at + 3] = source.a;
            }
        };
        glyphs[ch] = .{
            .uv = .{ @as(f32, @floatFromInt(ox)) / @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(oy)) / @as(f32, @floatFromInt(height)), @as(f32, @floatFromInt(rendered.width)) / @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(rendered.height)) / @as(f32, @floatFromInt(height)) },
            .bearing_x = rendered.bearing_x,
            .bearing_y = rendered.bearing_y,
            .width = @floatFromInt(rendered.width),
            .height = @floatFromInt(rendered.height),
            .advance = item.advance.x(),
        };
    }
    return .{ .pixels = pixels, .glyphs = glyphs };
}
