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
/// Trees drawn with a lighter crown: `[0]` mid, `[1]` far, by species (`treeDetail`).
tree_lod_counts: [2][Vegetation.tree_count]u32 = @splat(@splat(0)),
/// Instances per living-sap species: bodies, then glows (the same plants drawn bright).
sap_counts: [SapFlora.count]u32 = @splat(0),
sap_glow_counts: [SapFlora.count]u32 = @splat(0),
boulder_counts: [@import("../procedural/Vegetation.zig").boulder_count]u32 = @splat(0),
/// Each resident's scattered objects tagged with their draw bucket this frame (`gatherScatter`).
scatter_tags: [Streamer.render_capacity][Scatter.capacity]u8 = undefined,
bucket_colors: [bucket_count][4]f32 = undefined,
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
        self.tree_lod_counts = @splat(@splat(0));
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
        self.tree_lod_counts = @splat(@splat(0));
        self.sap_counts = @splat(0);
        self.sap_glow_counts = @splat(0);
        self.plant_count = 0;
        self.boulder_counts = @splat(0);
    } else {
        self.refreshBucketColors();
        self.gatherScatter(vp, culling, removed, .{ camera.position.x(), camera.position.y(), camera.position.z() });
    }
    self.gatherProps(props, .{ camera.position.x(), camera.position.y(), camera.position.z() }, hide_owner);
}

/// How far, in tree heights, a tree keeps its full crown, then its mid crown; beyond, the far one.
const near_crown_heights: f32 = 1.0;
const mid_crown_heights: f32 = 2.5;

/// Crown detail for a tree seen from `eye`: by distance to its middle over its height, so tall
/// trees keep detail farther out than short ones.
pub fn treeDetail(eye: [3]f32, transform: @import("../world/Transform.zig")) Vegetation.Detail {
    const p = transform.position;
    const d: [3]f32 = .{ p[0] - eye[0], p[1] + transform.scale * 0.5 - eye[1], p[2] - eye[2] };
    const reach = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    if (reach < near_crown_heights * transform.scale) return .near;
    if (reach < mid_crown_heights * transform.scale) return .mid;
    return .far;
}

/// Draw buckets for scattered objects, in instance order: relics, flora by variant, lighter tree
/// crowns (mid, then far) by species, living-sap
/// bodies then glows by species, boulders by variant. `drawFlora` and `drawSolids` read them back
/// in this order.
const flora_bucket: u8 = 1;
const tree_mid_bucket: u8 = flora_bucket + Vegetation.variant_count;
const tree_far_bucket: u8 = tree_mid_bucket + Vegetation.tree_count;
const sap_body_bucket: u8 = tree_far_bucket + Vegetation.tree_count;
const sap_glow_bucket: u8 = sap_body_bucket + SapFlora.count;
const boulder_bucket: u8 = sap_glow_bucket + SapFlora.count;
const bucket_count = boulder_bucket + Vegetation.boulder_count;
/// A scattered object left out this frame (filtered, culled or removed).
const no_bucket: u8 = 0xff;

/// Sorts every visible scattered object into its draw bucket with two scans of the residents
/// (tag and count, then place), instead of one scan per bucket. Instances keep resident-then-
/// object order within a bucket, exactly as a scan per bucket would emit them.
fn gatherScatter(self: *Scene, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications, eye: [3]f32) void {
    var sources: [Streamer.render_capacity]Source = undefined;
    var source_count: usize = 0;
    for (self.residents) |resident| {
        if (!resident.visible) continue;
        const view = resident.view.?;
        const data = self.stream.payload(view) orelse continue; // stale during a terrain rebuild
        sources[source_count] = .{ .key = view.key, .objects = data.objects[0..data.object_count] };
        source_count += 1;
    }
    self.sortScatter(sources[0..source_count], vp, culling, removed, eye);
}

/// One visible chunk's scattered objects.
const Source = struct { key: Key, objects: []const Scatter.Object };

