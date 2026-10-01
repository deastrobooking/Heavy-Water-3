//! Background asset loading. A worker thread turns requests into `Model`s: pack entries (read
//! at their offset, hash-verified, decoded), embedded `HWMS` bytes, or generator functions
//! (procedural meshes such as Arbors and the district). The caller gets a ticket immediately,
//! watches its state (`queued → loading → ready | failed`) and its group's progress, and takes
//! the finished model on its own thread. GPU upload is the renderer's job, under its byte budget.
//!
//! Fixed capacity, one worker, no allocation on the caller's thread beyond what `take` returns.
const std = @import("std");
const Model = @import("Model.zig");
const Pack = @import("Pack.zig");
const Guid = @import("Guid.zig");
const Loader = @This();

pub const capacity = 256;
pub const max_groups = 16;
pub const max_packs = 4;
pub const State = enum(u8) { empty, queued, loading, ready, failed, taken };
pub const Ticket = struct { index: u16 };
pub const Generator = struct {
    context: *const anyopaque,
    build: *const fn (context: *const anyopaque, allocator: std.mem.Allocator) anyerror!Model,
};
pub const Source = union(enum) {
    /// An entry of an opened pack (by `openPack` index).
    pack: struct { pack: u8, guid: Guid },
    /// `HWMS` bytes that outlive the request (usually embedded).
    bytes: []const u8,
    generate: Generator,
};
const Slot = struct {
    state: State = .empty,
    group: u8 = 0,
    source: Source = undefined,
    model: ?Model = null,
    failure: ?anyerror = null,
};
const OpenPack = struct { file: std.Io.File, toc: Pack };
pub const Stats = struct { loaded: u32 = 0, failed: u32 = 0, bytes_read: u64 = 0, worst_job_ms: f32 = 0 };

allocator: std.mem.Allocator,
io: std.Io,
slots: [capacity]Slot = @splat(.{}),
packs: [max_packs]?OpenPack = @splat(null),
mutex: std.Io.Mutex = .init,
condition: std.Io.Condition = .init,
thread: ?std.Thread = null,
stopping: bool = false,
stats: Stats = .{},

/// Keep the returned pointer stable until `destroy`.
pub fn create(allocator: std.mem.Allocator, io: std.Io) !*Loader {
    const self = try allocator.create(Loader);
    self.* = .{ .allocator = allocator, .io = io };
    errdefer allocator.destroy(self);
    self.thread = try std.Thread.spawn(.{}, worker, .{self});
    return self;
}

/// Stops the worker (finishing the job in flight) and frees untaken models and packs.
pub fn destroy(self: *Loader) void {
    self.mutex.lockUncancelable(self.io);
    self.stopping = true;
    self.condition.broadcast(self.io);
    self.mutex.unlock(self.io);
    if (self.thread) |t| t.join();
    for (&self.slots) |*slot| if (slot.model) |m| m.deinit(self.allocator);
    for (&self.packs) |*p| if (p.*) |pack| {
        pack.toc.deinit(self.allocator);
        pack.file.close(self.io);
    };
    self.allocator.destroy(self);
}

/// Opens a pack file and validates its table of contents; its entries become requestable.
pub fn openPack(self: *Loader, dir: std.Io.Dir, path: []const u8) !u8 {
    const slot = for (self.packs, 0..) |p, i| {
        if (p == null) break i;
    } else return error.TooManyPacks;
    const file = try dir.openFile(self.io, path, .{});
    errdefer file.close(self.io);
    const size = (try file.stat(self.io)).size;
    var head: [Pack.header_size]u8 = undefined;
    if (try file.readPositionalAll(self.io, &head, 0) != head.len) return error.NotAPack;
    const count = std.mem.readInt(u32, head[8..12], .little);
    if (count > Pack.max_entries) return error.TooManyEntries;
    const table = try self.allocator.alloc(u8, Pack.header_size + @as(usize, count) * Pack.entry_size);
    defer self.allocator.free(table);
    if (try file.readPositionalAll(self.io, table, 0) != table.len) return error.Truncated;
    const toc = try Pack.open(self.allocator, table, size);
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.packs[slot] = .{ .file = file, .toc = toc };
    return @intCast(slot);
}

