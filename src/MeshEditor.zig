//! Standalone source-linked Captain mesh authoring tool.
const std = @import("std");
const mach = @import("mach");
const World = @import("world/World.zig");
const Renderer = @import("render/Renderer.zig");
const Catalog = @import("asset/Catalog.zig");
const Model = @import("asset/Model.zig");
const Modifiers = @import("asset/Modifiers.zig");
const Gltf = @import("asset/Gltf.zig");
const Meta = @import("asset/Meta.zig");
const Camera = @import("world/Camera.zig");
const Canvas = @import("ui/Canvas.zig");
const Editor = @This();

pub const Modules = mach.Modules(.{ mach.Core, Editor, World, Renderer });
pub const mach_module = .app;
pub const mach_systems = .{ .main, .init, .start, .tick, .update, .publish, .stop, .deinit };
pub const main = mach.schedule(.{
    .{ mach.Core, .init }, .{ World, .init }, .{ Editor, .init }, .{ Renderer, .init }, .{ Editor, .start }, .{ mach.Core, .main },
});
pub const tick = mach.schedule(.{ .{ Editor, .update }, .{ mach.Core, .snapshotStart }, .{ Editor, .publish }, .{ mach.Core, .snapshotEnd } });
pub const deinit = mach.schedule(.{ .{ Editor, .stop }, .{ Renderer, .deinit }, .{ World, .deinit } });

allocator: std.mem.Allocator = undefined,
io: std.Io = undefined,
window: mach.ObjectID = undefined,
core: *mach.Core = undefined,
thread: mach.Thread = undefined,
catalog: *Catalog = undefined,
handle: Catalog.MeshHandle = .none,
arena: std.heap.ArenaAllocator = undefined,
document: Modifiers.Document = undefined,
original_document: Modifiers.Document = undefined,
analysis: Modifiers.Analysis = undefined,
source_model: []u8 = &.{},
source_glb: []const u8 = &.{},
selected: usize = 0,
list_offset: usize = 0,
run_pose: bool = false,
rig_joints: usize = 0,
source_clips: usize = 0,
pointer: [2]f32 = .{ -1, -1 },
scale: f32 = 1.5,
yaw: f32 = std.math.pi,
pitch: f32 = -0.08,
dirty: bool = false,
preview_dirty: bool = false,
status: []const u8 = "Captain mesh ready",
renaming: bool = false,
rename_buffer: [80]u8 = undefined,
rename_len: usize = 0,

pub fn init(self: *Editor, core: *mach.Core, world: *World, app_mod: mach.Mod(Editor), renderer_mod: mach.Mod(Renderer), io: std.Io, allocator: std.mem.Allocator) !void {
    self.* = .{ .core = core, .io = io, .allocator = allocator, .catalog = &world.catalog, .arena = std.heap.ArenaAllocator.init(allocator) };
    errdefer self.arena.deinit();
    core.on_exit = app_mod.id.deinit;
    self.window = try core.windows.new(.{ .title = "Heavy Water | Mesh Editor", .width = 1440, .height = 900, .on_render = renderer_mod.id.render });

    // The deferred Captain preview is the first catalog job. Build it synchronously here so the
    // editor opens directly into the imported asset without starting the game's content loader.
    if (world.catalog.pending_count == 0) return error.CaptainAssetMissing;
    const pending = world.catalog.pending[0];
    self.source_glb = try std.Io.Dir.cwd().readFileAlloc(io, "assets/Characters/Test+Chroma (1).glb", self.arena.allocator(), .limited(256 << 20));
    const trace = try Gltf.inspect(self.arena.allocator(), self.source_glb);
    self.rig_joints = if (trace.skins.len == 0) 0 else trace.skins[0].joint_count;
    self.source_clips = trace.animation_count;
    var base_model = try Gltf.compilePosePreview(allocator, self.source_glb, .{}, .bind);
    var base_model_owned = true;
    errdefer if (base_model_owned) base_model.deinit(allocator);
    self.source_model = try base_model.encode(allocator);
    self.document = blk: {
        const sidecar_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "tools/captain/Captain.modifiers.json", self.arena.allocator(), .limited(1 << 20));
        break :blk try std.json.parseFromSliceLeaky(Modifiers.Document, self.arena.allocator(), sidecar_bytes, .{});
    };
    self.original_document = self.document;
    self.original_document.parts = try self.arena.allocator().dupe(Modifiers.Part, self.document.parts);
    self.analysis = try Modifiers.apply(allocator, &base_model, self.document, &Meta.hashSource(self.source_glb));
    base_model_owned = false;
    try world.catalog.install(allocator, pending.handle, base_model);
    self.handle = pending.handle;
    world.catalog.pending_count = 0;
}