fn sortScatter(self: *Scene, sources: []const Source, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications, eye: [3]f32) void {
    var counts: [bucket_count]u32 = @splat(0);
    for (sources, 0..) |source, r| {
        const tags = &self.scatter_tags[r];
        for (source.objects, 0..) |object, o| {
            tags[o] = self.bucketOf(source.key, object, vp, culling, removed, eye);
            if (tags[o] == no_bucket) continue;
            counts[tags[o]] += 1;
            if (tags[o] >= sap_body_bucket and tags[o] < sap_glow_bucket) counts[tags[o] + SapFlora.count] += 1;
        }
    }
    // The flora review appends one fixed specimen to each reviewed variant.
    if (self.flora_review) for (0..Vegetation.variant_count) |v| {
        if (self.flora_review_variant) |only| if (v != only) continue;
        counts[flora_bucket + v] += 1;
    };
    var cursors: [bucket_count]u32 = undefined;
    var next = self.instance_count;
    for (counts, &cursors) |count, *cursor| {
        cursor.* = next;
        next += count;
    }
    std.debug.assert(next <= self.instances.len);
    for (sources, 0..) |source, r| {
        const tags = &self.scatter_tags[r];
        for (source.objects, 0..) |object, o| {
            const bucket = tags[o];
            if (bucket == no_bucket) continue;
            const t = object.transform.toInstance();
            self.instances[cursors[bucket]] = .{ .translation_scale = t, .tint = multiply(object.tint, self.bucket_colors[bucket]) };
            cursors[bucket] += 1;
            if (bucket >= sap_body_bucket and bucket < sap_glow_bucket) {
                // The same plant again, drawn bright; alpha tags the glow for the night pass.
                const glow = bucket + SapFlora.count;
                var tint = multiply(object.tint, self.bucket_colors[glow]);
                tint[3] = glow_alpha;
                self.instances[cursors[glow]] = .{ .translation_scale = t, .tint = tint };
                cursors[glow] += 1;
            }
        }
    }
    if (self.flora_review) for (0..Vegetation.variant_count) |v| {
        if (self.flora_review_variant) |only| if (v != only) continue;
        const position = floraReviewPosition(self.flora_review_seed, self.flora_review_origin, @intCast(v));
        const scale: f32 = if (Vegetation.isRedwood(@intCast(v))) 150 else if (Vegetation.isTree(@intCast(v))) 132 else if (v == 7) 2.5 else 2.2;
        self.instances[cursors[flora_bucket + v]] = .{ .translation_scale = .{ position[0], position[1], position[2], scale }, .tint = self.bucket_colors[flora_bucket + v] };
        cursors[flora_bucket + v] += 1;
    };
    self.instance_count = next;
    self.relic_count = counts[0];
    @memcpy(&self.flora_counts, counts[flora_bucket..tree_mid_bucket]);
    @memcpy(&self.tree_lod_counts[0], counts[tree_mid_bucket..tree_far_bucket]);
    @memcpy(&self.tree_lod_counts[1], counts[tree_far_bucket..sap_body_bucket]);
    @memcpy(&self.sap_counts, counts[sap_body_bucket..sap_glow_bucket]);
    @memcpy(&self.sap_glow_counts, counts[sap_glow_bucket..boulder_bucket]);
    @memcpy(&self.boulder_counts, counts[boulder_bucket..]);
    self.plant_count = 0;
    for (counts[flora_bucket..boulder_bucket]) |count| self.plant_count += count;
}

