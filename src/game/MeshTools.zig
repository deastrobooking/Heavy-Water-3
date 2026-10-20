//! The in-game vertex tools for an imported mesh: which tool is active, brush settings, the orbit
//! camera, and the press/drag/release state machine that turns pointer rays into `MeshEdit`
//! strokes. It holds no GPU or window state; `App` feeds it world-space rays and the model's
//! placement, then uploads whatever `MeshEdit` reports dirty.
const std = @import("std");
const math = @import("mach").math;
const MeshEdit = @import("../asset/MeshEdit.zig");
const Model = @import("../asset/Model.zig");
const Mesh = @import("../render/Mesh.zig");
const Camera = @import("../world/Camera.zig");
const CharacterMesh = @import("../character/mesh.zig");
const MeshTools = @This();

pub const V = MeshEdit.V;
pub const Ray = struct { origin: V, direction: V };

pub const Tool = enum { select, move, draw, inflate, smooth, grab, paint, pen, split, pick };
pub const tool_labels = [_][]const u8{ "SELECT", "MOVE", "DRAW", "INFLATE", "SMOOTH", "GRAB", "PAINT", "CEL PEN", "SPLIT", "PICK" };
pub const tool_hints = [_][]const u8{
    "CLICK A VERTEX, SHIFT+CLICK TO ADD, DRAG TO BRUSH-SELECT",
    "DRAG TO MOVE THE SELECTION; SOFT RADIUS FADES THE PULL",
    "DRAG TO BUILD UP THE SURFACE",
    "DRAG TO PUFF THE SURFACE OUTWARD",
    "DRAG TO RELAX BUMPS",
    "DRAG TO PULL THE SURFACE UNDER THE BRUSH",
    "DRAG TO PAINT VERTEX COLOUR",
    "DRAG TO DRAW A CEL MATERIAL (SHADING AND INK)",
    "CLICK A PIECE TO SELECT IT, THEN TEAR OFF THE SELECTION",
    "CLICK THE MESH TO PICK UP ITS COLOUR AND CEL PEN",
};

/// Paint brush presets as data: size, strength, edge hardness and blend in one choice.
pub const Preset = struct { name: []const u8, radius: f32, strength: f32, hardness: f32, blend: MeshEdit.Blend };
pub const presets = [_]Preset{
    .{ .name = "SOFT AIR", .radius = 0.06, .strength = 0.15, .hardness = 0, .blend = .mix },
    .{ .name = "HARD ROUND", .radius = 0.03, .strength = 1, .hardness = 0.85, .blend = .mix },
    .{ .name = "WATERCOLOUR", .radius = 0.08, .strength = 0.3, .hardness = 0.1, .blend = .multiply },
    .{ .name = "HIGHLIGHT", .radius = 0.04, .strength = 0.35, .hardness = 0.4, .blend = .screen },
    .{ .name = "SMUDGE", .radius = 0.05, .strength = 0.5, .hardness = 0.2, .blend = .smudge },
};

/// Brush colours offered by the panel; any colour can still be picked up from the mesh.
pub const swatches = [_][3]f32{ .{ 0.95, 0.93, 0.88 }, .{ 0.12, 0.12, 0.14 }, .{ 0.85, 0.2, 0.18 }, .{ 0.95, 0.62, 0.18 }, .{ 0.95, 0.85, 0.3 }, .{ 0.3, 0.72, 0.35 }, .{ 0.22, 0.55, 0.9 }, .{ 0.55, 0.32, 0.8 } };
pub const pen_count: u8 = @intCast(@import("../character/CelStyle.zig").material_count);

/// Panel controls, encoded as the row of a single hit area.
pub const Control = enum(u8) {
    radius_down = 20,
    radius_up,
    strength_down,
    strength_up,
    soft_down,
    soft_up,
    pen_down,
    pen_up,
    masked,
    grow,
    linked,
    invert,
    clear,
    same_pen,
    same_color,
    fill_color,
    fill_pen,
    undo,
    redo,
    tear_off,
    close,
    mirror,
    backface,
    hue_down,
    hue_up,
    sat_down,
    sat_up,
    val_down,
    val_up,
    preset_down,
    preset_up,
    blend_cycle,
    hardness_down,
    hardness_up,
    swatch_first = 60,
    open = 90,
    _,
};

pub const Action = enum { none, tear_off, close };
pub const max_overlay = 512;

