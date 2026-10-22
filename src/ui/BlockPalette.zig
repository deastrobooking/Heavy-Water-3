//! A strip at the bottom of each building player's view: the style's materials as swatches with
//! that player's own count, the chosen one framed, and the shape and box state as text.
const std = @import("std");
const Canvas = @import("Canvas.zig");
const Sandbox = @import("../game/Sandbox.zig");
const BlockTool = @import("../game/BlockTool.zig");
const Materials = @import("../build/Materials.zig");

const swatch: f32 = 26;
const gap: f32 = 6;

pub fn draw(c: *Canvas, view: Canvas.Rect, sb: *const Sandbox, slot: usize, st: BlockTool.State) void {
    const palette = Materials.ofStyle(st.style);
    const chosen = BlockTool.cell(st);
    const width = @as(f32, @floatFromInt(palette.len)) * (swatch + gap) - gap;
    const x0 = view.x + (view.w - width) / 2;
    // Above the vitals and powers panels along the bottom of the view.
    const y = view.y + view.h - swatch - 150;
    c.rect(.{ .x = x0 - 10, .y = y - 24, .w = width + 20, .h = swatch + 44 }, .{ 0.03, 0.05, 0.08, 0.72 });
    var label: [64]u8 = undefined;
    const mode = if (st.corner != null) (if (st.corner_clears) "  CLEAR BOX" else "  FILL BOX") else "";
    const text = std.fmt.bufPrint(&label, "{s} {s}{s}", .{ shapeName(chosen.shape), Materials.all[chosen.material].name, mode }) catch "";
    c.text(x0, y - 18, text, 1, .{ 0.92, 0.95, 1, 1 });
    for (palette, 0..) |m, i| {
        const x = x0 + @as(f32, @floatFromInt(i)) * (swatch + gap);
        const count = sb.kits[slot].blocks[m];
        const color = Materials.all[m].color;
        const dim: f32 = if (count == 0) 0.35 else 1;
        c.rect(.{ .x = x, .y = y, .w = swatch, .h = swatch }, .{ color[0] * dim, color[1] * dim, color[2] * dim, 1 });
        if (m == chosen.material) c.frame(.{ .x = x - 3, .y = y - 3, .w = swatch + 6, .h = swatch + 6 }, 2, .{ 1, 0.85, 0.3, 1 });
        c.print(x + 2, y + swatch + 3, 0.8, .{ 0.85, 0.88, 0.92, 1 }, "{d}", .{count});
    }
}

fn shapeName(shape: anytype) []const u8 {
    return switch (shape) {
        .cube => "CUBE",
        .slab => "SLAB",
        .ramp => "RAMP",
        .stair => "STAIR",
        else => "",
    };
}

/// P1 when holding the block tool, and every guest in building mode.
pub fn drawAll(c: *Canvas, sb: *const Sandbox, p1_view: Canvas.Rect, guest_views: anytype) void {
    if (sb.tools.tool == .blocks) draw(c, p1_view, sb, 0, sb.tools.blocks);
    for (guest_views) |g| if (sb.guests[g.index].building) |st| draw(c, g.view, sb, g.index + 1, st);
}

test "the palette for four building players fits the canvas budget" {
    var canvas: Canvas = .{};
    canvas.reset(1280, 720);
    var sb: Sandbox = undefined;
    sb.tools = .{};
    sb.kits = @splat(.{});
    const before = canvas.len;
    for (0..4) |i| draw(&canvas, .{ .x = @floatFromInt(i * 320), .y = 0, .w = 320, .h = 360 }, &sb, i, .{});
    try std.testing.expect(canvas.len - before <= 4 * 30);
}
