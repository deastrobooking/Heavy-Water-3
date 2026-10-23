const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const Streamer = @import("../world/Streamer.zig");
const Key = @import("../world/ChunkKey.zig");
const Region = @import("../world/Region.zig");
const Cloudwater = @import("../procedural/Cloudwater.zig");
const Chunk = @import("../procedural/Chunk.zig");
const CityHeightmaps = @import("../procedural/CityHeightmaps.zig");
const Scatter = @import("../procedural/Scatter.zig");
const Camera = @import("../world/Camera.zig");
const Mesh = @import("Mesh.zig");
const GpuMesh = @import("GpuMesh.zig");
const Visibility = @import("Visibility.zig");
const Catalog = @import("../asset/Catalog.zig");
const Model = @import("../asset/Model.zig");
const World = @import("../world/World.zig");
const Modifications = @import("../world/Modifications.zig");
const Vegetation = @import("../procedural/Vegetation.zig");
const SapFlora = @import("../procedural/SapFlora.zig");
const Noise = @import("../procedural/Noise.zig");
const Scene = @This();
const world_prop_distance: f32 = 6000;
/// Per-axis `stretch` (applied first) and a unit-quaternion `rotation`; the shader corrects
/// normals for the stretch and rotates them.
pub const Instance = extern struct { translation_scale: [4]f32, tint: [4]f32, stretch: [4]f32 = .{ 1, 1, 1, 0 }, rotation: [4]f32 = .{ 0, 0, 0, 1 } };
/// Every living-sap object draws twice (body, then glow), so those get a second slot each.
pub const max_instances = Streamer.render_capacity * (Scatter.capacity + Scatter.sap_candidates) + 1 + World.max_props * Model.max_submeshes;
/// One instanced draw of a catalog submesh.
/// `ground` draws (the mountain panorama and cave meshes) are shaded as terrain.
const Draw = struct { mesh: *const GpuMesh, first_index: u32, index_count: u32, first_instance: u32, instances: u32, ground: bool = false };
const max_draws = Catalog.mesh_capacity * Model.max_submeshes;
pub const MeshPatch = struct {
    handle: Catalog.MeshHandle,
    model: *const Model,
    vertex_indices: []const u32 = &.{},
    triangle_offsets: []const u32 = &.{},
    all_vertices: bool = false,
    all_indices: bool = false,
};
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
flora_counts: [@import("../procedural/Vegetation.zig").variant_count]u32 = @splat(0),
/// Instances per living-sap species: bodies, then glows (the same plants drawn bright).
sap_counts: [SapFlora.count]u32 = @splat(0),
sap_glow_counts: [SapFlora.count]u32 = @splat(0),
boulder_counts: [@import("../procedural/Vegetation.zig").boulder_count]u32 = @splat(0),
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
/// Deterministic art-review lineup for the giant flora and night pigment pass.
flora_review: bool = false,
flora_review_variant: ?u8 = null,
flora_review_seed: u64 = 0,
flora_review_origin: [3]f32 = .{ 0, 0, 0 },
/// Isolated backdrop for orbital vehicle art-review captures.
space_review: bool = false,

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