allocator: std.mem.Allocator,
editor: ?MeshEdit.Editor = null,
active: bool = false,
tool: Tool = .select,
/// Brush and soft-selection sizes as fractions of the model's height, so they work on any import.
radius: f32 = 0.05,
strength: f32 = 0.3,
soft: f32 = 0.12,
color: [3]f32 = swatches[2],
/// Hue (0..1), saturation and value of `color`, kept separately so hue survives grey.
hsv: [3]f32 = rgbToHsv(swatches[2]),
hardness: f32 = 0,
blend: MeshEdit.Blend = .mix,
preset: u8 = 0,
/// Mirror every brush across the model's centre plane.
mirror: bool = false,
/// Skip vertices facing away from the camera.
backface: bool = true,
/// Model-space direction of the last pointer ray, for backface masking.
view_dir: V = .{ 0, 0, -1 },
pen: u8 = @intFromEnum(CharacterMesh.Material.armor),
masked: bool = false,
/// World = base + rotateY(yaw) * (scale * model point).
base: V = .{ 0, 0, 0 },
yaw: f32 = 0,
model_scale: f32 = 1,
orbit_yaw: f32 = 0,
orbit_pitch: f32 = -0.15,
orbit_distance: f32 = 1.5,
dragging: bool = false,
stroke_open: bool = false,
anchor: V = .{ 0, 0, 0 },
plane_normal: V = .{ 0, 0, 1 },
/// Model-space point under the pointer, for the brush ring.
hover: ?V = null,
parts_saved: u32 = 0,
/// Selected vertices on screen (normalised 0..1, y down), refreshed each frame by `refreshOverlay`.
/// Fixed capacity, allocated at bind, so the frame path does not allocate.
overlay: [][2]f32 = &.{},
overlay_len: usize = 0,
/// Brush ring on screen: centre x, y and radius as a fraction of screen height.
ring: ?[3]f32 = null,
status_buffer: [80]u8 = @splat(0),
status_len: usize = 0,

pub fn init(allocator: std.mem.Allocator) MeshTools {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *MeshTools) void {
    self.unbind();
}

/// Starts editing `model` (which must be allocated with this allocator). `mirror` is the base
/// copy a part-appearance bake rebuilds from; it is kept in step after every stroke.
pub fn bind(self: *MeshTools, model: *Model, mirror: ?*Model) MeshEdit.Error!void {
    self.unbind();
    var editor = try MeshEdit.Editor.init(self.allocator, model);
    errdefer editor.deinit();
    try editor.setMirror(mirror);
    const overlay = try self.allocator.alloc([2]f32, max_overlay);
    self.editor = editor;
    self.overlay = overlay;
    self.overlay_len = 0;
    self.active = true;
    self.setStatus("{d} VERTICES", .{model.mesh.vertices.len});
}

pub fn unbind(self: *MeshTools) void {
    self.endStroke();
    if (self.editor) |*e| e.deinit();
    self.editor = null;
    self.allocator.free(self.overlay);
    self.overlay = &.{};
    self.overlay_len = 0;
    self.ring = null;
    self.active = false;
    self.dragging = false;
}

pub fn bound(self: *const MeshTools, model: *const Model) bool {
    return if (self.editor) |e| e.model == model else false;
}

pub fn status(self: *const MeshTools) []const u8 {
    return self.status_buffer[0..self.status_len];
}

fn setStatus(self: *MeshTools, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&self.status_buffer, fmt, args) catch self.status_buffer[0..0];
    self.status_len = text.len;
}

pub fn height(self: *const MeshTools) f32 {
    const e = self.editor orelse return 1;
    return @max(e.model.bounds_max[1] - e.model.bounds_min[1], 1e-4);
}

pub fn penName(pen: u8) []const u8 {
    if (pen >= pen_count) return "?";
    return @tagName(@as(CharacterMesh.Material, @enumFromInt(pen)));
}

// ---- Placement ---------------------------------------------------------------------------

pub fn toModelPoint(self: *const MeshTools, w: V) V {
    const d = sub(w, self.base);
    const c = @cos(-self.yaw);
    const s = @sin(-self.yaw);
    return scale(.{ c * d[0] + s * d[2], d[1], -s * d[0] + c * d[2] }, 1 / self.model_scale);
}