/// The draw bucket of one scattered object this frame, or `no_bucket` when it is not drawn.
fn bucketOf(self: *const Scene, key: Key, object: Scatter.Object, vp: mach.math.Mat4x4, culling: bool, removed: *const Modifications, eye: [3]f32) u8 {
    const bucket: u8 = switch (object.kind) {
        .relic => 0,
        .boulder => if (object.variant < Vegetation.boulder_count) boulder_bucket + object.variant else return no_bucket,
        .vegetation => if (SapFlora.speciesOf(object.variant)) |species| blk: {
            if (self.flora_review) return no_bucket;
            break :blk sap_body_bucket + @as(u8, @intCast(@intFromEnum(species)));
        } else blk: {
            if (object.variant >= Vegetation.variant_count) return no_bucket;
            // K2 stays bare except for the authored sheltered Cloudwater pockets.
            if (Region.k2.contains(key.x, key.z) and !Cloudwater.isSheltered(object.transform.position[0], object.transform.position[2])) return no_bucket;
            // Keep the fixed flora showcase legible instead of letting random nearby trees occlude it.
            if (self.flora_review) return no_bucket;
            if (Vegetation.treeIndex(object.variant)) |species| switch (treeDetail(eye, object.transform)) {
                .near => {},
                .mid => break :blk tree_mid_bucket + species,
                .far => break :blk tree_far_bucket + species,
            };
            break :blk flora_bucket + object.variant;
        },
    };
    // Saved removals apply to regenerated content by stable (chunk, local_id) identity.
    if (removed.len > 0 and removed.contains(.of(key, object.local_id))) return no_bucket;
    if (culling) {
        const t = object.transform.toInstance();
        // Living-sap plants are culled about their middle, everything else about its top.
        const lift: f32 = if (bucket >= sap_body_bucket and bucket < sap_glow_bucket) 0.5 else 1;
        if (!Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3] * lift, t[2] }, 1.3 * t[3])) return no_bucket;
    }
    return bucket;
}

/// Base colours of each bucket's mesh, refreshed each frame (catalog meshes can be replaced).
fn refreshBucketColors(self: *Scene) void {
    const c = &self.catalog.content;
    self.bucket_colors[0] = self.baseColor(c.relic);
    for (0..Vegetation.variant_count) |v| self.bucket_colors[flora_bucket + v] = self.baseColor(c.flora[v]);
    for (0..Vegetation.tree_count) |t| {
        self.bucket_colors[tree_mid_bucket + t] = self.baseColor(c.tree_crowns[t][0]);
        self.bucket_colors[tree_far_bucket + t] = self.baseColor(c.tree_crowns[t][1]);
    }
    for (0..SapFlora.count) |s| {
        self.bucket_colors[sap_body_bucket + s] = self.baseColor(c.sap_body[s]);
        self.bucket_colors[sap_glow_bucket + s] = self.baseColor(c.sap_glow[s]);
    }
    for (0..Vegetation.boulder_count) |b| self.bucket_colors[boulder_bucket + b] = self.baseColor(c.boulders[b]);
}

/// Instance tint alpha of a glowing plant part: above 1 is emissive, up to 2 fully so.
const glow_alpha: f32 = 2.5;

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
    for (self.tree_lod_counts, 0..) |counts, lod| for (counts, 0..) |count, species| if (count > 0) {
        if (self.gpuMesh(self.catalog.content.tree_crowns[species][lod])) |mesh| indices += @as(u64, mesh.index_count) * count;
        if (self.gpuMesh(self.catalog.content.tree_trunks[species])) |mesh| indices += @as(u64, mesh.index_count) * count;
    };
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
    for (self.draws[0..self.draw_count]) |draw| indices += @as(u64, draw.index_count) * draw.instances;
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
    for (self.tree_lod_counts, 0..) |counts, lod| for (counts, 0..) |count, species| {
        if (count == 0) continue;
        if (self.gpuMesh(self.catalog.content.tree_trunks[species])) |trunk| trunk.draw(pass, count, next);
        if (self.gpuMesh(self.catalog.content.tree_crowns[species][lod])) |mesh| mesh.draw(pass, count, next);
        next += count;
    };
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

