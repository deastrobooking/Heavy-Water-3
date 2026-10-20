//! The vertex tools' panel: a narrow tool bar docked right so the model stays in view, plus the
//! selection dots and brush ring drawn over the 3D view. Every control is one `mesh_tool` hit
//! whose row is a `MeshTools.Control` (or a tool index).
const std = @import("std");
const Canvas = @import("Canvas.zig");
const Screens = @import("Screens.zig");
const Creator = @import("../game/Creator.zig");
const MeshTools = @import("../game/MeshTools.zig");
const Rect = Canvas.Rect;
const Color = Canvas.Color;

const ink = Screens.ink;
const dim = Screens.dim;
const accent = Screens.accent;
const gold = Screens.gold;

fn alpha(c: Color, a: f32) Color {
    return .{ c[0], c[1], c[2], c[3] * a };
}

fn id(row: usize) u16 {
    return Screens.hitId(.mesh_tool, row);
}

fn control(c: MeshTools.Control) u16 {
    return id(@intFromEnum(c));
}

fn button(c: *Canvas, r: Rect, label: []const u8, hit: u16, on: bool) void {
    c.rect(r, if (on) alpha(accent, 0.34) else alpha(accent, 0.1));
    c.frame(r, 1, alpha(accent, if (on) 1 else 0.6));
    c.centered(r.x + r.w / 2, r.y + (r.h - Canvas.line_height) / 2, label, 0.82, if (on) ink else alpha(ink, 0.9));
    c.hit(r, hit);
}

/// A "- value +" stepper row.
fn stepper(c: *Canvas, x: f32, y: f32, w: f32, label: []const u8, value: []const u8, down: MeshTools.Control, up: MeshTools.Control) void {
    c.text(x, y + 7, label, 0.74, dim);
    button(c, .{ .x = x + w - 128, .y = y, .w = 28, .h = 24 }, "-", control(down), false);
    c.centered(x + w - 64, y + 7, value, 0.8, ink);
    button(c, .{ .x = x + w - 28, .y = y, .w = 28, .h = 24 }, "+", control(up), false);
}

/// A compact "LABEL  -  value  +" stepper in a half-width cell.
fn small(c: *Canvas, x: f32, y: f32, w: f32, label: []const u8, value: []const u8, down: MeshTools.Control, up: MeshTools.Control) void {
    c.text(x, y + 8, label, 0.6, dim);
    button(c, .{ .x = x + w - 92, .y = y, .w = 22, .h = 22 }, "-", control(down), false);
    c.centered(x + w - 46, y + 7, value, 0.7, ink);
    button(c, .{ .x = x + w - 22, .y = y, .w = 22, .h = 22 }, "+", control(up), false);
}