pub fn toWorldPoint(self: *const MeshTools, p: V) V {
    const q = scale(p, self.model_scale);
    const c = @cos(self.yaw);
    const s = @sin(self.yaw);
    return add(self.base, .{ c * q[0] + s * q[2], q[1], -s * q[0] + c * q[2] });
}

pub fn toModelRay(self: *const MeshTools, ray: Ray) Ray {
    const origin = self.toModelPoint(ray.origin);
    const tip = self.toModelPoint(add(ray.origin, ray.direction));
    return .{ .origin = origin, .direction = normalize(sub(tip, origin)) };
}

/// Model-space centre of the model's bounds, in world space: what the orbit camera looks at.
pub fn focus(self: *const MeshTools) V {
    const e = self.editor orelse return self.base;
    return self.toWorldPoint(scale(add(e.model.bounds_min, e.model.bounds_max), 0.5));
}

pub fn orbit(self: *MeshTools, dx: f32, dy: f32) void {
    self.orbit_yaw = @mod(self.orbit_yaw + dx * 0.008, 2 * std.math.pi);
    self.orbit_pitch = std.math.clamp(self.orbit_pitch - dy * 0.006, -1.4, 1.4);
}

pub fn zoom(self: *MeshTools, steps: f32) void {
    self.orbit_distance = std.math.clamp(self.orbit_distance * std.math.pow(f32, 0.9, steps), 0.25, 6);
}

/// Points `camera` at the model from the orbit angles, relative to the model's facing.
pub fn aim(self: *const MeshTools, camera: *Camera) void {
    camera.yaw = self.yaw + std.math.pi + self.orbit_yaw;
    camera.pitch = self.orbit_pitch;
    const f = camera.forward();
    const target = self.focus();
    const distance = self.orbit_distance * self.height() * self.model_scale;
    camera.position = math.vec3(target[0] - f.x() * distance, target[1] - f.y() * distance, target[2] - f.z() * distance);
}

/// World point to normalised screen coordinates (0..1, y down), matching `Scene3D.screenRay`.
pub fn project(camera: Camera, aspect: f32, w: V) ?[2]f32 {
    const f3 = camera.forward();
    const f: V = .{ f3.x(), f3.y(), f3.z() };
    const r: V = .{ @cos(camera.yaw), 0, -@sin(camera.yaw) };
    const u = cross(f, r);
    const d = sub(w, .{ camera.position.x(), camera.position.y(), camera.position.z() });
    const depth = dot(d, f);
    if (depth <= camera.near) return null;
    const t = @tan(camera.fov * 0.5);
    return .{ 0.5 + dot(d, r) / (depth * aspect * t) / 2, 0.5 - dot(d, u) / (depth * t) / 2 };
}

/// Projects the selection and the brush ring for the panel to draw. Selections larger than the
/// overlay show an even sample of their vertices.
pub fn refreshOverlay(self: *MeshTools, camera: Camera, aspect: f32) void {
    self.overlay_len = 0;
    self.ring = null;
    const e = self.editor orelse return;
    const count = e.selection.count();
    const stride = @max(1, count / max_overlay + 1);
    var it = e.selection.iterator(.{});
    var k: usize = 0;
    while (it.next()) |i| : (k += 1) {
        if (k % stride != 0 or self.overlay_len >= self.overlay.len) continue;
        const p = project(camera, aspect, self.toWorldPoint(e.model.mesh.vertices[i].position)) orelse continue;
        self.overlay[self.overlay_len] = p;
        self.overlay_len += 1;
    }
    const brushes = switch (self.tool) {
        .select, .draw, .inflate, .smooth, .grab, .paint, .pen => true,
        else => false,
    };
    if (!brushes) return;
    const hover = self.hover orelse return;
    const centre_world = self.toWorldPoint(hover);
    const centre = project(camera, aspect, centre_world) orelse return;
    // Radius on screen: project a point one brush radius away across the view.
    const r: V = .{ @cos(camera.yaw), 0, -@sin(camera.yaw) };
    const edge = project(camera, aspect, add(centre_world, scale(r, self.radius * self.height() * self.model_scale))) orelse return;
    self.ring = .{ centre[0], centre[1], @abs(edge[0] - centre[0]) * aspect };
}

// ---- Pointer -----------------------------------------------------------------------------

/// Tracks the surface under the pointer (for the brush ring) without editing.
pub fn hoverAt(self: *MeshTools, world_ray: Ray) void {
    const e = &(self.editor orelse return);
    const ray = self.toModelRay(world_ray);
    self.hover = if (e.raycast(ray.origin, ray.direction)) |hit| hit.point else null;
}