/// Writes only changed vertex runs and triangle triplets into an existing catalog GPU mesh.
/// If it has not uploaded yet, the normal catalog upload will include the current CPU model.
pub fn patchMesh(self: *Scene, queue: *gpu.Queue, patch: MeshPatch) void {
    if (!self.owns_meshes or self.mesh_generation[patch.handle.index] != patch.handle.generation) return;
    const mesh = if (self.meshes[patch.handle.index]) |*value| value else return;
    if (patch.all_vertices) {
        queue.writeBuffer(mesh.vertices, 0, patch.model.mesh.vertices);
    } else {
        var at: usize = 0;
        while (at < patch.vertex_indices.len) {
            const first: usize = patch.vertex_indices[at];
            var end = first + 1;
            at += 1;
            while (at < patch.vertex_indices.len and patch.vertex_indices[at] == end) : (at += 1) end += 1;
            queue.writeBuffer(mesh.vertices, first * @sizeOf(Mesh.Vertex), patch.model.mesh.vertices[first..end]);
        }
    }
    if (patch.all_indices) {
        queue.writeBuffer(mesh.indices, 0, patch.model.mesh.indices);
    } else {
        var at: usize = 0;
        while (at < patch.triangle_offsets.len) {
            const first: usize = patch.triangle_offsets[at];
            var end = first + 3;
            at += 1;
            while (at < patch.triangle_offsets.len and patch.triangle_offsets[at] == end) : (at += 1) end += 3;
            queue.writeBuffer(mesh.indices, first * @sizeOf(u32), patch.model.mesh.indices[first..end]);
        }
    }
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

/// Material base color of a single-material catalog mesh (harvestable saplings, vegetation).
fn baseColor(self: *const Scene, handle: Catalog.MeshHandle) [4]f32 {
    const entry = self.catalog.mesh(handle) orelse return .{ 1, 1, 1, 1 };
    return (self.catalog.material(entry.materials[0]) orelse return .{ 1, 1, 1, 1 }).base_color;
}

/// `hide_owner` (nonzero) skips that player's avatar parts: its own first-person view.
pub fn prepare(self: *Scene, queue: *gpu.Queue, camera: Camera, vp: mach.math.Mat4x4, culling: bool, upload_budget: usize, removed: *const Modifications, props: []const World.Prop, hide_owner: u8) void {
    if (self.space_review) {
        self.draw_count = 0;
        self.prop_count = 0;
        self.instance_count = 1;
        self.resident_count = 0;
        self.terrain_draws = 0;
        self.active_missing = 0;
        self.relic_count = 0;
        self.plant_count = 0;
        self.flora_counts = @splat(0);
        self.sap_counts = @splat(0);
        self.sap_glow_counts = @splat(0);
        self.boulder_counts = @splat(0);
        for (&self.residents) |*resident| resident.visible = false;
        self.gatherProps(props, .{ camera.position.x(), camera.position.y(), camera.position.z() }, hide_owner);
        return;
    }
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
            // A rebuilt chunk (a sculpt edit) keeps showing its old copy until the new one is ready.
            const rebuilt = Key.eql(view.key, now.key) and !Streamer.Handle.eql(view.handle, now.handle) and now.state != .empty;
            if ((!Streamer.Handle.eql(view.handle, now.handle) and !rebuilt) or (now.state != .ready and !rebuilt) or Key.distance(view.key, center) > Streamer.render_radius) {
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
        for (self.residents, 0..) |resident, i| if (resident.view) |v| {
            if (Key.eql(v.key, view.key)) free = i; // replace this chunk's stale copy in place
        };
        if (free == null) for (self.residents, 0..) |resident, i| if (resident.view == null) {
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
            const x = @as(f32, @floatFromInt(view.key.x)) * Key.extent;
            const z = @as(f32, @floatFromInt(view.key.z)) * Key.extent;
            var low = CityHeightmaps.heightAt(self.stream.seed, x, z);
            var high = low;
            const half = Key.extent * 0.5;
            for ([_][2]f32{ .{ -half, -half }, .{ half, -half }, .{ -half, half }, .{ half, half } }) |corner| {
                const height = CityHeightmaps.heightAt(self.stream.seed, x + corner[0], z + corner[1]);
                low = @min(low, height);
                high = @max(high, height);
            }
            const vertical = (high - low) * 0.5 + 8;
            const radius = @sqrt(half * half * 2 + vertical * vertical);
            resident.visible = !culling or Visibility.sphereVisible(vp, .{ x, (low + high) * 0.5, z }, radius);
            if (resident.visible) self.terrain_draws += 1;
        }
    }
    self.peak_resident_count = @max(self.peak_resident_count, self.resident_count);
    if (Region.antarctica.contains(center.x, center.z)) {
        // The first ice sheet approach is intentionally bare: keep procedural forest, stones,
        // and salvage out of the visual-only perimeter until Antarctic encounter dressing exists.
        self.relic_count = 0;
        self.flora_counts = @splat(0);
        self.sap_counts = @splat(0);
        self.sap_glow_counts = @splat(0);
        self.plant_count = 0;
        self.boulder_counts = @splat(0);
    } else {
        self.relic_count = self.gather(.relic, vp, culling, removed, null);
        self.plant_count = 0;
        for (&self.flora_counts, 0..) |*count, variant| {
            count.* = self.gather(.vegetation, vp, culling, removed, @intCast(variant));
            self.plant_count += count.*;
        }
        // The living-sap flora: every plant's body, then the same plants' glow drawn bright.
        for (&self.sap_counts, 0..) |*count, species| {
            count.* = self.gatherSap(vp, culling, removed, @intCast(species), false);
            self.plant_count += count.*;
        }
        for (&self.sap_glow_counts, 0..) |*count, species| {
            count.* = self.gatherSap(vp, culling, removed, @intCast(species), true);
            self.plant_count += count.*;
        }
        for (&self.boulder_counts, 0..) |*count, variant| count.* = self.gather(.boulder, vp, culling, removed, @intCast(variant));
    }
    self.gatherProps(props, .{ camera.position.x(), camera.position.y(), camera.position.z() }, hide_owner);
}

fn gather(self: *Scene, kind: Scatter.Kind, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications, variant: ?u8) u32 {
    const first = self.instance_count;
    const handle = switch (kind) {
        .relic => self.catalog.content.relic,
        .vegetation => self.catalog.content.flora[variant.?],
        .boulder => self.catalog.content.boulders[variant.?],
    };
    const color = self.baseColor(handle);
    for (self.residents) |resident| {
        if (!resident.visible) continue;
        const view = resident.view.?;
        const data = self.stream.payload(view) orelse continue; // stale during a terrain rebuild
        for (data.objects[0..data.object_count]) |object| {
            if (object.kind != kind) continue;
            // K2 stays bare except for the authored sheltered Cloudwater pockets.
            if (kind == .vegetation and Region.k2.contains(view.key.x, view.key.z) and !Cloudwater.isSheltered(object.transform.position[0], object.transform.position[2])) continue;
            // Keep the fixed flora showcase legible instead of letting random nearby trees occlude it.
            if (self.flora_review and kind == .vegetation) continue;
            if (variant) |v| if (object.variant != v) continue;
            // Saved removals apply to regenerated content by stable (chunk, local_id) identity.
            if (removed.len > 0 and removed.contains(.of(view.key, object.local_id))) continue;
            const t = object.transform.toInstance();
            if (culling and !Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3], t[2] }, 1.3 * t[3])) continue;
            self.instances[self.instance_count] = .{ .translation_scale = t, .tint = multiply(object.tint, color) };
            self.instance_count += 1;
        }
    }
    if (kind == .vegetation and self.flora_review) if (variant) |v| {
        if (self.flora_review_variant) |review_variant| if (v != review_variant) return self.instance_count - first;
        if (self.instance_count < self.instances.len) {
            const position = floraReviewPosition(self.flora_review_seed, self.flora_review_origin, v);
            const scale: f32 = if (Vegetation.isRedwood(v)) 150 else if (Vegetation.isTree(v)) 132 else if (v == 7) 2.5 else 2.2;
            self.instances[self.instance_count] = .{ .translation_scale = .{ position[0], position[1], position[2], scale }, .tint = multiply(.{ 1, 1, 1, 1 }, color) };
            self.instance_count += 1;
        }
    };
    return self.instance_count - first;
}

