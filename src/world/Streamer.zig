const std = @import("std");
const Key = @import("ChunkKey.zig");
const Chunk = @import("../procedural/Chunk.zig");
const Mesh = @import("../render/Mesh.zig");
const Scatter = @import("../procedural/Scatter.zig");
const Streamer = @This();

pub const active_radius = 1;
pub const render_radius = 2;
pub const generation_radius = 3;
pub const capacity = (generation_radius * 2 + 1) * (generation_radius * 2 + 1);
pub const render_capacity = (render_radius * 2 + 1) * (render_radius * 2 + 1);
pub const State = enum { empty, queued, generating, canceling, ready };
pub const Handle = struct {
    slot: usize,
    generation: u64,
    pub fn eql(a: Handle, b: Handle) bool {
        return a.slot == b.slot and a.generation == b.generation;
    }
};
pub const Payload = struct {
    vertices: [Chunk.vertex_count]Mesh.Vertex,
    indices: [Chunk.index_count]u32,
    objects: [Scatter.capacity]Scatter.Object,
    object_count: usize,

    pub fn mesh(self: *Payload) Mesh {
        return .{ .vertices = &self.vertices, .indices = &self.indices };
    }
};
const Slot = struct {
    key: Key = .{ .x = 0, .z = 0 },
    token: std.atomic.Value(u64) = .init(0),
    state: State = .empty,
};
pub const View = struct { key: Key, handle: Handle, state: State };
pub const Stats = struct {
    queued: usize = 0,
    generating: usize = 0,
    ready: usize = 0,
    active: usize = 0,
    generated: u64 = 0,
    canceled: u64 = 0,
    evicted: u64 = 0,
    generation_ms: f32 = 0,
    max_generation_ms: f32 = 0,
    pool_allocations: u32 = 2,
    cpu_bytes: usize = @sizeOf(Streamer) + capacity * @sizeOf(Payload),
};
pub const Snapshot = struct { views: [capacity]View, stats: Stats };

allocator: std.mem.Allocator,
io: std.Io,
seed: u64,
payloads: []Payload,
slots: [capacity]Slot = @splat(.{}),
center: Key = .{ .x = 0, .z = 0 },
mutex: std.Io.Mutex = .init,
condition: std.Io.Condition = .init,
thread: ?std.Thread = null,
stopping: bool = false,
stats: Stats = .{},

/// Two persistent allocations, no allocations for generation or per-frame planning.
/// Keep the returned pointer stable until destroy joins the worker.
pub fn create(allocator: std.mem.Allocator, io: std.Io, seed: u64) !*Streamer {
    const self = try allocator.create(Streamer);
    errdefer allocator.destroy(self);
    const payloads = try allocator.alloc(Payload, capacity);
    self.* = .{ .allocator = allocator, .io = io, .seed = seed, .payloads = payloads };
    return self;
}

pub fn start(self: *Streamer) !void {
    std.debug.assert(self.thread == null);
    self.thread = try std.Thread.spawn(.{}, worker, .{self});
}

pub fn destroy(self: *Streamer) void {
    self.mutex.lockUncancelable(self.io);
    self.stopping = true;
    for (&self.slots) |*slot| _ = slot.token.fetchAdd(1, .release);
    self.condition.broadcast(self.io);
    self.mutex.unlock(self.io);
    if (self.thread) |thread| thread.join();
    const allocator = self.allocator;
    allocator.free(self.payloads);
    allocator.destroy(self);
}