pub fn press(self: *MeshTools, world_ray: Ray, extend: bool) MeshEdit.Error!void {
    const e = &(self.editor orelse return);
    const ray = self.toModelRay(world_ray);
    const hit = e.raycast(ray.origin, ray.direction);
    self.hover = if (hit) |h| h.point else null;
    self.view_dir = ray.direction;
    self.dragging = true;
    self.plane_normal = scale(ray.direction, -1);
    switch (self.tool) {
        .select => {
            if (!extend) e.clearSelection();
            if (hit) |h| e.selectVertex(h.vertex, true);
            self.dragging = hit != null;
        },
        .pick => {
            if (hit) |h| {
                const got = e.sample(h.vertex);
                self.setColor(got.color);
                self.pen = got.pen;
                self.setStatus("PICKED COLOUR AND PEN {s}", .{penName(got.pen)});
            }
            self.dragging = false;
        },
        .split => {
            if (!extend) e.clearSelection();
            if (hit) |h| {
                e.selectVertex(h.vertex, true);
                try e.selectLinked();
                self.setStatus("{d} VERTICES IN THIS PIECE  |  TEAR OFF TO SAVE IT AS A PART", .{e.selectedCount()});
            }
            self.dragging = false;
        },
        .move => {
            if (e.selectedCount() == 0) if (hit) |h| e.selectVertex(h.vertex, true);
            if (e.selectedCount() == 0) {
                self.dragging = false;
                return;
            }
            try e.prepareSoft(self.soft * self.height());
            self.anchor = if (hit) |h| h.point else self.selectionCentre();
            self.beginStroke();
        },
        .grab => {
            const h = hit orelse {
                self.dragging = false;
                return;
            };
            e.prepareAround(h.point, self.radius * self.height());
            self.anchor = h.point;
            self.beginStroke();
        },
        .draw, .inflate, .smooth, .paint, .pen => {
            self.beginStroke();
            if (hit) |h| try self.dab(h.point);
        },
    }
}

pub fn drag(self: *MeshTools, world_ray: Ray) MeshEdit.Error!void {
    if (!self.dragging) return self.hoverAt(world_ray);
    const e = &(self.editor orelse return);
    const ray = self.toModelRay(world_ray);
    self.view_dir = ray.direction;
    switch (self.tool) {
        .select => if (e.raycast(ray.origin, ray.direction)) |h| {
            self.hover = h.point;
            e.selectSphere(h.point, self.radius * self.height(), true);
        },
        .move, .grab => {
            const denom = dot(ray.direction, self.plane_normal);
            if (@abs(denom) < 1e-6) return;
            const t = dot(sub(self.anchor, ray.origin), self.plane_normal) / denom;
            const point = add(ray.origin, scale(ray.direction, t));
            try e.move(sub(point, self.anchor));
            self.anchor = point;
        },
        .draw, .inflate, .smooth, .paint, .pen => if (e.raycast(ray.origin, ray.direction)) |h| {
            self.hover = h.point;
            try self.dab(h.point);
        },
        .split, .pick => {},
    }
}

pub fn release(self: *MeshTools) void {
    self.dragging = false;
    self.endStroke();
}

fn beginStroke(self: *MeshTools) void {
    if (self.stroke_open) return;
    if (self.editor) |*e| e.begin();
    self.stroke_open = true;
}

fn endStroke(self: *MeshTools) void {
    if (!self.stroke_open) return;
    self.stroke_open = false;
    if (self.editor) |*e| e.end() catch self.setStatus("OUT OF MEMORY: LAST STROKE NOT UNDOABLE", .{});
}

fn dab(self: *MeshTools, center: V) MeshEdit.Error!void {
    const e = &(self.editor orelse return);
    const brush: MeshEdit.Brush = switch (self.tool) {
        .draw => .draw,
        .inflate => .inflate,
        .smooth => .smooth,
        .paint => .paint,
        .pen => .pen,
        else => return,
    };
    // Shape brushes take small steps per dab; colour and pens apply at full strength.
    const strength = switch (brush) {
        .paint => self.strength,
        .pen => 1,
        else => self.strength * 0.25,
    };
    try e.dab(brush, .{
        .center = center,
        .radius = self.radius * self.height(),
        .strength = strength,
        .color = self.color,
        .pen = self.pen,
        .masked = self.masked,
        .hardness = if (brush == .paint) self.hardness else 0,
        .blend = self.blend,
        .mirror = self.mirror,
        .facing = if (self.backface) self.view_dir else null,
    });
}