/// Instances of one living-sap species, as plain bodies or as glow: the glow copy raises the
/// tint alpha above 1, which the scene shader turns into lumen that burns brighter at night.
fn gatherSap(self: *Scene, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications, species: u8, glow: bool) u32 {
    const first = self.instance_count;
    const handle = if (glow) self.catalog.content.sap_glow[species] else self.catalog.content.sap_body[species];
    const color = self.baseColor(handle);
    const variant = SapFlora.variantOf(@enumFromInt(species));
    if (self.flora_review) return 0;
    for (self.residents) |resident| {
        if (!resident.visible) continue;
        const view = resident.view.?;
        const data = self.stream.payload(view) orelse continue; // stale during a terrain rebuild
        for (data.objects[0..data.object_count]) |object| {
            if (object.kind != .vegetation or object.variant != variant) continue;
            if (removed.len > 0 and removed.contains(.of(view.key, object.local_id))) continue;
            const t = object.transform.toInstance();
            if (culling and !Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3] * 0.5, t[2] }, 1.3 * t[3])) continue;
            if (self.instance_count >= self.instances.len) return self.instance_count - first;
            var tint = multiply(object.tint, color);
            if (glow) tint[3] = glow_alpha;
            self.instances[self.instance_count] = .{ .translation_scale = t, .tint = tint };
            self.instance_count += 1;
        }
    }
    return self.instance_count - first;
}

