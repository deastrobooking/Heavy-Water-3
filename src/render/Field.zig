//! Scale workloads: a seeded field of N small objects (10K, 100K, 1M) over the benchmark
//! route, for measuring how rendering scales with object count.
//!
//! - Instances are sorted into a grid of 64 m cells, so per-frame CPU work is per cell, never per
//!   instance: distance and frustum tests pick visible cells and their LOD (crate model near,
//!   block proxy far).
//! - Consecutive visible cells of the same LOD are adjacent in the instance buffer, so they merge
//!   into one ranged instanced draw (`first_instance`, `instance_count`).
//! - Per-instance frustum rejection then happens on the GPU, in the vertex stage (scene.wgsl
//!   culls instances whose `stretch.w` radius is set).
//! - Instance data streams to the GPU once, under a per-frame byte budget; the CPU copy is freed
//!   once the whole field is resident.
//!
//! The pinned Mach cannot do GPU-compacted culling with indirect submission (no shader atomics,
//! no indirect draws on Metal); see docs/scale.md.
const std = @import("std");
const math = @import("mach").math;
const Seed = @import("../procedural/Seed.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Visibility = @import("Visibility.zig");
pub const Instance = @import("StreamingScene.zig").Instance;
const Field = @This();

pub const cell_size: f32 = 64;
/// The field covers the fly-through route: x −768..1792, z −768..768.
pub const origin: [2]f32 = .{ -768, -768 };
pub const columns = 40;
pub const rows = 24;
pub const cell_count = columns * rows;
pub const lod_distance: f32 = 160;
pub const draw_distance: f32 = 1400;
pub const max_runs = cell_count;
/// Bounding radius of one object at scale 1 (unit crate/block, with margin).
const object_radius: f32 = 0.9;

pub const Lod = enum(u1) { near, far };
pub const Cell = struct { center: [3]f32, radius: f32, first: u32, count: u32 };
pub const Run = struct { first: u32, count: u32, lod: Lod };
pub const Plan = struct {
    runs: [max_runs]Run = undefined,
    run_count: usize = 0,
    visible_cells: usize = 0,
    instances: [2]u32 = .{ 0, 0 },
    pub fn slice(self: *const Plan) []const Run {
        return self.runs[0..self.run_count];
    }
};

allocator: std.mem.Allocator,
count: u32,
/// Sorted by cell (row-major); freed once fully uploaded.
instances: ?[]Instance,
cells: [cell_count]Cell,
/// Instances already on the GPU (always a prefix of the sorted array).
uploaded: u32 = 0,
generation_ms: f32 = 0,

fn hash(seed: u64, i: u64, k: u64) u64 {
    return Seed.mix(seed ^ Seed.mix(i *% 0x9E3779B97F4A7C15 +% k));
}

pub fn generate(allocator: std.mem.Allocator, seed: u64, count: u32) !Field {
    const raw = try allocator.alloc(Instance, count);
    defer allocator.free(raw);
    const cell_of = try allocator.alloc(u16, count);
    defer allocator.free(cell_of);
    var counts: [cell_count]u32 = @splat(0);
    for (raw, cell_of, 0..) |*inst, *cell, i| {
        const x = origin[0] + Seed.unit(hash(seed, i, 1)) * columns * cell_size;
        const z = origin[1] + Seed.unit(hash(seed, i, 2)) * rows * cell_size;
        const scale = 0.6 + 0.9 * Seed.unit(hash(seed, i, 3));
        const yaw = Seed.unit(hash(seed, i, 4)) * 2 * std.math.pi;
        const shade = 0.55 + 0.45 * Seed.unit(hash(seed, i, 5));
        const ground = Terrain.surface(seed, x, z).height;
        inst.* = .{
            .translation_scale = .{ x, ground + 0.4 * scale, z, scale },
            .tint = .{ shade, 0.8 * shade + 0.1, 0.6, 1 },
            .stretch = .{ 1, 1, 1, object_radius },
            .rotation = .{ 0, @sin(yaw / 2), 0, @cos(yaw / 2) },
        };
        const cx: usize = @min(columns - 1, @as(usize, @intFromFloat((x - origin[0]) / cell_size)));
        const cz: usize = @min(rows - 1, @as(usize, @intFromFloat((z - origin[1]) / cell_size)));
        cell.* = @intCast(cz * columns + cx);
        counts[cell.*] += 1;
    }
    // Counting sort by cell, then exact per-cell bounds.
    var self: Field = .{ .allocator = allocator, .count = count, .instances = try allocator.alloc(Instance, count), .cells = undefined };
    var next: [cell_count]u32 = undefined;
    var running: u32 = 0;
    for (&self.cells, counts, &next) |*cell, n, *at| {
        cell.* = .{ .center = @splat(0), .radius = 0, .first = running, .count = n };
        at.* = running;
        running += n;
    }
    for (raw, cell_of) |inst, c| {
        self.instances.?[next[c]] = inst;
        next[c] += 1;
    }
    for (&self.cells, 0..) |*cell, c| {
        const cx = c % columns;
        const cz = c / columns;
        var lo: f32 = std.math.inf(f32);
        var hi: f32 = -std.math.inf(f32);
        for (self.instances.?[cell.first..][0..cell.count]) |inst| {
            lo = @min(lo, inst.translation_scale[1]);
            hi = @max(hi, inst.translation_scale[1]);
        }
        if (cell.count == 0) {
            lo = 0;
            hi = 0;
        }
        const half = cell_size / 2;
        const half_height = (hi - lo) / 2 + 2;
        cell.center = .{ origin[0] + (@as(f32, @floatFromInt(cx)) + 0.5) * cell_size, (lo + hi) / 2, origin[1] + (@as(f32, @floatFromInt(cz)) + 0.5) * cell_size };
        cell.radius = @sqrt(2 * half * half + half_height * half_height);
    }
    return self;
}

pub fn deinit(self: *Field) void {
    if (self.instances) |i| self.allocator.free(i);
    self.instances = null;
}

pub fn resident(self: *const Field) bool {
    return self.uploaded == self.count;
}

/// The next slice to upload within `budget_bytes`, or null when resident. The caller writes it
/// at instance offset `first`, then calls `commit`.
pub fn nextUpload(self: *const Field, budget_bytes: usize) ?struct { first: u32, data: []const Instance } {
    if (self.resident()) return null;
    const n: u32 = @intCast(@min(self.count - self.uploaded, budget_bytes / @sizeOf(Instance)));
    if (n == 0) return null;
    return .{ .first = self.uploaded, .data = self.instances.?[self.uploaded..][0..n] };
}

pub fn commit(self: *Field, n: u32) void {
    self.uploaded += n;
    if (self.resident()) self.deinit();
}

pub fn cpuBytes(self: *const Field) usize {
    return if (self.instances) |i| i.len * @sizeOf(Instance) else 0;
}

pub fn gpuBytes(self: *const Field) usize {
    return @as(usize, self.count) * @sizeOf(Instance);
}

/// Visible, resident cells within draw distance, merged into runs per LOD.
pub fn plan(self: *const Field, eye: [3]f32, vp: math.Mat4x4) Plan {
    var p: Plan = .{};
    var open: ?Run = null;
    for (self.cells) |cell| {
        const visible = cell.count > 0 and cell.first + cell.count <= self.uploaded and blk: {
            const d = @sqrt((cell.center[0] - eye[0]) * (cell.center[0] - eye[0]) + (cell.center[1] - eye[1]) * (cell.center[1] - eye[1]) + (cell.center[2] - eye[2]) * (cell.center[2] - eye[2]));
            break :blk d - cell.radius < draw_distance and Visibility.sphereVisible(vp, cell.center, cell.radius);
        };
        if (!visible) {
            if (open) |run| p.runs[p.run_count] = run;
            if (open != null) p.run_count += 1;
            open = null;
            continue;
        }
        const d = @sqrt((cell.center[0] - eye[0]) * (cell.center[0] - eye[0]) + (cell.center[2] - eye[2]) * (cell.center[2] - eye[2]));
        const lod: Lod = if (d - cell.radius < lod_distance) .near else .far;
        p.visible_cells += 1;
        p.instances[@intFromEnum(lod)] += cell.count;
        if (open) |*run| {
            if (run.lod == lod and run.first + run.count == cell.first) {
                run.count += cell.count;
                continue;
            }
            p.runs[p.run_count] = run.*;
            p.run_count += 1;
        }
        open = .{ .first = cell.first, .count = cell.count, .lod = lod };
    }
    if (open) |run| {
        p.runs[p.run_count] = run;
        p.run_count += 1;
    }
    return p;
}

test "fields are deterministic, cell-sorted, bounded, and stream under a byte budget" {
    var f = try Field.generate(std.testing.allocator, 42, 20000);
    defer f.deinit();
    var g = try Field.generate(std.testing.allocator, 42, 20000);
    defer g.deinit();
    try std.testing.expectEqualSlices(f32, &f.instances.?[777].translation_scale, &g.instances.?[777].translation_scale);
    var total: u32 = 0;
    for (f.cells, 0..) |cell, c| {
        try std.testing.expectEqual(total, cell.first);
        total += cell.count;
        for (f.instances.?[cell.first..][0..cell.count]) |inst| {
            const p = inst.translation_scale;
            const cx: usize = @min(columns - 1, @as(usize, @intFromFloat((p[0] - origin[0]) / cell_size)));
            const cz: usize = @min(rows - 1, @as(usize, @intFromFloat((p[2] - origin[1]) / cell_size)));
            try std.testing.expectEqual(c, cz * columns + cx);
            const d = @sqrt((p[0] - cell.center[0]) * (p[0] - cell.center[0]) + (p[1] - cell.center[1]) * (p[1] - cell.center[1]) + (p[2] - cell.center[2]) * (p[2] - cell.center[2]));
            try std.testing.expect(d <= cell.radius);
        }
    }
    try std.testing.expectEqual(f.count, total);
    // 64 KiB per frame uploads 1,024 instances; nothing draws before its cells are resident.
    const eye: [3]f32 = .{ 0, 60, -400 };
    const camera: @import("../world/Camera.zig") = .{ .position = math.vec3(eye[0], eye[1], eye[2]), .yaw = 0, .pitch = -0.2 };
    const vp = camera.viewProjection(16.0 / 9.0);
    try std.testing.expectEqual(@as(usize, 0), f.plan(eye, vp).run_count);
    var frames: usize = 0;
    while (f.nextUpload(64 * 1024)) |u| : (frames += 1) {
        try std.testing.expectEqual(f.uploaded, u.first);
        try std.testing.expect(u.data.len * @sizeOf(Instance) <= 64 * 1024);
        f.commit(@intCast(u.data.len));
    }
    try std.testing.expectEqual(@as(usize, 20), frames);
    try std.testing.expect(f.resident() and f.instances == null and f.cpuBytes() == 0);
}

test "plans cull by frustum and distance, pick LOD by distance, and merge contiguous cells" {
    var f = try Field.generate(std.testing.allocator, 7, 50000);
    defer f.deinit();
    while (f.nextUpload(1 << 30)) |u| f.commit(@intCast(u.data.len));
    const Camera = @import("../world/Camera.zig");
    const eye: [3]f32 = .{ 500, 60, 0 };
    const look: Camera = .{ .position = math.vec3(eye[0], eye[1], eye[2]), .yaw = 1.3, .pitch = -0.25 };
    const p = f.plan(eye, look.viewProjection(16.0 / 9.0));
    try std.testing.expect(p.visible_cells > 0 and p.visible_cells < cell_count);
    try std.testing.expect(p.instances[0] > 0 and p.instances[1] > 0);
    // Runs cover exactly the visible instances, never overlap, and merge cells (fewer runs).
    var covered: u32 = 0;
    var last_end: u32 = 0;
    for (p.slice()) |run| {
        try std.testing.expect(run.first >= last_end);
        last_end = run.first + run.count;
        covered += run.count;
        for (f.cells) |cell| if (cell.count > 0 and cell.first >= run.first and cell.first < run.first + run.count) {
            const d = @sqrt((cell.center[0] - eye[0]) * (cell.center[0] - eye[0]) + (cell.center[2] - eye[2]) * (cell.center[2] - eye[2]));
            try std.testing.expectEqual(run.lod == .near, d - cell.radius < lod_distance);
        };
    }
    try std.testing.expectEqual(p.instances[0] + p.instances[1], covered);
    try std.testing.expect(p.run_count < p.visible_cells);
    // Looking straight up sees no cells.
    const up: Camera = .{ .position = math.vec3(eye[0], eye[1], eye[2]), .yaw = 0, .pitch = 1.5 };
    try std.testing.expectEqual(@as(usize, 0), f.plan(eye, up.viewProjection(1.5)).visible_cells);
}
