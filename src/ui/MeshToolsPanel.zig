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

pub fn draw(c: *Canvas, cr: *const Creator, v: Rect) void {
    const tools = cr.mesh_tools orelse return;
    const w: f32 = @min(320, v.w * 0.42);
    // Content is about 600 units tall; the status lines follow it rather than being pinned to the
    // bottom, so a short window scrolls instead of drawing text over the buttons.
    const r: Rect = .{ .x = v.x + v.w - w - 10, .y = v.y + 10, .w = w, .h = @min(v.h - 20, 610) };
    // The panel first: the canvas has a fixed command budget, and the selection dots take only
    // what the panel leaves.
    defer overlay(c, tools, v, r);
    c.rect(r, .{ 0.025, 0.04, 0.055, 0.9 });
    c.frame(r, 1, alpha(accent, 0.5));
    c.text(r.x + 12, r.y + 10, "VERTEX TOOLS", 1, accent);
    const x = r.x + 12;
    const inner = r.w - 24;
    var y = r.y + 34;

    // Tools, three per row.
    const cell = (inner - 8) / 3;
    for (MeshTools.tool_labels, 0..) |label, i| {
        const col: f32 = @floatFromInt(i % 3);
        const row: f32 = @floatFromInt(i / 3);
        button(c, .{ .x = x + col * (cell + 4), .y = y + row * 30, .w = cell, .h = 26 }, label, id(i), tools.tool == @as(MeshTools.Tool, @enumFromInt(i)));
    }
    y += 98;
    c.text(x, y, MeshTools.tool_hints[@intFromEnum(tools.tool)], 0.62, dim);
    y += 22;

    // Brush.
    var buf: [24]u8 = undefined;
    stepper(c, x, y, inner, "BRUSH SIZE", std.fmt.bufPrint(&buf, "{d:.1}%", .{tools.radius * 100}) catch "", .radius_down, .radius_up);
    y += 30;
    stepper(c, x, y, inner, "STRENGTH", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.strength * 100}) catch "", .strength_down, .strength_up);
    y += 30;
    stepper(c, x, y, inner, "SOFT SELECT", std.fmt.bufPrint(&buf, "{d:.0}%", .{tools.soft * 100}) catch "", .soft_down, .soft_up);
    y += 30;
    button(c, .{ .x = x, .y = y, .w = inner, .h = 24 }, if (tools.masked) "PAINT INSIDE SELECTION: ON" else "PAINT INSIDE SELECTION: OFF", control(.masked), tools.masked);
    y += 34;

    // Colour swatches and the cel pen.
    c.text(x, y, "COLOUR", 0.74, dim);
    y += 16;
    const sw = (inner - 7 * 4) / @as(f32, @floatFromInt(MeshTools.swatches.len));
    for (MeshTools.swatches, 0..) |color, i| {
        const cell_rect: Rect = .{ .x = x + @as(f32, @floatFromInt(i)) * (sw + 4), .y = y, .w = sw, .h = 22 };
        c.rect(cell_rect, .{ color[0], color[1], color[2], 1 });
        if (std.mem.eql(f32, &color, &tools.color)) c.frame(cell_rect, 2, ink);
        c.hit(cell_rect, id(@intFromEnum(MeshTools.Control.swatch_first) + i));
    }
    y += 30;
    var pen_buf: [24]u8 = undefined;
    stepper(c, x, y, inner, "CEL PEN", upper(&pen_buf, MeshTools.penName(tools.pen)), .pen_down, .pen_up);
    y += 34;

    // Selection.
    const e = tools.editor;
    c.print(x, y, 0.74, dim, "SELECTION  {d} VERTICES", .{if (e) |ed| ed.selectedCount() else 0});
    y += 18;
    const half = (inner - 4) / 2;
    const quarter = (inner - 12) / 4;
    for ([_]MeshTools.Control{ .grow, .linked, .invert, .clear }, [_][]const u8{ "GROW", "PIECE", "INVERT", "CLEAR" }, 0..) |ctl, label, i| {
        button(c, .{ .x = x + @as(f32, @floatFromInt(i)) * (quarter + 4), .y = y, .w = quarter, .h = 24 }, label, control(ctl), false);
    }
    y += 28;
    button(c, .{ .x = x, .y = y, .w = half, .h = 24 }, "SAME PEN", control(.same_pen), false);
    button(c, .{ .x = x + half + 4, .y = y, .w = half, .h = 24 }, "SAME COLOUR", control(.same_color), false);
    y += 28;
    button(c, .{ .x = x, .y = y, .w = half, .h = 24 }, "FILL COLOUR", control(.fill_color), false);
    button(c, .{ .x = x + half + 4, .y = y, .w = half, .h = 24 }, "FILL PEN", control(.fill_pen), false);
    y += 28;
    button(c, .{ .x = x, .y = y, .w = inner, .h = 26 }, "TEAR OFF SELECTION AS A PART", control(.tear_off), false);
    y += 36;

    // History and exit.
    const can_undo = if (e) |ed| ed.canUndo() else false;
    const can_redo = if (e) |ed| ed.canRedo() else false;
    button(c, .{ .x = x, .y = y, .w = half, .h = 26 }, "UNDO", control(.undo), can_undo);
    button(c, .{ .x = x + half + 4, .y = y, .w = half, .h = 26 }, "REDO", control(.redo), can_redo);
    y += 32;
    button(c, .{ .x = x, .y = y, .w = inner, .h = 26 }, "BACK TO PART LIBRARY", control(.close), false);

    y += 38;
    c.text(x, y, tools.status(), 0.62, gold);
    c.text(x, y + 16, "1-9 TOOLS  [ ] SIZE  Z / SHIFT+Z", 0.6, dim);
    c.text(x, y + 30, "RIGHT-DRAG ORBIT  WHEEL ZOOM  ESC BACK", 0.6, dim);
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