pub fn start(self: *Editor, core: *mach.Core, app_mod: mach.Mod(Editor), core_mod: mach.Mod(mach.Core), renderer: *Renderer) !void {
    renderer.scene.space_review = true;
    renderer.show_metrics = false;
    self.thread = try mach.startThread(core, app_mod.id.tick, core_mod, .app);
}

pub fn update(self: *Editor, core: *mach.Core) void {
    var events = core.events(.default);
    while (events.next()) |event| switch (event) {
        .close => core.exit(),
        .key_press => |key| if (self.renaming) switch (key.key) {
            .escape => self.renaming = false,
            .enter => self.commitRename(),
            .backspace => {
                if (self.rename_len > 0) self.rename_len -= 1;
            },
            else => {},
        } else switch (key.key) {
            .escape => core.exit(),
            .up => self.select(-1),
            .down => self.select(1),
            .left => self.orbit(-0.12, 0),
            .right => self.orbit(0.12, 0),
            .w => self.orbit(0, 0.08),
            .e => self.orbit(0, -0.08),
            .s => self.save() catch { self.status = "Save failed; see console"; },
            .r => self.beginRename(),
            .equal, .kp_add => self.transform(1.05),
            .minus, .kp_subtract => self.transform(@as(f32, 1) / 1.05),
            .c => self.cycleColor(),
            .p => self.togglePose(),
            else => {},
        },
        .char_input => |input| if (self.renaming and input.codepoint >= 0x20 and input.codepoint < 0x7f and self.rename_len < self.rename_buffer.len) {
            self.rename_buffer[self.rename_len] = @intCast(input.codepoint);
            self.rename_len += 1;
        },
        .mouse_motion => |motion| {
            const height: f32 = @floatFromInt(@max(core.windows.get(self.window, .height), 1));
            const virtual_scale = 720 / height;
            self.pointer = .{ @as(f32, @floatCast(motion.pos.x)) * virtual_scale, @as(f32, @floatCast(motion.pos.y)) * virtual_scale };
        },
        .mouse_press => |mouse| if (mouse.button == .left) self.selectAtPointer(),
        .mouse_scroll => |wheel| {
            if (self.pointer[0] <= 310) {
                self.select(if (wheel.yoffset > 0) -1 else 1);
            } else {
                self.scale = std.math.clamp(self.scale * (if (wheel.yoffset > 0) @as(f32, 0.9) else 1.1), 0.2, 10);
            }
        },
        else => {},
    };
}

fn select(self: *Editor, direction: isize) void {
    if (self.document.parts.len == 0) return;
    const count: isize = @intCast(self.document.parts.len);
    self.selected = @intCast(@mod(@as(isize, @intCast(self.selected)) + direction, count));
    self.list_offset = if (self.selected >= 25) self.selected - 24 else 0;
}

fn orbit(self: *Editor, yaw: f32, pitch: f32) void {
    self.yaw += yaw;
    self.pitch = std.math.clamp(self.pitch + pitch, -1.2, 1.2);
}

fn selectAtPointer(self: *Editor) void {
    const panel: f32 = 310;
    if (self.pointer[0] < 0 or self.pointer[0] > panel) return;
    const row_height: f32 = 23;
    const y = self.pointer[1] - 102;
    if (y < 0) return;
    const index = self.list_offset + @as(usize, @intFromFloat(y / row_height));
    if (index < self.document.parts.len) self.selected = index;
}