fn selectionCentre(self: *const MeshTools) V {
    const e = self.editor orelse return .{ 0, 0, 0 };
    var sum: V = .{ 0, 0, 0 };
    var it = e.selection.iterator(.{});
    var n: f32 = 0;
    while (it.next()) |i| {
        sum = add(sum, e.model.mesh.vertices[i].position);
        n += 1;
    }
    return if (n > 0) scale(sum, 1 / n) else sum;
}

pub fn setColor(self: *MeshTools, rgb: [3]f32) void {
    self.color = rgb;
    self.hsv = rgbToHsv(rgb);
}

pub fn applyPreset(self: *MeshTools, index: u8) void {
    const p = presets[index];
    self.preset = index;
    self.radius = p.radius;
    self.strength = p.strength;
    self.hardness = p.hardness;
    self.blend = p.blend;
    if (self.tool != .paint) self.setTool(.paint);
    self.setStatus("BRUSH: {s}", .{p.name});
}

pub fn rgbToHsv(c: [3]f32) [3]f32 {
    const hi = @max(c[0], @max(c[1], c[2]));
    const lo = @min(c[0], @min(c[1], c[2]));
    const d = hi - lo;
    var h: f32 = 0;
    if (d > 1e-6) {
        if (hi == c[0]) {
            h = @mod((c[1] - c[2]) / d, 6);
        } else if (hi == c[1]) {
            h = (c[2] - c[0]) / d + 2;
        } else h = (c[0] - c[1]) / d + 4;
        h /= 6;
    }
    return .{ h, if (hi > 1e-6) d / hi else 0, hi };
}

pub fn hsvToRgb(hsv: [3]f32) [3]f32 {
    const h = @mod(hsv[0], 1) * 6;
    const c = hsv[2] * hsv[1];
    const x = c * (1 - @abs(@mod(h, 2) - 1));
    const m = hsv[2] - c;
    const rgb: [3]f32 = if (h < 1) .{ c, x, 0 } else if (h < 2) .{ x, c, 0 } else if (h < 3) .{ 0, c, x } else if (h < 4) .{ 0, x, c } else if (h < 5) .{ x, 0, c } else .{ c, 0, x };
    return .{ rgb[0] + m, rgb[1] + m, rgb[2] + m };
}

// ---- Panel and keys ----------------------------------------------------------------------

pub fn setTool(self: *MeshTools, tool: Tool) void {
    self.release();
    self.tool = tool;
    // The hint is already on the panel under the tool buttons.
    self.setStatus("TOOL: {s}", .{tool_labels[@intFromEnum(tool)]});
}