/// Called only by the render coordinator. Worker computation never holds this mutex.
pub fn plan(self: *Streamer, center: Key) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.center = center;
    for (&self.slots) |*slot| {
        if (slot.state == .empty or slot.state == .canceling or Key.distance(slot.key, center) <= generation_radius) continue;
        _ = slot.token.fetchAdd(1, .release);
        switch (slot.state) {
            .generating => slot.state = .canceling,
            .ready => {
                slot.state = .empty;
                self.stats.evicted += 1;
            },
            .queued => {
                slot.state = .empty;
                self.stats.canceled += 1;
            },
            else => unreachable,
        }
    }
    // Near-to-far assignment also makes startup and cache-miss recovery predictable.
    for (0..generation_radius + 1) |ring| {
        const radius: i32 = @intCast(ring);
        var z = -radius;
        while (z <= radius) : (z += 1) {
            var x = -radius;
            while (x <= radius) : (x += 1) {
                if (@max(@abs(x), @abs(z)) != ring) continue;
                const key: Key = .{ .x = center.x + x, .z = center.z + z };
                if (!key.valid()) continue;
                var exists = false;
                var free: ?usize = null;
                for (self.slots, 0..) |slot, i| {
                    if (slot.state == .empty and free == null) free = i;
                    if (slot.state != .empty and slot.state != .canceling and Key.eql(slot.key, key)) exists = true;
                }
                if (exists) continue;
                if (free) |i| {
                    self.slots[i].key = key;
                    _ = self.slots[i].token.fetchAdd(1, .release);
                    self.slots[i].state = .queued;
                }
            }
        }
    }
    self.condition.signal(self.io);
}

pub fn snapshot(self: *Streamer) Snapshot {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    var result: Snapshot = .{ .views = undefined, .stats = self.stats };
    for (self.slots, 0..) |slot, i| {
        result.views[i] = .{ .key = slot.key, .state = slot.state, .handle = .{ .slot = i, .generation = slot.token.load(.acquire) } };
        switch (slot.state) {
            .queued => result.stats.queued += 1,
            .generating, .canceling => result.stats.generating += 1,
            .ready => {
                result.stats.ready += 1;
                if (Key.distance(slot.key, self.center) <= active_radius) result.stats.active += 1;
            },
            .empty => {},
        }
    }
    return result;
}

/// A ready payload stays immutable until the coordinator's next plan() call.
/// It must not be retained across frames without rechecking its generation handle.
pub fn payload(self: *Streamer, view: View) ?*Payload {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (view.handle.slot >= capacity) return null;
    const slot = &self.slots[view.handle.slot];
    if (slot.state != .ready or slot.token.load(.acquire) != view.handle.generation) return null;
    return &self.payloads[view.handle.slot];
}

fn nextJob(self: *Streamer) ?usize {
    var best: ?usize = null;
    var distance: u32 = std.math.maxInt(u32);
    for (self.slots, 0..) |slot, i| {
        const d = Key.distance(slot.key, self.center);
        if (slot.state == .queued and d < distance) {
            best = i;
            distance = d;
        }
    }
    return best;
}

fn worker(self: *Streamer) void {
    while (true) {
        self.mutex.lockUncancelable(self.io);
        while (!self.stopping and self.nextJob() == null) self.condition.waitUncancelable(self.io, &self.mutex);
        if (self.stopping) {
            self.mutex.unlock(self.io);
            return;
        }
        const i = self.nextJob().?;
        const slot = &self.slots[i];
        const key = slot.key;
        const token = slot.token.load(.acquire);
        slot.state = .generating;
        self.mutex.unlock(self.io);

        const begin = std.Io.Timestamp.now(self.io, .awake);
        const data = &self.payloads[i];
        const complete = Chunk.fill(self.seed, key.x, key.z, &data.vertices, &data.indices, .{ .token = &slot.token, .expected = token });
        if (complete and slot.token.load(.acquire) == token) data.object_count = Scatter.generate(self.seed, key, &data.objects);
        const ms = @as(f32, @floatFromInt(begin.durationTo(std.Io.Timestamp.now(self.io, .awake)).nanoseconds)) / 1e6;

        self.mutex.lockUncancelable(self.io);
        if (complete and slot.token.load(.acquire) == token) {
            slot.state = .ready;
            self.stats.generated += 1;
            self.stats.generation_ms = ms;
            self.stats.max_generation_ms = @max(self.stats.max_generation_ms, ms);
        } else {
            slot.state = .empty;
            self.stats.canceled += 1;
        }
        self.mutex.unlock(self.io);
    }
}

test "planner bounds work, prioritizes center and invalidates recycled handles" {
    const stream = try create(std.testing.allocator, std.testing.io, 42);
    defer stream.destroy();
    stream.plan(.{ .x = 0, .z = 0 });
    const first = stream.snapshot();
    try std.testing.expectEqual(@as(usize, capacity), first.stats.queued);
    try std.testing.expect(Key.eql(.{ .x = 0, .z = 0 }, first.views[stream.nextJob().?].key));
    for (0..20) |step| {
        const key: Key = .{ .x = @as(i32, @intCast(step)) * 10 - 100, .z = -8 };
        stream.plan(key);
        const state = stream.snapshot();
        try std.testing.expectEqual(@as(usize, capacity), state.stats.queued);
        for (state.views) |view| try std.testing.expect(Key.distance(view.key, key) <= generation_radius);
    }
    try std.testing.expect(!Handle.eql(first.views[0].handle, stream.snapshot().views[0].handle));
}

