const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const Streamer = @import("../world/Streamer.zig");
const Key = @import("../world/ChunkKey.zig");
const Chunk = @import("../procedural/Chunk.zig");
const Scatter = @import("../procedural/Scatter.zig");
const Camera = @import("../world/Camera.zig");
const Mesh = @import("Mesh.zig");
const GpuMesh = @import("GpuMesh.zig");
const Visibility = @import("Visibility.zig");
const Catalog = @import("../asset/Catalog.zig");
const Model = @import("../asset/Model.zig");
const World = @import("../world/World.zig");
const Modifications = @import("../world/Modifications.zig");
const Scene = @This();
/// Per-axis `stretch` (applied first) and a unit-quaternion `rotation`; the shader corrects
/// normals for the stretch and rotates them.
pub const Instance = extern struct { translation_scale: [4]f32, tint: [4]f32, stretch: [4]f32 = .{ 1, 1, 1, 0 }, rotation: [4]f32 = .{ 0, 0, 0, 1 } };
pub const max_instances = Streamer.render_capacity * Scatter.capacity + 1 + World.max_props * Model.max_submeshes;
/// One instanced draw of a catalog submesh.
const Draw = struct { mesh: *const GpuMesh, first_index: u32, index_count: u32, first_instance: u32, instances: u32 };
const max_draws = Catalog.mesh_capacity * Model.max_submeshes;
pub const chunk_bytes = Chunk.vertex_count * @sizeOf(Mesh.Vertex) + Chunk.index_count * 4;
pub const gpu_pool_bytes = Streamer.render_capacity * chunk_bytes;
const Resident = struct { mesh: GpuMesh, view: ?Streamer.View = null, visible: bool = false };

stream: *Streamer,
catalog: *const Catalog,
/// GPU copies of catalog meshes, indexed by handle slot; validated against the catalog on use.
meshes: [Catalog.mesh_capacity]?GpuMesh = @splat(null),
/// Handle generation each GPU copy was made from; a replaced catalog entry re-uploads.
mesh_generation: [Catalog.mesh_capacity]u16 = @splat(0),
/// Split-screen views draw the primary scene's catalog meshes.
shared: ?*const Scene = null,
/// Catalog meshes uploaded after setup (deferred or replaced), and their bytes this frame.
late_uploads: u32 = 0,
late_upload_bytes: usize = 0,
draws: [max_draws]Draw = undefined,
draw_count: usize = 0,
prop_count: u32 = 0,
residents: [Streamer.render_capacity]Resident = undefined,
initialized: bool = false,
/// Split-screen views after the first borrow the primary scene's catalog meshes.
owns_meshes: bool = true,
instances: [max_instances]Instance = undefined,
instance_count: u32 = 1,
relic_count: u32 = 0,
plant_count: u32 = 0,
resident_count: usize = 0,
peak_resident_count: usize = 0,
active_missing: usize = 0,
gpu_pool_allocations: u32 = 0,
terrain_draws: u32 = 0,
stats: Streamer.Stats = .{},
uploads: u64 = 0,
evictions: u64 = 0,
upload_bytes: usize = 0,
peak_upload_bytes: usize = 0,
total_upload_bytes: u64 = 0,
center_changes: u64 = 0,
last_center: ?Key = null,

pub fn init(allocator: std.mem.Allocator, io: std.Io, seed: u64, catalog: *const Catalog) !Scene {
    const stream = try Streamer.create(allocator, io, seed);
    errdefer stream.destroy();
    try stream.start();
    return .{ .stream = stream, .catalog = catalog };
}

pub fn setup(self: *Scene, device: *gpu.Device, queue: *gpu.Queue) void {
    for (&self.residents) |*resident| {
        resident.* = .{ .mesh = GpuMesh.allocate(device, Chunk.vertex_count, Chunk.index_count) };
        self.gpu_pool_allocations += 2;
    }
    self.initialized = true;
    _ = self.uploadMeshes(device, queue, std.math.maxInt(usize));
    self.late_uploads = 0;
}

/// Another view of the same world: its own streamer and terrain pool, shared catalog meshes.
pub fn setupShared(self: *Scene, device: *gpu.Device, primary: *const Scene) void {
    for (&self.residents) |*resident| {
        resident.* = .{ .mesh = GpuMesh.allocate(device, Chunk.vertex_count, Chunk.index_count) };
        self.gpu_pool_allocations += 2;
    }
    self.initialized = true;
    self.shared = primary;
    self.owns_meshes = false;
}