/// A panel button or shortcut. Returns what `App` must do (file output, closing).
pub fn control(self: *MeshTools, c: Control) MeshEdit.Error!Action {
    const e = &(self.editor orelse return if (c == .close) .close else .none);
    if (self.dragging) self.release();
    switch (c) {
        .radius_down, .radius_up => self.radius = std.math.clamp(self.radius * (if (c == .radius_up) @as(f32, 1.25) else 0.8), 0.005, 0.5),
        .strength_down, .strength_up => self.strength = std.math.clamp(self.strength + (if (c == .strength_up) @as(f32, 0.1) else -0.1), 0.05, 1),
        .soft_down, .soft_up => self.soft = std.math.clamp(self.soft + (if (c == .soft_up) @as(f32, 0.04) else -0.04), 0, 0.6),
        .pen_down, .pen_up => self.pen = @intCast(@mod(@as(i32, self.pen) + (if (c == .pen_up) @as(i32, 1) else -1), pen_count)),
        .masked => self.masked = !self.masked,
        .grow => try e.growSelection(),
        .linked => try e.selectLinked(),
        .invert => e.invertSelection(),
        .clear => e.clearSelection(),
        .same_pen, .same_color => {
            var it = e.selection.iterator(.{});
            const first = it.next() orelse {
                self.setStatus("SELECT A VERTEX FIRST", .{});
                return .none;
            };
            e.selectSimilar(@intCast(first), if (c == .same_pen) .pen else .color, 0.02);
        },
        .fill_color, .fill_pen => {
            if (e.selectedCount() == 0) {
                self.setStatus("SELECT VERTICES FIRST", .{});
                return .none;
            }
            e.begin();
            defer e.end() catch {};
            if (c == .fill_color) try e.fillSelection(self.color) else try e.fillSelectionPen(self.pen);
        },
        .undo => _ = try e.undo(),
        .redo => _ = try e.redo(),
        .tear_off => return .tear_off,
        .close => return .close,
        .open => {},
        .mirror => self.mirror = !self.mirror,
        .backface => self.backface = !self.backface,
        .hue_down, .hue_up => {
            self.hsv[0] = @mod(self.hsv[0] + (if (c == .hue_up) @as(f32, 1) else -1) / 24.0, 1);
            self.color = hsvToRgb(self.hsv);
        },
        .sat_down, .sat_up, .val_down, .val_up => {
            const k: usize = if (c == .sat_down or c == .sat_up) 1 else 2;
            const up = c == .sat_up or c == .val_up;
            self.hsv[k] = std.math.clamp(self.hsv[k] + (if (up) @as(f32, 0.1) else -0.1), 0, 1);
            self.color = hsvToRgb(self.hsv);
        },
        .preset_down, .preset_up => {
            const n: i32 = @intCast(presets.len);
            self.applyPreset(@intCast(@mod(@as(i32, self.preset) + (if (c == .preset_up) @as(i32, 1) else -1), n)));
        },
        .blend_cycle => self.blend = @enumFromInt(@as(u2, @intFromEnum(self.blend)) +% 1),
        .hardness_down, .hardness_up => self.hardness = std.math.clamp(self.hardness + (if (c == .hardness_up) @as(f32, 0.1) else -0.1), 0, 0.95),
        else => {
            const row = @intFromEnum(c);
            if (row >= @intFromEnum(Control.swatch_first) and row < @intFromEnum(Control.swatch_first) + swatches.len) {
                self.setColor(swatches[row - @intFromEnum(Control.swatch_first)]);
            } else if (row < tool_labels.len) self.setTool(@enumFromInt(row));
        },
    }
    return .none;
}

/// Copies the selected faces into a new standalone model (caller owns it) and removes them from
/// the edited mesh as one undo step.
pub fn tearOff(self: *MeshTools, allocator: std.mem.Allocator) MeshEdit.Error!Model {
    const e = &(self.editor orelse return error.EmptySelection);
    var part = try e.extract(allocator, null);
    errdefer part.deinit(allocator);
    e.begin();
    defer e.end() catch {};
    _ = try e.separate();
    self.parts_saved += 1;
    return part;
}

fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn scale(a: V, s: f32) V {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: V, b: V) V {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn normalize(a: V) V {
    const l = @sqrt(dot(a, a));
    return if (l > 1e-12) scale(a, 1 / l) else .{ 0, 0, 1 };
}

// ---- Tests -------------------------------------------------------------------------------

fn testTools(model: *Model) !MeshTools {
    var tools = MeshTools.init(std.testing.allocator);
    errdefer tools.deinit();
    try tools.bind(model, null);
    // Placed 10 m east, turned a quarter, twice size: rays must still land on the right vertices.
    tools.base = .{ 10, 0, 0 };
    tools.yaw = std.math.pi / 2.0;
    tools.model_scale = 2;
    return tools;
}

test "placement round-trips points and rays between world and model space" {
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = try testTools(&model);
    defer tools.deinit();
    const p: V = .{ 0.3, 1.2, -0.4 };
    const back = tools.toModelPoint(tools.toWorldPoint(p));
    for (p, back) |x, y| try std.testing.expectApproxEqAbs(x, y, 1e-5);
    // A ray straight down onto the cube's top face (model y = 2) hits it.
    const top = tools.toWorldPoint(.{ 0.1, 2, 0.1 });
    tools.hoverAt(.{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } });
    try std.testing.expectApproxEqAbs(@as(f32, 2), tools.hover.?[1], 1e-4);
}

