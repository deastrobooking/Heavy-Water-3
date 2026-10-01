//! One persistent CPU skinning/GPU vertex buffer per character, shared by all local views.
const std = @import("std");
const gpu = @import("mach").gpu;
const Ranger = @import("../character/Ranger.zig");
const World = @import("../world/World.zig");
const GpuMesh = @import("GpuMesh.zig");
const Instance = @import("StreamingScene.zig").Instance;
const R = @import("../physics/Rotation.zig");
const Characters = @This();
const Slot = struct { ranger: Ranger, gpu_mesh: GpuMesh };
slots: [Ranger.capacity]?Slot = @splat(null),
visible: [Ranger.capacity]bool = @splat(false),
owners: [Ranger.capacity]u8 = @splat(0),
instances: ?*gpu.Buffer = null,

pub fn prepare(self: *Characters, a: std.mem.Allocator, device: *gpu.Device, encoder: *gpu.CommandEncoder, props: []const World.Prop) !void {
    self.visible = @splat(false);
    var transforms: [Ranger.capacity]Instance = @splat(.{ .translation_scale = .{ 0, 0, 0, 1 }, .tint = .{ 1, 1, 1, 1 } });
    for (props) |prop| {
        const descriptor = prop.character orelse continue;
        const i = descriptor.id;
        if (i >= Ranger.capacity) continue;
        if (self.slots[i] == null or !Ranger.sameAppearance(self.slots[i].?.ranger.profile, descriptor.profile)) {
            // Finish the replacement before releasing the live appearance.
            const ranger = try Ranger.init(a, descriptor.profile);
            const mesh = GpuMesh.allocate(device, ranger.mesh.vertices.len, ranger.mesh.indices.len);
            encoder.writeBuffer(mesh.indices, 0, ranger.mesh.indices);
            if (self.slots[i]) |*old| {
                old.gpu_mesh.deinit();
                old.ranger.deinit(a);
            }
            self.slots[i] = .{ .ranger = ranger, .gpu_mesh = mesh };
        }
        const slot = &self.slots[i].?;
        slot.ranger.update(descriptor.pose);
        encoder.writeBuffer(slot.gpu_mesh.vertices, 0, slot.ranger.mesh.vertices);
        self.visible[i] = true;
        self.owners[i] = prop.owner;
        transforms[i] = .{ .translation_scale = descriptor.pose.feet ++ [_]f32{1}, .tint = .{ 1, 1, 1, 1 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, descriptor.pose.yaw) };
    }
    if (self.instances == null) self.instances = device.createBuffer(&.{ .label = "character transforms", .size = @sizeOf(@TypeOf(transforms)), .usage = .{ .vertex = true, .copy_dst = true } });
    encoder.writeBuffer(self.instances.?, 0, &transforms);
}
pub fn draw(self: *const Characters, pass: *gpu.RenderPassEncoder, hide_owner: u8) void {
    const instances = self.instances orelse return;
    pass.setVertexBuffer(1, instances, 0, Ranger.capacity * @sizeOf(Instance));
    for (self.slots, self.visible, self.owners, 0..) |slot, visible, owner, i| {
        if (!visible or (hide_owner != 0 and owner == hide_owner)) continue;
        if (slot) |s| s.gpu_mesh.draw(pass, 1, @intCast(i));
    }
}
pub fn deinit(self: *Characters, a: std.mem.Allocator) void {
    for (&self.slots) |*slot| if (slot.*) |*s| {
        s.gpu_mesh.deinit();
        s.ranger.deinit(a);
        slot.* = null;
    };
    if (self.instances) |b| b.release();
    self.instances = null;
}