pub fn gpuMesh(self: *const Scene, handle: Catalog.MeshHandle) ?*const GpuMesh {
    const owner = self.shared orelse self;
    const entry = self.catalog.mesh(handle) orelse return null;
    if (!entry.ready or owner.mesh_generation[handle.index] != handle.generation) return null;
    return if (owner.meshes[handle.index]) |*mesh| mesh else null;
}

/// Uploads ready catalog meshes that have no current GPU copy, within `budget` bytes; one mesh
/// larger than the budget still goes when nothing else has this frame, so none starves.
/// Returns the bytes uploaded. Primary scene only.
pub fn uploadMeshes(self: *Scene, device: *gpu.Device, queue: *gpu.Queue, budget: usize) usize {
    var bytes: usize = 0;
    var live = self.catalog.meshes.live.iterator(.{});
    while (live.next()) |i| {
        const entry = &self.catalog.meshes.items[i];
        const generation = self.catalog.meshes.idAt(i).generation;
        if (!entry.ready or (self.meshes[i] != null and self.mesh_generation[i] == generation)) continue;
        const size = entry.model.mesh.vertices.len * @sizeOf(Mesh.Vertex) + entry.model.mesh.indices.len * 4;
        if (bytes > 0 and bytes + size > budget) break;
        if (self.meshes[i]) |old| old.deinit();
        self.meshes[i] = GpuMesh.upload(device, queue, entry.model.mesh);
        self.mesh_generation[i] = generation;
        bytes += size;
        self.late_uploads += 1;
    }
    self.late_upload_bytes = bytes;
    return bytes;
}

/// Material base color of a single-material catalog mesh (relics, vegetation).
fn baseColor(self: *const Scene, handle: Catalog.MeshHandle) [4]f32 {
    const entry = self.catalog.mesh(handle) orelse return .{ 1, 1, 1, 1 };
    return (self.catalog.material(entry.materials[0]) orelse return .{ 1, 1, 1, 1 }).base_color;
}

/// `hide_owner` (nonzero) skips that player's avatar parts: its own first-person view.
pub fn prepare(self: *Scene, queue: *gpu.Queue, camera: Camera, vp: mach.math.Mat4x4, culling: bool, upload_budget: usize, removed: *const Modifications, props: []const World.Prop, hide_owner: u8) void {
    const center = Key.fromPosition(camera.position.x(), camera.position.z());
    if (self.last_center) |previous| {
        if (!Key.eql(center, previous)) self.center_changes += 1;
    }
    self.last_center = center;
    self.stream.plan(center);
    const snapshot = self.stream.snapshot();
    self.stats = snapshot.stats;
    self.upload_bytes = 0;
    for (&self.residents) |*resident| {
        if (resident.view) |view| {
            const now = snapshot.views[view.handle.slot];
            if (!Streamer.Handle.eql(view.handle, now.handle) or now.state != .ready or Key.distance(view.key, center) > Streamer.render_radius) {
                resident.view = null;
                self.evictions += 1;
            }
        }
    }
    // GPU buffers are persistent and recycled. New chunk data is submitted under a byte budget.
    while (self.upload_bytes + chunk_bytes <= upload_budget) {
        var candidate: ?Streamer.View = null;
        var best: u32 = std.math.maxInt(u32);
        for (snapshot.views) |view| {
            const distance = Key.distance(view.key, center);
            if (view.state != .ready or distance > Streamer.render_radius or distance >= best) continue;
            var present = false;
            for (self.residents) |resident| if (resident.view) |v| {
                if (Streamer.Handle.eql(v.handle, view.handle)) present = true;
            };
            if (!present) {
                candidate = view;
                best = distance;
            }
        }
        const view = candidate orelse break;
        var free: ?usize = null;
        for (self.residents, 0..) |resident, i| if (resident.view == null) {
            free = i;
            break;
        };
        const i = free orelse break;
        self.residents[i].mesh.write(queue, self.stream.payload(view).?.mesh());
        self.residents[i].view = view;
        self.upload_bytes += chunk_bytes;
        self.uploads += 1;
    }
    self.total_upload_bytes += self.upload_bytes;
    self.peak_upload_bytes = @max(self.peak_upload_bytes, self.upload_bytes);
    self.instances[0] = .{ .translation_scale = .{ 0, 0, 0, 1 }, .tint = .{ 1, 1, 1, 1 } };
    self.instance_count = 1;
    self.resident_count = 0;
    self.terrain_draws = 0;
    self.active_missing = 0;
    for (0..3) |z| for (0..3) |x| {
        const key: Key = .{ .x = center.x + @as(i32, @intCast(x)) - 1, .z = center.z + @as(i32, @intCast(z)) - 1 };
        if (key.valid()) self.active_missing += 1;
    };
    for (&self.residents) |*resident| {
        resident.visible = false;
        if (resident.view) |view| {
            self.resident_count += 1;
            if (Key.distance(view.key, center) <= Streamer.active_radius) self.active_missing -= 1;
            resident.visible = !culling or Visibility.sphereVisible(vp, .{ @as(f32, @floatFromInt(view.key.x)) * Key.extent, 0, @as(f32, @floatFromInt(view.key.z)) * Key.extent }, 96);
            if (resident.visible) self.terrain_draws += 1;
        }
    }
    self.peak_resident_count = @max(self.peak_resident_count, self.resident_count);
    self.relic_count = self.gather(.relic, vp, culling, removed);
    self.plant_count = self.gather(.vegetation, vp, culling, removed);
    self.gatherProps(props, .{ camera.position.x(), camera.position.y(), camera.position.z() }, hide_owner);
}

