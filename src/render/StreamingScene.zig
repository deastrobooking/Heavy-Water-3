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
const Scene = @This();
pub const Instance = extern struct { translation_scale: [4]f32, tint: [4]f32 };
pub const max_instances = Streamer.render_capacity * Scatter.capacity + 1;
pub const chunk_bytes = Chunk.vertex_count * @sizeOf(Mesh.Vertex) + Chunk.index_count * 4;
pub const gpu_pool_bytes = Streamer.render_capacity * chunk_bytes;
const Resident = struct { mesh: GpuMesh, view: ?Streamer.View = null, visible: bool = false };

stream: *Streamer,
residents: [Streamer.render_capacity]Resident = undefined,
initialized: bool = false,
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
relic: ?GpuMesh = null,
plant: ?GpuMesh = null,

pub fn init(allocator: std.mem.Allocator, io: std.Io, seed: u64) !Scene {
    const stream = try Streamer.create(allocator, io, seed);
    errdefer stream.destroy();
    try stream.start();
    return .{ .stream = stream };
}

pub fn setup(self: *Scene, device: *gpu.Device, queue: *gpu.Queue, allocator: std.mem.Allocator) !void {
    for (&self.residents) |*resident| {
        resident.* = .{ .mesh = GpuMesh.allocate(device, Chunk.vertex_count, Chunk.index_count) };
        self.gpu_pool_allocations += 2;
    }
    self.initialized = true;
    const relic = try Mesh.cube(allocator);
    defer relic.deinit(allocator);
    self.relic = GpuMesh.upload(device, queue, relic);
    const plant = try Mesh.vegetation(allocator);
    defer plant.deinit(allocator);
    self.plant = GpuMesh.upload(device, queue, plant);
}

pub fn prepare(self: *Scene, queue: *gpu.Queue, camera: Camera, vp: mach.math.Mat4x4, culling: bool, upload_budget: usize) void {
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
    self.relic_count = self.gather(.relic, vp, culling);
    self.plant_count = self.gather(.vegetation, vp, culling);
}

fn gather(self: *Scene, kind: Scatter.Kind, vp: mach.math.Mat4x4, culling: bool) u32 {
    const first = self.instance_count;
    for (self.residents) |resident| {
        if (!resident.visible) continue;
        const data = self.stream.payload(resident.view.?).?;
        for (data.objects[0..data.object_count]) |object| {
            if (object.kind != kind) continue;
            const t = object.transform.toInstance();
            if (culling and !Visibility.sphereVisible(vp, .{ t[0], t[1] + t[3], t[2] }, 1.3 * t[3])) continue;
            self.instances[self.instance_count] = .{ .translation_scale = t, .tint = object.tint };
            self.instance_count += 1;
        }
    }
    return self.instance_count - first;
}

pub fn draw(self: *Scene, pass: *gpu.RenderPassEncoder) void {
    for (self.residents) |resident| if (resident.visible) resident.mesh.draw(pass, 1, 0);
    if (self.relic_count > 0) self.relic.?.draw(pass, self.relic_count, 1);
    if (self.plant_count > 0) self.plant.?.draw(pass, self.plant_count, 1 + self.relic_count);
}

pub fn destroy(self: *Scene) void {
    self.stream.destroy();
    if (self.initialized) for (self.residents) |resident| resident.mesh.deinit();
    if (self.relic) |mesh| mesh.deinit();
    if (self.plant) |mesh| mesh.deinit();
}