test "move tool drags the clicked corner with the pointer and undoes in one step" {
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = try testTools(&model);
    defer tools.deinit();
    tools.soft = 0;
    tools.setTool(.move);
    const corner = tools.toWorldPoint(.{ 0.49, 2, 0.49 });
    try tools.press(.{ .origin = .{ corner[0], 20, corner[2] }, .direction = .{ 0, -1, 0 } }, false);
    try std.testing.expectEqual(@as(usize, 3), tools.editor.?.selectedCount());
    // Dragging sideways in world x moves the corner along the view plane (horizontal here).
    try tools.drag(.{ .origin = .{ corner[0] + 1, 20, corner[2] }, .direction = .{ 0, -1, 0 } });
    tools.release();
    // The model is turned a quarter and doubled, so one world metre along x is half a metre along
    // model z for the three copies of the corner.
    var moved: usize = 0;
    for (model.mesh.vertices) |v| if (@abs(@abs(v.position[2]) - 0.5) > 1e-4) {
        moved += 1;
        try std.testing.expectApproxEqAbs(@as(f32, 0.5), @abs(v.position[2]) - 0.5, 1e-3);
    };
    try std.testing.expectEqual(@as(usize, 3), moved);
    try std.testing.expectEqual(Action.none, try tools.control(.undo));
    for (model.mesh.vertices) |v| try std.testing.expect(@abs(@abs(v.position[2]) - 0.5) < 1e-5);
}

test "pen tool paints a cel material and split tears a piece off as its own model" {
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = try testTools(&model);
    defer tools.deinit();
    tools.setTool(.pen);
    tools.radius = 1;
    const top = tools.toWorldPoint(.{ 0, 2, 0 });
    try tools.press(.{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } }, false);
    tools.release();
    try std.testing.expectEqual(@intFromEnum(CharacterMesh.Material.armor), tools.editor.?.penOf(model.mesh.indices[4 * 6]));
    tools.setTool(.split);
    try tools.press(.{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } }, false);
    try std.testing.expectEqual(@as(usize, 24), tools.editor.?.selectedCount());
    try std.testing.expectEqual(Action.tear_off, try tools.control(.tear_off));
    var part = try tools.tearOff(a);
    defer part.deinit(a);
    try std.testing.expectEqual(@as(usize, 36), part.mesh.indices.len);
    try std.testing.expect(part.pens != null);
    tools.hoverAt(.{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } });
    try std.testing.expect(tools.hover == null);
    _ = try tools.control(.undo);
    tools.hoverAt(.{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } });
    try std.testing.expect(tools.hover != null);
}

test "panel controls clamp brush settings and pick tools and swatches" {
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = try testTools(&model);
    defer tools.deinit();
    for (0..40) |_| _ = try tools.control(.radius_up);
    try std.testing.expectEqual(@as(f32, 0.5), tools.radius);
    _ = try tools.control(@enumFromInt(@intFromEnum(Tool.smooth)));
    try std.testing.expectEqual(Tool.smooth, tools.tool);
    _ = try tools.control(@enumFromInt(@intFromEnum(Control.swatch_first) + 6));
    try std.testing.expectEqual(swatches[6], tools.color);
    _ = try tools.control(.pen_down);
    try std.testing.expectEqual(@intFromEnum(CharacterMesh.Material.accent), tools.pen);
    try std.testing.expectEqual(Action.close, try tools.control(.close));
}

test "HSV round-trips, presets set the brush, and the pick tool reads the mesh" {
    for (swatches) |c| {
        const back = hsvToRgb(rgbToHsv(c));
        for (c, back) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-5);
    }
    const a = std.testing.allocator;
    var model = try Model.fromMesh(a, try Mesh.cube(a), .{});
    defer model.deinit(a);
    var tools = try testTools(&model);
    defer tools.deinit();
    _ = try tools.control(.preset_up);
    try std.testing.expectEqual(Tool.paint, tools.tool);
    try std.testing.expectEqual(MeshEdit.Blend.mix, tools.blend);
    try std.testing.expectEqual(@as(f32, 0.85), tools.hardness);
    // Hue steps keep saturation and value.
    const before = tools.hsv;
    _ = try tools.control(.hue_up);
    try std.testing.expectApproxEqAbs(before[1], rgbToHsv(tools.color)[1], 1e-4);
    // Paint the top face, then pick it back up after changing colour.
    tools.setColor(.{ 0.1, 0.6, 0.2 });
    tools.radius = 1;
    const top = tools.toWorldPoint(.{ 0, 2, 0 });
    const down: Ray = .{ .origin = .{ top[0], 20, top[2] }, .direction = .{ 0, -1, 0 } };
    try tools.press(down, false);
    tools.release();
    tools.setColor(.{ 1, 1, 1 });
    tools.setTool(.pick);
    try tools.press(down, false);
    try std.testing.expect(tools.color[1] > tools.color[0]);
}