pub fn request(self: *Loader, source: Source, group: u8) !Ticket {
    if (group >= max_groups) return error.InvalidGroup;
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    const index = for (self.slots, 0..) |s, i| {
        if (s.state == .empty) break i;
    } else return error.LoaderFull;
    self.slots[index] = .{ .state = .queued, .group = group, .source = source };
    self.condition.signal(self.io);
    return .{ .index = @intCast(index) };
}

pub fn state(self: *Loader, ticket: Ticket) State {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.slots[ticket.index].state;
}

pub fn failure(self: *Loader, ticket: Ticket) ?anyerror {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.slots[ticket.index].failure;
}

/// The finished model, once; the caller owns it. Null until ready (or after failure).
pub fn take(self: *Loader, ticket: Ticket) ?Model {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    const slot = &self.slots[ticket.index];
    if (slot.state != .ready) return null;
    const m = slot.model.?;
    slot.model = null;
    slot.state = .taken;
    return m;
}

/// Frees a ticket's slot for reuse after its result was taken or its failure handled.
pub fn release(self: *Loader, ticket: Ticket) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    const slot = &self.slots[ticket.index];
    if (slot.state == .queued or slot.state == .loading) return;
    if (slot.model) |m| m.deinit(self.allocator);
    slot.* = .{};
}

/// Fraction of a group's requests that have finished (ready, taken, or failed); 1 when empty.
pub fn progress(self: *Loader, group: u8) f32 {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    var total: u32 = 0;
    var done: u32 = 0;
    for (self.slots) |s| {
        if (s.state == .empty or s.group != group) continue;
        total += 1;
        done += @intFromBool(s.state == .ready or s.state == .taken or s.state == .failed);
    }
    return if (total == 0) 1 else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total));
}

fn worker(self: *Loader) void {
    while (true) {
        self.mutex.lockUncancelable(self.io);
        var index: ?usize = null;
        while (true) {
            for (self.slots, 0..) |s, i| if (s.state == .queued) {
                index = i;
                break;
            };
            if (index != null or self.stopping) break;
            self.condition.waitUncancelable(self.io, &self.mutex);
        }
        const i = index orelse {
            self.mutex.unlock(self.io);
            return;
        };
        self.slots[i].state = .loading;
        const source = self.slots[i].source;
        const pack = if (source == .pack) self.packs[source.pack.pack] else null;
        self.mutex.unlock(self.io);

        var timer = std.Io.Timestamp.now(self.io, .awake);
        var read: u64 = 0;
        const result = self.run(source, pack, &read);
        const ms = @as(f32, @floatFromInt(timer.untilNow(self.io, .awake).nanoseconds)) / 1e6;

        self.mutex.lockUncancelable(self.io);
        self.stats.bytes_read += read;
        self.stats.worst_job_ms = @max(self.stats.worst_job_ms, ms);
        if (result) |model| {
            self.slots[i].model = model;
            self.slots[i].state = .ready;
            self.stats.loaded += 1;
        } else |err| {
            self.slots[i].failure = err;
            self.slots[i].state = .failed;
            self.stats.failed += 1;
        }
        self.mutex.unlock(self.io);
    }
}

fn run(self: *Loader, source: Source, pack: ?OpenPack, read: *u64) !Model {
    switch (source) {
        .bytes => |b| return Model.decode(self.allocator, b),
        .generate => |g| return g.build(g.context, self.allocator),
        .pack => |p| {
            const open = pack orelse return error.UnknownPack;
            const entry = open.toc.find(p.guid) orelse return error.UnknownAsset;
            if (entry.kind != .model) return error.WrongKind;
            const blob = try self.allocator.alloc(u8, entry.size);
            defer self.allocator.free(blob);
            if (try open.file.readPositionalAll(self.io, blob, entry.offset) != blob.len) return error.Truncated;
            read.* = blob.len;
            try Pack.verify(entry, blob);
            return Model.decode(self.allocator, blob);
        },
    }
}