fn transform(self: *Editor, multiplier: f32) void {
    if (self.document.parts.len == 0) return;
    const part = &self.document.parts[self.selected];
    for (&part.scale) |*axis| axis.* = std.math.clamp(axis.* * multiplier, 0.1, 5);
    self.dirty = true;
    self.preview_dirty = true;
    self.status = "Component scale changed (S saves)";
}

fn beginRename(self: *Editor) void {
    if (self.document.parts.len == 0) return;
    self.renaming = true;
    const label = self.document.parts[self.selected].label;
    self.rename_len = @min(label.len, self.rename_buffer.len);
    @memcpy(self.rename_buffer[0..self.rename_len], label[0..self.rename_len]);
    self.status = "Type a label, press Enter to accept";
}

fn commitRename(self: *Editor) void {
    if (!self.renaming or self.rename_len == 0 or self.document.parts.len == 0) return;
    self.document.parts[self.selected].label = self.arena.allocator().dupe(u8, self.rename_buffer[0..self.rename_len]) catch {
        self.status = "Rename failed: out of memory";
        return;
    };
    self.renaming = false;
    self.dirty = true;
    self.status = "Component renamed (S saves)";
}

fn cycleColor(self: *Editor) void {
    if (self.document.parts.len == 0) return;
    const part = &self.document.parts[self.selected];
    part.color = if (part.color) |color| .{ color[2], color[0], color[1] } else palette(self.document, part.surface);
    self.dirty = true;
    self.preview_dirty = true;
    self.status = "Component color changed (S saves)";
}

fn togglePose(self: *Editor) void {
    self.run_pose = !self.run_pose;
    const pose: Gltf.PreviewPose = if (self.run_pose) .run else .bind;
    var model = Gltf.compilePosePreview(self.allocator, self.source_glb, .{}, pose) catch |err| {
        self.run_pose = !self.run_pose;
        std.log.err("mesh editor pose preview failed: {s}", .{@errorName(err)});
        self.status = "Pose preview failed; see console";
        return;
    };
    const encoded = model.encode(self.allocator) catch |err| {
        model.deinit(self.allocator);
        self.run_pose = !self.run_pose;
        std.log.err("mesh editor pose source encode failed: {s}", .{@errorName(err)});
        return;
    };
    model.deinit(self.allocator);
    self.allocator.free(self.source_model);
    self.source_model = encoded;
    self.preview_dirty = true;
    self.status = if (self.run_pose) "Previewing compatible game run pose" else "Previewing bind pose";
}

fn palette(doc: Modifiers.Document, surface: Modifiers.Surface) [3]f32 {
    return switch (surface) {
        .skin => doc.skin_color,
        .eyes => doc.eye_color,
        .armor => doc.armor_color,
        .energy => doc.energy_color,
        .neutral => .{ 0.82, 0.86, 0.9 },
    };
}

fn save(self: *Editor) !void {
    const json = try std.json.Stringify.valueAlloc(self.allocator, self.document, .{ .whitespace = .indent_2 });
    defer self.allocator.free(json);
    try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = "tools/captain/Captain.modifiers.json", .data = json });
    self.dirty = false;
    self.status = "Saved tools/captain/Captain.modifiers.json";
}

fn rebuild(self: *Editor) !void {
    var model = try Model.decode(self.allocator, self.source_model);
    var model_owned = true;
    errdefer if (model_owned) model.deinit(self.allocator);
    const analysis = try Modifiers.apply(self.allocator, &model, self.document, &Meta.hashSource(self.source_glb));
    self.allocator.free(self.analysis.vertex_parts);
    self.allocator.free(self.analysis.components);
    self.analysis = analysis;
    model_owned = false;
    try self.catalog.replaceHandle(self.allocator, &self.handle, model);
}

fn partIndex(parts: []const Modifiers.Part, id: u32) ?usize {
    for (parts, 0..) |part, i| if (part.id == id) return i;
    return null;
}