pub fn draw(c: *Canvas, cr: *const Creator, v: Rect) void {
    const tools = cr.mesh_tools orelse return;
    const w: f32 = @min(340, v.w * 0.44);
    // About 500 units of content; status lines follow it, so a short window scrolls instead of
    // drawing text over the buttons.
    const r: Rect = .{ .x = v.x + v.w - w - 10, .y = v.y + 10, .w = w, .h = @min(v.h - 20, 520) };
    // The panel first: the canvas has a fixed command budget, and the selection dots take only
    // what the panel leaves.
    defer overlay(c, tools, v, r);
    c.rect(r, .{ 0.025, 0.04, 0.055, 0.9 });
    c.frame(r, 1, alpha(accent, 0.5));
    c.text(r.x + 12, r.y + 10, "VERTEX TOOLS", 1, accent);
    const x = r.x + 12;
    const inner = r.w - 24;
    const half = (inner - 8) / 2;
    const x2 = x + half + 8;
    var y = r.y + 32;
    var buf: [24]u8 = undefined;

    // Tools, five per row (keys 1-9, 0).
    const cell = (inner - 16) / 5;
    for (MeshTools.tool_labels, 0..) |label, i| {
        const col: f32 = @floatFromInt(i % 5);
        const row: f32 = @floatFromInt(i / 5);
        button(c, .{ .x = x + col * (cell + 4), .y = y + row * 28, .w = cell, .h = 24 }, label, id(i), tools.tool == @as(MeshTools.Tool, @enumFromInt(i)));
    }
    y += 60;
    c.text(x, y, MeshTools.tool_hints[@intFromEnum(tools.tool)], 0.58, dim);
    y += 18;

    // Brush.
    stepper(c, x, y, inner, "BRUSH PRESET", MeshTools.presets[tools.preset].name, .preset_down, .preset_up);
    y += 30;
    small(c, x, y, half, "SIZE", std.fmt.bufPrint(&buf, "{d:.1}%", .{tools.radius * 100}) catch "", .radius_down, .radius_up);
    small(c, x2, y, half, "STRENGTH", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.strength * 100}) catch "", .strength_down, .strength_up);
    y += 28;
    small(c, x, y, half, "HARDNESS", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.hardness * 100}) catch "", .hardness_down, .hardness_up);
    small(c, x2, y, half, "SOFT SEL", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.soft * 100}) catch "", .soft_down, .soft_up);
    y += 28;
    const quarter = (inner - 12) / 4;
    const blend_label: []const u8 = switch (tools.blend) {
        .mix => "MIX",
        .multiply => "MULTIPLY",
        .screen => "SCREEN",
        .smudge => "SMUDGE",
    };
    button(c, .{ .x = x, .y = y, .w = quarter, .h = 22 }, blend_label, control(.blend_cycle), false);
    button(c, .{ .x = x + (quarter + 4), .y = y, .w = quarter, .h = 22 }, "MIRROR X", control(.mirror), tools.mirror);
    button(c, .{ .x = x + 2 * (quarter + 4), .y = y, .w = quarter, .h = 22 }, "FRONT ONLY", control(.backface), tools.backface);
    button(c, .{ .x = x + 3 * (quarter + 4), .y = y, .w = quarter, .h = 22 }, "IN SEL", control(.masked), tools.masked);
    y += 30;

    // Colour: swatches, the current colour, HSV, and the cel pen.
    const sw = (inner - 40 - 7 * 4) / @as(f32, @floatFromInt(MeshTools.swatches.len));
    for (MeshTools.swatches, 0..) |color, i| {
        const cell_rect: Rect = .{ .x = x + @as(f32, @floatFromInt(i)) * (sw + 4), .y = y, .w = sw, .h = 20 };
        c.rect(cell_rect, .{ color[0], color[1], color[2], 1 });
        c.hit(cell_rect, id(@intFromEnum(MeshTools.Control.swatch_first) + i));
    }
    const current: Rect = .{ .x = x + inner - 32, .y = y - 2, .w = 32, .h = 24 };
    c.rect(current, .{ tools.color[0], tools.color[1], tools.color[2], 1 });
    c.frame(current, 2, ink);
    y += 28;
    small(c, x, y, half, "HUE", std.fmt.bufPrint(&buf, "{d:.0}", .{tools.hsv[0] * 360}) catch "", .hue_down, .hue_up);
    small(c, x2, y, half, "SAT", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.hsv[1] * 100}) catch "", .sat_down, .sat_up);
    y += 28;
    var pen_buf: [24]u8 = undefined;
    small(c, x, y, half, "VALUE", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.hsv[2] * 100}) catch "", .val_down, .val_up);
    small(c, x2, y, half, "PEN", upper(&pen_buf, MeshTools.penName(tools.pen)), .pen_down, .pen_up);
    y += 32;

    // Selection.
    const e = tools.editor;
    c.print(x, y, 0.7, dim, "SELECTION  {d} VERTICES", .{if (e) |ed| ed.selectedCount() else 0});
    y += 16;
    for ([_]MeshTools.Control{ .grow, .linked, .invert, .clear }, [_][]const u8{ "GROW", "PIECE", "INVERT", "CLEAR" }, 0..) |ctl, label, i| {
        button(c, .{ .x = x + @as(f32, @floatFromInt(i)) * (quarter + 4), .y = y, .w = quarter, .h = 22 }, label, control(ctl), false);
    }
    y += 26;
    for ([_]MeshTools.Control{ .same_pen, .same_color, .fill_color, .fill_pen }, [_][]const u8{ "SAME PEN", "SAME COL", "FILL COL", "FILL PEN" }, 0..) |ctl, label, i| {
        button(c, .{ .x = x + @as(f32, @floatFromInt(i)) * (quarter + 4), .y = y, .w = quarter, .h = 22 }, label, control(ctl), false);
    }
    y += 26;
    button(c, .{ .x = x, .y = y, .w = inner, .h = 24 }, "TEAR OFF SELECTION AS A PART", control(.tear_off), false);
    y += 30;

    // History and exit.
    const can_undo = if (e) |ed| ed.canUndo() else false;
    const can_redo = if (e) |ed| ed.canRedo() else false;
    const third = (inner - 8) / 3;
    button(c, .{ .x = x, .y = y, .w = third, .h = 24 }, "UNDO", control(.undo), can_undo);
    button(c, .{ .x = x + third + 4, .y = y, .w = third, .h = 24 }, "REDO", control(.redo), can_redo);
    button(c, .{ .x = x + 2 * (third + 4), .y = y, .w = third, .h = 24 }, "BACK", control(.close), false);
    y += 32;
    c.text(x, y, tools.status(), 0.62, gold);
    c.text(x, y + 16, "1-9 0 TOOLS  [ ] SIZE  Z / SHIFT+Z  ESC BACK", 0.58, dim);
    c.text(x, y + 30, "RIGHT-DRAG ORBIT  WHEEL ZOOM", 0.58, dim);
}

