//! Skinned characters, shared by all local views. On the GPU path (the default) each character
//! uploads its bind-pose mesh once and, when its pose changes, only its joint palette (one dual
//! quaternion per joint, 2 KiB); the skinned pipeline blends it per vertex. Characters with
//! more joints than the palette holds, or every character with `-Dcpu-skinning=true`, are
//! skinned on the CPU into their own vertex buffer, as before.
const std = @import("std");
const mach = @import("mach");
const gpu = @import("mach").gpu;
const Ranger = @import("../character/Ranger.zig");
const World = @import("../world/World.zig");
const GpuMesh = @import("GpuMesh.zig");
const Instance = @import("StreamingScene.zig").Instance;
const R = @import("../physics/Rotation.zig");
const FrameStats = @import("../engine/FrameStats.zig");
const Characters = @This();
/// A character's static GPU-skinned mesh.
pub const SkinnedMesh = struct {
    vertices: *gpu.Buffer,
    indices: *gpu.Buffer,
    vertex_bytes: usize,
    index_count: u32,

    fn deinit(self: SkinnedMesh) void {
        self.indices.release();
        self.vertices.release();
    }
};
/// The skinned pipeline's resources, owned by the renderer: the pipeline, the palette uniform
/// buffer (one `Ranger.palette_bytes` slot per character id) and its bind group.
pub const Skinning = struct { pipeline: *gpu.RenderPipeline, palette: *gpu.Buffer, group: *gpu.BindGroup };
const Slot = struct { ranger: Ranger, gpu_mesh: ?GpuMesh = null, skinned: ?SkinnedMesh = null };
slots: [Ranger.capacity]?Slot = @splat(null),
/// Set by the renderer when the skinned pipeline exists; null skins every character on the CPU.
skinning: ?Skinning = null,
visible: [Ranger.capacity]bool = @splat(false),
owners: [Ranger.capacity]u8 = @splat(0),
instances: ?*gpu.Buffer = null,