fn componentById(components: []const Modifiers.Component, id: u32) ?Modifiers.Component {
    for (components) |component| if (component.id == id) return component;
    return null;
}

pub fn publish(self: *Editor, renderer: *Renderer) void {
    if (self.preview_dirty) {
        self.rebuild() catch |err| {
        self.status = "Preview rebuild failed; see console";
        std.log.err("mesh editor preview rebuild failed: {s}", .{@errorName(err)});
        };
        self.preview_dirty = false;
    }
    const center_y = 0.5;
    const distance: f32 = 2.9;
    renderer.views[0].camera = .{ .position = mach.math.vec3(distance * @sin(self.yaw), center_y + distance * @sin(self.pitch), -distance * @cos(self.yaw)), .yaw = -self.yaw, .pitch = -self.pitch };
    renderer.prop_count = 1;
    renderer.props[0] = .{ .mesh = self.handle, .transform = .{ .position = .{ 0, 0, 0 }, .scale = self.scale }, .tint = .{ 1, 1, 1, 1 } };
    self.drawUi(renderer);
}

fn drawUi(self: *Editor, renderer: *Renderer) void {
    const w = @as(f32, @floatFromInt(renderer.width)) * 720 / @as(f32, @floatFromInt(@max(renderer.height, 1)));
    renderer.ui.reset(w, 720);
    const bg: Canvas.Color = .{ 0.025, 0.045, 0.075, 0.96 };
    const selected_bg: Canvas.Color = .{ 0.12, 0.35, 0.43, 0.98 };
    const text: Canvas.Color = .{ 0.84, 0.92, 0.97, 1 };
    const muted: Canvas.Color = .{ 0.48, 0.63, 0.72, 1 };
    renderer.ui.rect(.{ .x = 0, .y = 0, .w = 310, .h = 720 }, bg);
    renderer.ui.text(18, 18, "MESH EDITOR", 1.7, text);
    renderer.ui.text(18, 48, "Captain / source linked", 1, muted);
    renderer.ui.text(18, 72, "Connected components", 1.05, text);
    const visible = @min(self.document.parts.len -| self.list_offset, 25);
    for (self.document.parts[self.list_offset .. self.list_offset + visible], 0..) |part, row| {
        const index = self.list_offset + row;
        const y = 98 + @as(f32, @floatFromInt(row)) * 23;
        if (index == self.selected) renderer.ui.rect(.{ .x = 10, .y = y - 2, .w = 288, .h = 21 }, selected_bg);
        renderer.ui.print(18, y, 0.88, if (index == self.selected) text else muted, "{s}", .{part.label});
    }
    renderer.ui.rect(.{ .x = 10, .y = 690, .w = 288, .h = 20 }, if (self.dirty) .{ 0.62, 0.27, 0.08, 1 } else selected_bg);
    renderer.ui.text(18, 694, if (self.dirty) "UNSAVED" else "READY", 0.9, text);
    renderer.ui.text(330, 18, "CAPTAIN IMPORT  |  ORBIT: LEFT/RIGHT + W/E   ZOOM: WHEEL", 1, text);
    renderer.ui.print(330, 42, 1, muted, "PART: {s}   VERTICES: {d}", .{ self.document.parts[self.selected].label, self.document.parts[self.selected].vertex_count });
    renderer.ui.text(330, 66, "R rename / Enter accept    +/- scale    C color    P pose    S save", 1, muted);
    renderer.ui.print(330, 90, 1, muted, "SOURCE RIG: {d} joints | AUTHORED CLIPS: {d}", .{ self.rig_joints, self.source_clips });
    if (self.renaming) {
        renderer.ui.text(330, 114, "RENAME:", 1, text);
        renderer.ui.text(390, 114, self.rename_buffer[0..self.rename_len], 1, text);
    }
    renderer.ui.print(330, 690, 1, text, "{s}", .{self.status});
}

pub fn stop(self: *Editor) void {
    self.thread.join();
    self.allocator.free(self.analysis.vertex_parts);
    self.allocator.free(self.analysis.components);
    self.allocator.free(self.source_model);
    self.arena.deinit();
}