/// Instance tint alpha of a glowing plant part: above 1 is emissive, up to 2 fully so.
const glow_alpha: f32 = 1.75;

fn floraReviewPosition(seed: u64, origin: [3]f32, variant: u8) [3]f32 {
    const xoff: f32 = switch (variant) {
        3 => -210,
        4 => -140,
        5 => -70,
        6 => 0,
        7 => -18,
        8 => -6,
        9 => 6,
        10 => 18,
        11 => 70,
        12 => 140,
        13 => 210,
        14 => 280,
        else => 0,
    };
    // Pull the low flora toward the camera so its forms read beneath the distant giants.
    const zoff: f32 = if (Vegetation.isTree(variant)) 0 else 215;
    const x = origin[0] + xoff;
    const z = origin[2] + zoff;
    return .{ x, CityHeightmaps.heightAt(seed, x, z) - 0.03, z };
}

/// Groups props by catalog mesh, then emits one instanced draw per submesh with its material color.
/// A prop with a distance LOD is grouped under whichever handle `effectiveMesh` picks this frame.
fn gatherProps(self: *Scene, props: []const World.Prop, camera_position: [3]f32, hide_owner: u8) void {
    self.draw_count = 0;
    self.prop_count = 0;
    std.debug.assert(props.len <= World.max_props);
    var nearby: [World.max_props]bool = @splat(false);
    for (props, 0..) |prop, i| {
        const p = prop.transform.position;
        const dx = p[0] - camera_position[0];
        const dy = p[1] - camera_position[1];
        const dz = p[2] - camera_position[2];
        // Cave shells are already authored in absolute world coordinates; their instance origin
        // stays at zero so adding the player position would shift the mesh to the wrong place.
        nearby[i] = self.isCaveMesh(prop.mesh) or dx * dx + dy * dy + dz * dz <= world_prop_distance * world_prop_distance;
    }
    var live = self.catalog.meshes.live.iterator(.{});
    while (live.next()) |slot| {
        const handle = self.catalog.meshes.idAt(slot);
        const entry = self.catalog.mesh(handle).?;
        const mesh = self.gpuMesh(handle) orelse continue;
        for (entry.model.submeshes, 0..) |submesh, s| {
            const first = self.instance_count;
            const color = (self.catalog.material(entry.materials[s]) orelse continue).base_color;
            for (props, 0..) |prop, prop_index| {
                if (!nearby[prop_index]) continue;
                if (hide_owner != 0 and prop.owner == hide_owner) continue;
                if (!prop.effectiveMesh(camera_position).eql(handle)) continue;
                self.instances[self.instance_count] = .{ .translation_scale = prop.transform.toInstance(), .tint = multiply(prop.tint, color), .stretch = .{ prop.size[0], prop.size[1], prop.size[2], 0 }, .rotation = prop.rotation };
                self.instance_count += 1;
            }
            if (self.instance_count == first) break;
            if (s == 0) self.prop_count += self.instance_count - first;
            self.draws[self.draw_count] = .{ .mesh = mesh, .first_index = submesh.first_index, .index_count = submesh.index_count, .first_instance = first, .instances = self.instance_count - first, .ground = self.isGround(handle) };
            self.draw_count += 1;
        }
    }
}

/// Generated landscape (the ranges' far panorama, cave shells): coloured like the terrain.
fn isGround(self: *const Scene, handle: Catalog.MeshHandle) bool {
    if (handle.eql(self.catalog.ranges)) return true;
    return self.isCaveMesh(handle);
}

fn isCaveMesh(self: *const Scene, handle: Catalog.MeshHandle) bool {
    for (self.catalog.cave_meshes) |cave| if (handle.eql(cave)) return true;
    return false;
}

fn multiply(a: [4]f32, b: [4]f32) [4]f32 {
    return .{ a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3] };
}

/// The ground of every visible chunk (each chunk mesh holds its terrain first, then water).
pub fn drawTerrain(self: *const Scene, pass: *gpu.RenderPassEncoder) void {
    for (self.residents) |resident| if (resident.visible) resident.mesh.drawRange(pass, 0, Chunk.terrain_index_count, 1, 0);
    for (self.draws[0..self.draw_count]) |d| if (d.ground) d.mesh.drawRange(pass, d.first_index, d.index_count, d.instances, d.first_instance);
}