test "the one-pass scatter sort matches a scan per bucket, duplicates living-sap glows and honours removals" {
    const allocator = std.testing.allocator;
    const scene = try allocator.create(Scene);
    defer allocator.destroy(scene);
    scene.* = .{ .stream = undefined, .catalog = undefined };
    for (&scene.bucket_colors, 0..) |*color, b| color.* = .{ 1, 1, 1, @as(f32, @floatFromInt(b)) };
    const sap = SapFlora.variantOf(@enumFromInt(1));
    // A deliberately interleaved mix across two chunks, including an unknown variant.
    const kinds = [_]Scatter.Kind{ .vegetation, .boulder, .relic, .vegetation, .vegetation, .boulder, .vegetation, .relic };
    const variants = [_]u8{ 4, 2, 0, sap, 0, 0, 120, 0 };
    var chunks: [2][kinds.len]Scatter.Object = undefined;
    for (&chunks, 0..) |*chunk, c| for (chunk, 0..) |*object, i| {
        object.* = .{ .local_id = @intCast(i), .kind = kinds[(i + c) % kinds.len], .variant = variants[(i + 3 * c) % variants.len], .transform = .{ .position = .{ @floatFromInt(c), @floatFromInt(i), 0 } }, .tint = .{ 1, 1, 1, 1 } };
    };
    const sources = [_]Source{ .{ .key = .{ .x = 0, .z = 0 }, .objects = &chunks[0] }, .{ .key = .{ .x = 1, .z = 0 }, .objects = &chunks[1] } };
    var removed: Modifications = .{};
    _ = try removed.remove(.of(sources[1].key, 2));
    // Objects sit within 8 m of the origin; a unit-scale tree there is far from this eye.
    const eye: [3]f32 = .{ 0, 0, 40 };
    scene.instance_count = 1;
    scene.sortScatter(&sources, mach.math.Mat4x4.ident, false, &removed, eye);

    // The reference: one full scan per bucket, as the renderer used to do.
    var expected: [64][4]f32 = undefined;
    var n: usize = 0;
    for (0..bucket_count) |bucket| for (sources) |source| for (source.objects) |object| {
        const tag = scene.bucketOf(source.key, object, mach.math.Mat4x4.ident, false, &removed, eye);
        const glow_of_body = bucket >= sap_glow_bucket and bucket < boulder_bucket and tag == bucket - SapFlora.count;
        if (tag != bucket and !glow_of_body) continue;
        expected[n] = object.transform.toInstance();
        n += 1;
    };
    try std.testing.expectEqual(@as(u32, @intCast(1 + n)), scene.instance_count);
    for (expected[0..n], scene.instances[1 .. 1 + n]) |want, got| try std.testing.expectEqual(want, got.translation_scale);
    // Two relics per chunk; the removed object and the unknown variant are left out.
    try std.testing.expectEqual(@as(u32, 4), scene.relic_count);
    try std.testing.expectEqual(no_bucket, scene.bucketOf(sources[1].key, chunks[1][2], mach.math.Mat4x4.ident, false, &removed, eye));
    var sap_bodies: u32 = 0;
    var sap_glows: u32 = 0;
    for (scene.sap_counts, scene.sap_glow_counts) |body, glow| {
        sap_bodies += body;
        sap_glows += glow;
    }
    try std.testing.expect(sap_bodies > 0 and sap_glows == sap_bodies);
    const lighter = sumOf(&scene.tree_lod_counts[0]) + sumOf(&scene.tree_lod_counts[1]);
    try std.testing.expect(lighter > 0);
    try std.testing.expectEqual(glow_alpha, scene.instances[1 + scene.relic_count + sumOf(&scene.flora_counts) + lighter + sap_bodies].tint[3]);
}

fn sumOf(counts: []const u32) u32 {
    var total: u32 = 0;
    for (counts) |count| total += count;
    return total;
}

test "tree crowns lighten with distance measured in tree heights" {
    const tall: @import("../world/Transform.zig") = .{ .position = .{ 0, 0, 0 }, .scale = 120 };
    try std.testing.expectEqual(Vegetation.Detail.near, treeDetail(.{ 0, 60, 80 }, tall));
    try std.testing.expectEqual(Vegetation.Detail.mid, treeDetail(.{ 0, 60, 200 }, tall));
    try std.testing.expectEqual(Vegetation.Detail.far, treeDetail(.{ 0, 60, 400 }, tall));
    // The same 200 m keeps a giant at mid detail but sends a small pine far.
    const pine: @import("../world/Transform.zig") = .{ .position = .{ 0, 0, 0 }, .scale = 12 };
    try std.testing.expectEqual(Vegetation.Detail.far, treeDetail(.{ 0, 6, 200 }, pine));
}