/// Blocks (test and tooling use) until a group has finished or `limit_ms` passes.
pub fn wait(self: *Loader, group: u8, limit_ms: u32) bool {
    const start = std.Io.Timestamp.now(self.io, .awake);
    while (self.progress(group) < 1) {
        if (start.untilNow(self.io, .awake).nanoseconds > @as(i96, limit_ms) * std.time.ns_per_ms) return false;
        std.Thread.yield() catch {};
    }
    return true;
}

fn testModel(allocator: std.mem.Allocator, vertices: usize) ![]u8 {
    const Mesh = @import("../render/Mesh.zig");
    const verts = try allocator.alloc(Mesh.Vertex, vertices);
    const idx = try allocator.alloc(u32, (vertices / 3) * 3);
    for (verts, 0..) |*v, i| v.* = .{ .position = .{ @floatFromInt(i % 97), @floatFromInt(i / 97), 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 } };
    for (idx, 0..) |*x, i| x.* = @intCast(i);
    const model = try Model.fromMesh(allocator, .{ .vertices = verts, .indices = idx }, .named("test", .{ 1, 1, 1, 1 }));
    defer model.deinit(allocator);
    return model.encode(allocator);
}

test "a pack of 64 models loads in the background with progress; damage fails one asset only" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var inputs: [64]Pack.Input = undefined;
    var blobs: [64][]u8 = undefined;
    for (&inputs, &blobs, 0..) |*in, *blob, i| {
        blob.* = try testModel(a, 300 + i * 150);
        in.* = .{ .guid = .{ .value = 0x1000 + i }, .kind = .model, .data = blob.* };
    }
    defer for (blobs) |b| a.free(b);
    const pack_bytes = try Pack.write(a, &inputs);
    defer a.free(pack_bytes);
    // Corrupt the last blob's payload after the table was hashed.
    pack_bytes[pack_bytes.len - 5] ^= 0xff;
    try tmp.dir.writeFile(io, .{ .sub_path = "content.hwpk", .data = pack_bytes });

    const loader = try Loader.create(a, io);
    defer loader.destroy();
    const pack = try loader.openPack(tmp.dir, "content.hwpk");
    var tickets: [64]Ticket = undefined;
    for (&tickets, 0..) |*t, i| t.* = try loader.request(.{ .pack = .{ .pack = pack, .guid = .{ .value = 0x1000 + i } } }, 1);
    const Gen = struct {
        fn build(_: *const anyopaque, allocator: std.mem.Allocator) anyerror!Model {
            return Model.fromMesh(allocator, try @import("../render/Mesh.zig").block(allocator), .named("generated", .{ 1, 1, 1, 1 }));
        }
    };
    const generated = try loader.request(.{ .generate = .{ .context = &tickets, .build = Gen.build } }, 2);
    const missing = try loader.request(.{ .pack = .{ .pack = pack, .guid = .{ .value = 0x9999 } } }, 2);
    try std.testing.expect(loader.wait(1, 10_000) and loader.wait(2, 10_000));
    try std.testing.expectEqual(@as(f32, 1), loader.progress(1));
    for (tickets[0..63], 0..) |t, i| {
        const model = loader.take(t).?;
        defer model.deinit(a);
        try std.testing.expectEqual(300 + i * 150, model.mesh.vertices.len);
        try std.testing.expect(loader.take(t) == null); // taken once
        loader.release(t);
    }
    try std.testing.expectEqual(State.failed, loader.state(tickets[63]));
    try std.testing.expectEqual(error.HashMismatch, loader.failure(tickets[63]).?);
    try std.testing.expectEqual(error.UnknownAsset, loader.failure(missing).?);
    const block = loader.take(generated).?;
    defer block.deinit(a);
    try std.testing.expectEqual(@as(usize, 24), block.mesh.vertices.len);
    try std.testing.expectEqual(@as(u32, 64), loader.stats.loaded);
    try std.testing.expectEqual(@as(u32, 2), loader.stats.failed);
    // A damaged table is refused when the pack is opened.
    try tmp.dir.writeFile(io, .{ .sub_path = "bad.hwpk", .data = "HWPK\x07\x00\x00\x00" ++ [_]u8{0} ** 8 });
    try std.testing.expectError(error.UnsupportedPackVersion, loader.openPack(tmp.dir, "bad.hwpk"));
}