/// Selected vertices as dots and the brush as a ring, over the 3D view.
fn overlay(c: *Canvas, tools: *const MeshTools, v: Rect, panel: Rect) void {
    const ring_cost = 40;
    const room = Canvas.capacity -| c.len -| ring_cost -| 8;
    const points = tools.overlay[0..tools.overlay_len];
    const stride = if (room == 0) points.len + 1 else @max(1, (points.len + room - 1) / room);
    var k: usize = 0;
    while (k < points.len) : (k += stride) {
        const x = v.x + points[k][0] * v.w;
        const y = v.y + points[k][1] * v.h;
        if (panel.contains(x, y)) continue;
        c.rect(.{ .x = x - 1.5, .y = y - 1.5, .w = 3, .h = 3 }, gold);
    }
    const ring = tools.ring orelse return;
    const cx = v.x + ring[0] * v.w;
    const cy = v.y + ring[1] * v.h;
    const radius = ring[2] * v.h;
    const segments = 40;
    for (0..segments) |i| {
        const a = @as(f32, @floatFromInt(i)) / segments * 2 * std.math.pi;
        c.rect(.{ .x = cx + @cos(a) * radius - 1, .y = cy + @sin(a) * radius - 1, .w = 2, .h = 2 }, alpha(accent, 0.9));
    }
}

fn upper(buf: []u8, text: []const u8) []const u8 {
    const n = @min(buf.len, text.len);
    for (text[0..n], buf[0..n]) |ch, *out| out.* = if (ch == '_') ' ' else std.ascii.toUpper(ch);
    return buf[0..n];
}

test "the vertex tool bar fits, keeps hits apart, and stays inside the canvas budgets" {
    const Model = @import("../asset/Model.zig");
    const Mesh = @import("../render/Mesh.zig");
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = MeshTools.init(a);
    defer tools.deinit();
    try tools.bind(&model, null);
    var creator: Creator = .{};
    creator.mesh_tools = &tools;
    const canvas = try a.create(Canvas);
    defer a.destroy(canvas);
    for ([_][2]f32{ .{ 1280, 720 }, .{ 853, 480 } }) |size| {
        canvas.* = .{};
        canvas.reset(size[0], size[1]);
        draw(canvas, &creator, .{ .x = 0, .y = 0, .w = size[0], .h = size[1] });
        try std.testing.expect(canvas.len < Canvas.capacity);
        try std.testing.expect(canvas.hit_len < Canvas.hit_capacity);
        const hits = canvas.hits[0..canvas.hit_len];
        for (hits, 0..) |h, i| {
            // At 720 everything is on screen; the 480 case may scroll, but never off the sides.
            try std.testing.expect(h.rect.x >= 0 and h.rect.x + h.rect.w <= size[0]);
            if (size[1] >= 720) try std.testing.expect(h.rect.y >= 0 and h.rect.y + h.rect.h <= size[1]);
            for (hits[i + 1 ..]) |o| {
                const apart = h.rect.x + h.rect.w <= o.rect.x or o.rect.x + o.rect.w <= h.rect.x or h.rect.y + h.rect.h <= o.rect.y or o.rect.y + o.rect.h <= h.rect.y;
                try std.testing.expect(apart);
            }
        }
    }
}