fn gather(self: *Scene, kind: Scatter.Kind, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications) u32 {
    const first = self.instance_count;
    const color = self.baseColor(if (kind == .relic) self.catalog.content.relic else self.catalog.content.plant);
    for (self.residents) |resident| {
        if (!resident.visible) continue;
        const view = resident.view.?;
        const data = self.stream.payload(view).?;
        for (data.objects[0..data.object_count]) |object| {
            if (object.kind != kind) continue;
            // Saved removals apply to regenerated content by stable (chunk, local_id) identity.
            if (removed.len > 0 and removed.contains(.of(view.key, object.local_id))) continue;
            const t = object.transform.toInstance();
            if (culling and !Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3], t[2] }, 1.3 * t[3])) continue;
            self.instances[self.instance_count] = .{ .translation_scale = t, .tint = multiply(object.tint, color) };
            self.instance_count += 1;
        }
    }
    return self.instance_count - first;
}

/// Groups props by catalog mesh, then emits one instanced draw per submesh with its material color.
/// A prop with a distance LOD is grouped under whichever handle `effectiveMesh` picks this frame.
fn gatherProps(self: *Scene, props: []const World.Prop, camera_position: [3]f32, hide_owner: u8) void {
    self.draw_count = 0;
    self.prop_count = 0;
    var live = self.catalog.meshes.live.iterator(.{});
    while (live.next()) |slot| {
        const handle = self.catalog.meshes.idAt(slot);
        const entry = self.catalog.mesh(handle).?;
        const mesh = self.gpuMesh(handle) orelse continue;
        for (entry.model.submeshes, 0..) |submesh, s| {
            const first = self.instance_count;
            const color = (self.catalog.material(entry.materials[s]) orelse continue).base_color;
            for (props) |prop| {
                if (hide_owner != 0 and prop.owner == hide_owner) continue;
                if (!prop.effectiveMesh(camera_position).eql(handle)) continue;
                self.instances[self.instance_count] = .{ .translation_scale = prop.transform.toInstance(), .tint = multiply(prop.tint, color), .stretch = .{ prop.size[0], prop.size[1], prop.size[2], 0 }, .rotation = prop.rotation };
                self.instance_count += 1;
            }
            if (self.instance_count == first) break;
            if (s == 0) self.prop_count += self.instance_count - first;
            self.draws[self.draw_count] = .{ .mesh = mesh, .first_index = submesh.first_index, .index_count = submesh.index_count, .first_instance = first, .instances = self.instance_count - first };
            self.draw_count += 1;
        }
    }
}

fn multiply(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

pub fn draw(self: *Scene, pass: *gpu.RenderPassEncoder) void {
    for (self.residents) |resident| if (resident.visible) resident.mesh.draw(pass, 1, 0);
    if (self.relic_count > 0) if (self.gpuMesh(self.catalog.content.relic)) |mesh| mesh.draw(pass, self.relic_count, 1);
    if (self.plant_count > 0) if (self.gpuMesh(self.catalog.content.plant)) |mesh| mesh.draw(pass, self.plant_count, 1 + self.relic_count);
    for (self.draws[0..self.draw_count]) |d| d.mesh.drawRange(pass, d.first_index, d.index_count, d.instances, d.first_instance);
}

pub fn destroy(self: *Scene) void {
    self.stream.destroy();
    if (self.initialized) for (self.residents) |resident| resident.mesh.deinit();
    if (self.owns_meshes) for (self.meshes) |mesh| if (mesh) |m| m.deinit();
}