pub fn prepare(self: *Characters, a: std.mem.Allocator, io: std.Io, device: *gpu.Device, encoder: *gpu.CommandEncoder, props: []const World.Prop, visible_ids: [Ranger.capacity]bool, skin_times: ?*FrameStats) !void {
    self.visible = @splat(false);
    var skin_timer = if (skin_times != null) mach.time.Timer.start(io) else undefined;
    var skin_ns: u64 = 0;
    var transforms: [Ranger.capacity]Instance = @splat(.{ .translation_scale = .{ 0, 0, 0, 1 }, .tint = .{ 1, 1, 1, 1 } });
    for (props) |prop| {
        const descriptor = prop.character orelse continue;
        const i = descriptor.id;
        if (i >= Ranger.capacity or !visible_ids[i]) continue;
        var upload_vertices = false;
        if (self.slots[i] == null or !Ranger.sameAppearance(self.slots[i].?.ranger.profile, descriptor.profile)) {
            // Finish the replacement before releasing the live appearance.
            var ranger = try Ranger.init(a, descriptor.profile);
            errdefer ranger.deinit(a);
            var next: Slot = .{ .ranger = ranger };
            if (self.skinning != null and ranger.gpuSkinnable()) {
                const vertices = try ranger.skinnedVertices(a);
                defer a.free(vertices);
                const bytes = std.mem.sliceAsBytes(vertices);
                const vb = device.createBuffer(&.{ .label = "skinned character vertices", .size = bytes.len, .usage = .{ .vertex = true, .copy_dst = true } });
                const ib = device.createBuffer(&.{ .label = "skinned character indices", .size = ranger.mesh.indices.len * 4, .usage = .{ .index = true, .copy_dst = true } });
                encoder.writeBuffer(vb, 0, vertices);
                encoder.writeBuffer(ib, 0, ranger.mesh.indices);
                next.skinned = .{ .vertices = vb, .indices = ib, .vertex_bytes = bytes.len, .index_count = @intCast(ranger.mesh.indices.len) };
                // The palette is written for the first pose below, whatever it is.
                next.ranger.last_pose = null;
            } else {
                const mesh = GpuMesh.allocate(device, ranger.mesh.vertices.len, ranger.mesh.indices.len);
                encoder.writeBuffer(mesh.indices, 0, ranger.mesh.indices);
                next.gpu_mesh = mesh;
            }
            if (self.slots[i]) |*old| {
                if (old.gpu_mesh) |m| m.deinit();
                if (old.skinned) |m| m.deinit();
                old.ranger.deinit(a);
            }
            self.slots[i] = next;
            upload_vertices = true;
        }
        const slot = &self.slots[i].?;
        if (skin_times != null) skin_timer.reset();
        if (slot.skinned != null) {
            // GPU path: only the joint palette changes.
            var palette: Ranger.Palette = undefined;
            if (slot.ranger.posePalette(descriptor.pose, &palette)) {
                const joints = slot.ranger.character.skeleton.count();
                encoder.writeBuffer(self.skinning.?.palette, @as(u64, i) * Ranger.palette_bytes, palette[0 .. joints * 2]);
            }
        } else {
            upload_vertices = slot.ranger.update(descriptor.pose) or upload_vertices;
        }
        if (skin_times != null) skin_ns += skin_timer.lapPrecise();
        if (upload_vertices) if (slot.gpu_mesh) |m| encoder.writeBuffer(m.vertices, 0, slot.ranger.mesh.vertices);
        self.visible[i] = true;
        self.owners[i] = prop.owner;
        transforms[i] = .{ .translation_scale = descriptor.pose.feet ++ [_]f32{1}, .tint = .{ 1, 1, 1, 1 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, descriptor.pose.yaw) };
    }
    if (self.instances == null) self.instances = device.createBuffer(&.{ .label = "character transforms", .size = @sizeOf(@TypeOf(transforms)), .usage = .{ .vertex = true, .copy_dst = true } });
    encoder.writeBuffer(self.instances.?, 0, &transforms);
    if (skin_times) |stats| stats.record(@as(f32, @floatFromInt(skin_ns)) / 1_000_000);
}
/// Draws every visible character for a view: CPU-skinned ones with the pipeline already set,
/// then GPU-skinned ones with the skinned pipeline (each with its palette slot), and leaves
/// `scene_pipeline` and the view's frame bind group set again for whatever draws next.
pub fn draw(self: *const Characters, pass: *gpu.RenderPassEncoder, hide_owner: u8, frame_group: *gpu.BindGroup, scene_pipeline: *gpu.RenderPipeline) void {
    const instances = self.instances orelse return;
    pass.setVertexBuffer(1, instances, 0, Ranger.capacity * @sizeOf(Instance));
    var any_skinned = false;
    for (self.slots, self.visible, self.owners, 0..) |slot, visible, owner, i| {
        if (!visible or (hide_owner != 0 and owner == hide_owner)) continue;
        const s = slot orelse continue;
        if (s.gpu_mesh) |m| m.draw(pass, 1, @intCast(i));
        any_skinned = any_skinned or s.skinned != null;
    }
    const skinning = self.skinning orelse return;
    if (!any_skinned) return;
    pass.setPipeline(skinning.pipeline);
    pass.setBindGroup(0, frame_group, &.{});
    for (self.slots, self.visible, self.owners, 0..) |slot, visible, owner, i| {
        if (!visible or (hide_owner != 0 and owner == hide_owner)) continue;
        const m = (slot orelse continue).skinned orelse continue;
        pass.setBindGroup(1, skinning.group, &.{@as(u32, @intCast(i * Ranger.palette_bytes))});
        pass.setVertexBuffer(0, m.vertices, 0, m.vertex_bytes);
        pass.setIndexBuffer(m.indices, .uint32, 0, m.index_count * 4);
        pass.drawIndexed(m.index_count, 1, 0, 0, @intCast(i));
    }
    pass.setPipeline(scene_pipeline);
    pass.setBindGroup(0, frame_group, &.{});
}
pub fn deinit(self: *Characters, a: std.mem.Allocator) void {
    for (&self.slots) |*slot| if (slot.*) |*s| {
        if (s.gpu_mesh) |m| m.deinit();
        if (s.skinned) |m| m.deinit();
        s.ranger.deinit(a);
        slot.* = null;
    };
    if (self.instances) |b| b.release();
    self.instances = null;
}