/// Rivers and waterfalls of every visible chunk, for the blended water pipeline.
pub fn drawWater(self: *const Scene, pass: *gpu.RenderPassEncoder) void {
    for (self.residents) |resident| if (resident.visible) resident.mesh.drawRange(pass, Chunk.terrain_index_count, Chunk.index_count - Chunk.terrain_index_count, 1, 0);
}

/// Exact indexed triangle count for the draw set prepared for the current view.
pub fn submittedTriangles(self: *const Scene) u64 {
    var indices: u64 = @as(u64, self.terrain_draws) * Chunk.index_count;
    if (self.relic_count > 0) if (self.gpuMesh(self.catalog.content.relic)) |mesh| {
        indices += @as(u64, mesh.index_count) * self.relic_count;
    };
    for (self.flora_counts, 0..) |count, variant| {
        if (count == 0) continue;
        if (self.gpuMesh(self.catalog.content.flora[variant])) |mesh| indices += @as(u64, mesh.index_count) * count;
        if (Vegetation.treeIndex(@intCast(variant))) |species| if (self.gpuMesh(self.catalog.content.tree_trunks[species])) |mesh| {
            indices += @as(u64, mesh.index_count) * count;
        };
    }
    for (self.sap_counts, self.sap_glow_counts, 0..) |body, glow, species| {
        if (body > 0) if (self.gpuMesh(self.catalog.content.sap_body[species])) |mesh| {
            indices += @as(u64, mesh.index_count) * body;
        };
        if (glow > 0) if (self.gpuMesh(self.catalog.content.sap_glow[species])) |mesh| {
            indices += @as(u64, mesh.index_count) * glow;
        };
    }
    for (self.boulder_counts, 0..) |count, variant| if (count > 0) {
        if (self.gpuMesh(self.catalog.content.boulders[variant])) |mesh| indices += @as(u64, mesh.index_count) * count;
    };
    for (self.draws) |draw| indices += @as(u64, draw.index_count) * draw.instances;
    return indices / 3;
}

/// Scattered plants and trees (with their trunks), for the swaying foliage pipeline.
pub fn drawFlora(self: *const Scene, pass: *gpu.RenderPassEncoder) void {
    var next: u32 = 1 + self.relic_count;
    for (self.flora_counts, 0..) |count, variant| {
        if (count == 0) continue;
        const handle = self.catalog.content.flora[variant];
        if (Vegetation.treeIndex(@intCast(variant))) |species| {
            if (self.gpuMesh(self.catalog.content.tree_trunks[species])) |trunk| trunk.draw(pass, count, next);
        }
        if (self.gpuMesh(handle)) |mesh| mesh.draw(pass, count, next);
        next += count;
    }
    for (self.sap_counts, 0..) |count, species| {
        if (count == 0) continue;
        if (self.gpuMesh(self.catalog.content.sap_body[species])) |mesh| mesh.draw(pass, count, next);
        next += count;
    }
    for (self.sap_glow_counts, 0..) |count, species| {
        if (count == 0) continue;
        if (self.gpuMesh(self.catalog.content.sap_glow[species])) |mesh| mesh.draw(pass, count, next);
        next += count;
    }
}

/// Relics, boulders and props, for the main pipeline.
pub fn drawSolids(self: *const Scene, pass: *gpu.RenderPassEncoder) void {
    if (self.relic_count > 0) if (self.gpuMesh(self.catalog.content.relic)) |mesh| mesh.draw(pass, self.relic_count, 1);
    var next: u32 = 1 + self.relic_count + self.plant_count;
    for (self.boulder_counts, 0..) |count, variant| {
        if (count == 0) continue;
        if (self.gpuMesh(self.catalog.content.boulders[variant])) |mesh| mesh.draw(pass, count, next);
        next += count;
    }
    for (self.draws[0..self.draw_count]) |d| if (!d.ground) d.mesh.drawRange(pass, d.first_index, d.index_count, d.instances, d.first_instance);
}

/// Terrain under `key` changed; null rebuilds every chunk.
pub fn invalidateTerrain(self: *Scene, key: ?Key) void {
    self.stream.invalidate(key);
}

pub fn destroy(self: *Scene) void {
    self.stream.destroy();
    if (self.initialized) for (self.residents) |resident| resident.mesh.deinit();
    if (self.owns_meshes) for (self.meshes) |mesh| if (mesh) |m| m.deinit();
}