test "canceled terrain work stops before writing a row" {
    const data = try std.testing.allocator.create(Payload);
    defer std.testing.allocator.destroy(data);
    var token: std.atomic.Value(u64) = .init(2);
    try std.testing.expect(!Chunk.fill(42, 0, 0, &data.vertices, &data.indices, .{ .token = &token, .expected = 1 }));
}

fn awaitCenter(stream: *Streamer, key: Key) !View {
    const begin = std.Io.Timestamp.now(std.testing.io, .awake);
    while (begin.durationTo(std.Io.Timestamp.now(std.testing.io, .awake)).nanoseconds < 5_000_000_000) {
        stream.plan(key);
        const snapshot_value = stream.snapshot();
        try std.testing.expect(snapshot_value.stats.queued + snapshot_value.stats.generating + snapshot_value.stats.ready <= capacity);
        for (snapshot_value.views) |view| if (view.state == .ready and Key.eql(view.key, key)) return view;
        try std.Io.sleep(std.testing.io, .fromMilliseconds(1), .awake);
    }
    return error.GenerationTimedOut;
}

fn fingerprint(data: *const Payload) u64 {
    var hash = std.hash.Wyhash.init(0);
    hash.update(std.mem.sliceAsBytes(&data.vertices));
    hash.update(std.mem.sliceAsBytes(&data.indices));
    for (data.objects[0..data.object_count]) |object| {
        std.hash.autoHash(&hash, object.local_id);
        std.hash.autoHash(&hash, @intFromEnum(object.kind));
        hash.update(std.mem.asBytes(&object.transform.position));
        hash.update(std.mem.asBytes(&object.transform.scale));
        hash.update(std.mem.asBytes(&object.tint));
    }
    return hash.final();
}

test "background worker unloads and regenerates identically without new pool allocations" {
    var counting = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    const stream = try create(counting.allocator(), std.testing.io, 42);
    {
        defer stream.destroy();
        try stream.start();
        const origin: Key = .{ .x = -3, .z = 2 };
        const original = try awaitCenter(stream, origin);
        const expected = fingerprint(stream.payload(original).?);
        _ = try awaitCenter(stream, .{ .x = 50, .z = -80 });
        try std.testing.expect(stream.payload(original) == null);
        // Rapid motion invalidates queued/in-flight work; no third allocation may succeed.
        for (0..40) |i| stream.plan(.{ .x = @as(i32, @intCast(i)) * 10, .z = 10 });
        const regenerated = try awaitCenter(stream, origin);
        try std.testing.expect(!Handle.eql(original.handle, regenerated.handle));
        try std.testing.expectEqual(expected, fingerprint(stream.payload(regenerated).?));
        try std.testing.expectEqual(@as(usize, 2), counting.allocations);
        try std.testing.expect(!counting.has_induced_failure);
        // Shutdown must cancel pending generation and join before freeing the payload pool.
        stream.plan(.{ .x = 100, .z = 100 });
    }
    try std.testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);
}

test "in-flight slots cannot be recycled until the worker acknowledges cancellation" {
    const stream = try create(std.testing.allocator, std.testing.io, 42);
    defer stream.destroy();
    stream.plan(.{ .x = 0, .z = 0 });
    stream.slots[0].state = .generating;
    const token = stream.slots[0].token.load(.acquire);
    stream.plan(.{ .x = 100, .z = 100 });
    try std.testing.expectEqual(State.canceling, stream.slots[0].state);
    try std.testing.expect(stream.slots[0].token.load(.acquire) != token);
    try std.testing.expectEqual(@as(usize, capacity - 1), stream.snapshot().stats.queued);
}

fn allocationProbe(allocator: std.mem.Allocator) !void {
    const stream = try create(allocator, std.testing.io, 42);
    defer stream.destroy();
}

test "streamer startup cleans up partial allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
