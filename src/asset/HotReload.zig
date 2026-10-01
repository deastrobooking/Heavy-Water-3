//! Development source watcher. App requests a scan once per second; all disk I/O, hashing,
//! model import and script compilation happen on this worker. Results are transferred once
//! to App.publish, inside the render mutex. A bad edit never replaces the working asset.
const std = @import("std");
const Guid = @import("Guid.zig");
const Meta = @import("Meta.zig");
const Gltf = @import("Gltf.zig");
const Model = @import("Model.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Host = @import("../script/Host.zig");
const Watcher = @This();
pub const capacity = 32;
pub const Kind = enum { model, blueprint, script };
pub const Spec = struct {
    guid: Guid,
    kind: Kind,
    path: []const u8,
    mod: []const u8 = "",
    exports: []const []const u8 = &.{},
    fuel: u64 = 20000,
    memory_pages: u32 = 4,
};
pub const Value = union(Kind) { model: Model, blueprint: *Blueprint, script: *Host };
pub const Event = struct {
    guid: Guid,
    kind: Kind,
    value: ?Value = null,
    failure: ?anyerror = null,
    pub fn deinit(self: *Event, a: std.mem.Allocator) void {
        if (self.value) |v| switch (v) {
            .model => |m| m.deinit(a),
            .blueprint => |b| a.destroy(b),
            .script => |host| {
                host.deinit();
                a.destroy(host);
            },
        };
        self.value = null;
    }
};
const Slot = struct { spec: Spec, arena: std.heap.ArenaAllocator, fingerprint: ?[32]u8 = null, pending: ?Event = null, last_failure: ?anyerror = null };
pub const Stats = struct { scans: u64 = 0, imports: u64 = 0, failures: u64 = 0 };
allocator: std.mem.Allocator,
io: std.Io,
slots: [capacity]Slot = undefined,
count: usize = 0,
mutex: std.Io.Mutex = .init,
condition: std.Io.Condition = .init,
thread: ?std.Thread = null,
requested: bool = false,
busy: bool = false,
stopping: bool = false,
stats: Stats = .{},

pub fn create(a: std.mem.Allocator, io: std.Io) !*Watcher {
    const self = try a.create(Watcher);
    self.* = .{ .allocator = a, .io = io };
    errdefer a.destroy(self);
    self.thread = try std.Thread.spawn(.{}, worker, .{self});
    return self;
}
pub fn destroy(self: *Watcher) void {
    self.mutex.lockUncancelable(self.io);
    self.stopping = true;
    self.condition.broadcast(self.io);
    self.mutex.unlock(self.io);
    if (self.thread) |thread| thread.join();
    for (self.slots[0..self.count]) |*slot| {
        if (slot.pending) |*event| event.deinit(self.allocator);
        slot.arena.deinit();
    }
    self.allocator.destroy(self);
}
/// Specs and their strings are copied, so callers may use stack buffers. Configuration may
/// be extended while running; existing slot addresses never change.
pub fn add(self: *Watcher, spec: Spec) !void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.count == capacity) return error.TooManyWatches;
    for (self.slots[0..self.count]) |s| if (s.spec.guid.eql(spec.guid)) return error.DuplicateGuid;
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    errdefer arena.deinit();
    var owned = spec;
    owned.path = try arena.allocator().dupe(u8, spec.path);
    owned.mod = try arena.allocator().dupe(u8, spec.mod);
    const names = try arena.allocator().alloc([]const u8, spec.exports.len);
    for (names, spec.exports) |*out, name| out.* = try arena.allocator().dupe(u8, name);
    owned.exports = names;
    self.slots[self.count] = .{ .spec = owned, .arena = arena };
    self.count += 1;
}
pub fn scan(self: *Watcher) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.busy) return;
    self.requested = true;
    self.condition.signal(self.io);
}
pub fn take(self: *Watcher) ?Event {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    for (self.slots[0..self.count]) |*slot| if (slot.pending) |event| {
        slot.pending = null;
        return event;
    };
    return null;
}
pub fn snapshot(self: *Watcher) Stats {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.stats;
}
pub fn wait(self: *Watcher, milliseconds: u32) bool {
    const start = std.Io.Timestamp.now(self.io, .awake);
    while (true) {
        self.mutex.lockUncancelable(self.io);
        const done = !self.busy and !self.requested;
        self.mutex.unlock(self.io);
        if (done) return true;
        if (start.untilNow(self.io, .awake).nanoseconds > @as(i96, milliseconds) * std.time.ns_per_ms) return false;
        std.Thread.yield() catch {};
    }
}
fn worker(self: *Watcher) void {
    while (true) {
        self.mutex.lockUncancelable(self.io);
        while (!self.requested and !self.stopping) self.condition.waitUncancelable(self.io, &self.mutex);
        if (self.stopping) {
            self.mutex.unlock(self.io);
            return;
        }
        self.requested = false;
        self.busy = true;
        const count = self.count;
        self.mutex.unlock(self.io);
        for (0..count) |i| {
            self.mutex.lockUncancelable(self.io);
            const blocked = self.slots[i].pending != null;
            self.mutex.unlock(self.io);
            if (blocked) continue; // Bounded staging; don't overwrite an unconsumed result.
            self.poll(i);
        }
        self.mutex.lockUncancelable(self.io);
        self.busy = false;
        self.stats.scans += 1;
        self.mutex.unlock(self.io);
    }
}
const Dependency = struct { uri: []const u8, bytes: []const u8 };
const Snapshot = struct {
    source: []const u8,
    sidecar: []const u8,
    dependencies: []const Dependency,
    fn resolve(context: ?*anyopaque, a: std.mem.Allocator, uri: []const u8) ![]u8 {
        const self: *const Snapshot = @ptrCast(@alignCast(context.?));
        for (self.dependencies) |dep| if (std.mem.eql(u8, dep.uri, uri)) return a.dupe(u8, dep.bytes);
        return error.MissingBuffer;
    }
};
fn read(self: *Watcher, arena: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(64 << 20));
}
fn gather(self: *Watcher, arena: std.mem.Allocator, spec: Spec) !Snapshot {
    var data: Snapshot = .{ .source = try self.read(arena, spec.path), .sidecar = &.{}, .dependencies = &.{} };
    if (spec.kind != .script) data.sidecar = try self.read(arena, try std.fmt.allocPrint(arena, "{s}.meta", .{spec.path}));
    if (spec.kind == .model) {
        const uris = try Gltf.externalBuffers(arena, data.source);
        if (uris.len > 32) return error.TooManyDependencies;
        const deps = try arena.alloc(Dependency, uris.len);
        var total: usize = data.source.len + data.sidecar.len;
        for (uris, deps) |uri, *dep| {
            const path = try std.fs.path.join(arena, &.{ std.fs.path.dirname(spec.path) orelse ".", uri });
            dep.* = .{ .uri = uri, .bytes = try self.read(arena, path) };
            total += dep.bytes.len;
            if (total > 128 << 20) return error.AssetTooLarge;
        }
        data.dependencies = deps;
    }
    return data;
}
fn poll(self: *Watcher, index: usize) void {
    const slot = &self.slots[index]; // Only the worker accesses fingerprints.
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    var data = self.gather(arena.allocator(), slot.spec) catch |err| {
        slot.fingerprint = null;
        self.failed(index, err);
        return;
    };
    var hasher: std.crypto.hash.Blake3 = .init(.{});
    hasher.update(data.source);
    hasher.update(data.sidecar);
    for (data.dependencies) |d| {
        hasher.update(d.uri);
        hasher.update(d.bytes);
    }
    var fingerprint: [32]u8 = undefined;
    hasher.final(&fingerprint);
    // Invalid edits are retried only after a byte change.
    if (slot.fingerprint) |old| if (std.mem.eql(u8, &old, &fingerprint)) return;
    slot.fingerprint = fingerprint;
    const value = self.compile(slot.spec, &data) catch |err| {
        self.failed(index, err);
        return;
    };
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    slot.last_failure = null;
    slot.pending = .{ .guid = slot.spec.guid, .kind = slot.spec.kind, .value = value };
    self.stats.imports += 1;
}
fn failed(self: *Watcher, i: usize, err: anyerror) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    const slot = &self.slots[i];
    if (slot.last_failure) |old| if (old == err) return;
    slot.last_failure = err;
    slot.pending = .{ .guid = slot.spec.guid, .kind = slot.spec.kind, .failure = err };
    self.stats.failures += 1;
}
fn compile(self: *Watcher, spec: Spec, data: *Snapshot) !Value {
    if (spec.kind == .script) {
        const host = try self.allocator.create(Host);
        host.* = .init(self.allocator);
        errdefer {
            host.deinit();
            self.allocator.destroy(host);
        }
        try host.add(spec.mod, data.source, spec.exports, spec.fuel, spec.memory_pages);
        return .{ .script = host };
    }
    const meta = try Meta.checkReload(self.allocator, data.sidecar, spec.path, data.source);
    if (!meta.guid.eql(spec.guid)) return error.GuidChanged;
    if (spec.kind == .blueprint) {
        if (meta.kind != .blueprint) return error.WrongKind;
        const bp = try self.allocator.create(Blueprint);
        errdefer self.allocator.destroy(bp);
        bp.* = try Blueprint.parse(self.allocator, data.source);
        return .{ .blueprint = bp };
    }
    if (meta.kind != .model) return error.WrongKind;
    var model = try Gltf.compile(self.allocator, data.source, .{ .context = data, .load = Snapshot.resolve });
    errdefer model.deinit(self.allocator);
    if (meta.model.scale != 1) {
        for (model.mesh.vertices) |*v| for (&v.position) |*c| {
            c.* *= meta.model.scale;
            if (!std.math.isFinite(c.*)) return error.InvalidPosition;
        };
        model.computeBounds();
    }
    return .{ .model = model };
}

fn testEvent(w: *Watcher) !Event {
    w.scan();
    try std.testing.expect(w.wait(5000));
    return w.take() orelse error.MissingReload;
}
test "source and settings edits stage replacements; bad identity and missing files recover" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/crate.gltf", .{tmp.sub_path});
    defer a.free(path);
    const source = @embedFile("crate.gltf");
    const guid: Guid = .{ .value = 1234 };
    const meta = try Meta.refresh(a, null, path, source, guid);
    defer a.free(meta);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf", .data = source });
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf.meta", .data = meta });
    const watcher = try create(a, io);
    defer watcher.destroy();
    try watcher.add(.{ .guid = guid, .kind = .model, .path = path });
    var first = try testEvent(watcher);
    defer first.deinit(a);
    try std.testing.expect(first.failure == null);
    const half = first.value.?.model.halfExtents();
    watcher.scan();
    try std.testing.expect(watcher.wait(5000));
    try std.testing.expect(watcher.take() == null);
    try std.testing.expectEqual(@as(u64, 1), watcher.snapshot().imports);
    const edit = try std.mem.replaceOwned(u8, a, source, "0.86", "0.26");
    defer a.free(edit);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf", .data = edit });
    var changed = try testEvent(watcher);
    defer changed.deinit(a);
    try std.testing.expectApproxEqAbs(@as(f32, 0.26), changed.value.?.model.materials[0].base_color[0], 0.001);
    const scaled = try std.mem.replaceOwned(u8, a, meta, "\"scale\": 1", "\"scale\": 2");
    defer a.free(scaled);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf.meta", .data = scaled });
    var resized = try testEvent(watcher);
    defer resized.deinit(a);
    for (half, resized.value.?.model.halfExtents()) |x, y| try std.testing.expectApproxEqAbs(x * 2, y, 0.001);
    const wrong = try Meta.refresh(a, null, path, source, .{ .value = 999 });
    defer a.free(wrong);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf.meta", .data = wrong });
    var bad = try testEvent(watcher);
    defer bad.deinit(a);
    try std.testing.expectEqual(error.GuidChanged, bad.failure.?);
    watcher.scan();
    try std.testing.expect(watcher.wait(5000));
    try std.testing.expect(watcher.take() == null);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf.meta", .data = meta });
    var recovered = try testEvent(watcher);
    defer recovered.deinit(a);
    try std.testing.expect(recovered.failure == null);
    try tmp.dir.deleteFile(io, "crate.gltf");
    var missing = try testEvent(watcher);
    defer missing.deinit(a);
    try std.testing.expect(missing.failure != null);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf", .data = edit });
    var restored = try testEvent(watcher);
    defer restored.deinit(a);
    try std.testing.expect(restored.failure == null);
}
test "script replacement is staged; malformed edits preserve the running host" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/logic.wasm", .{tmp.sub_path});
    defer a.free(path);
    const bytes = @embedFile("glowworks.wasm");
    try tmp.dir.writeFile(io, .{ .sub_path = "logic.wasm", .data = bytes });
    var live: Host = .init(a);
    defer live.deinit();
    try live.add("glowworks", bytes, &.{ "breathe", "majority" }, 20000, 4);
    const watcher = try create(a, io);
    defer watcher.destroy();
    try watcher.add(.{ .guid = .{ .value = 12 }, .kind = .script, .path = path, .mod = "glowworks", .exports = &.{ "majority", "breathe" } });
    var ready = try testEvent(watcher);
    defer ready.deinit(a);
    try std.testing.expect(ready.failure == null);
    try live.replaceFrom(ready.value.?.script);
    try std.testing.expectEqual(@as(?usize, 0), live.find("glowworks.breathe"));
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), live.call("glowworks.breathe", .{ 1, 0, 0, 0 }, 0), 1e-6);
    // Patch the compiled f32 constant (0.55 -> 0.25) in the fixture's bytecode.
    const changed_wasm = try a.dupe(u8, bytes);
    defer a.free(changed_wasm);
    const from = [5]u8{ 0x43, 0xcd, 0xcc, 0x0c, 0x3f };
    const at = std.mem.indexOf(u8, changed_wasm, &from) orelse return error.FixtureConstantMissing;
    std.mem.writeInt(u32, changed_wasm[at + 1 ..][0..4], @bitCast(@as(f32, 0.25)), .little);
    try tmp.dir.writeFile(io, .{ .sub_path = "logic.wasm", .data = changed_wasm });
    var changed_script = try testEvent(watcher);
    defer changed_script.deinit(a);
    try std.testing.expect(changed_script.failure == null);
    try live.replaceFrom(changed_script.value.?.script);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), live.call("glowworks.breathe", .{ 1, 0, 0, 0 }, 0), 1e-6);

    try tmp.dir.writeFile(io, .{ .sub_path = "logic.wasm", .data = "broken wasm" });
    var bad = try testEvent(watcher);
    defer bad.deinit(a);
    try std.testing.expect(bad.failure != null and bad.value == null);
    try std.testing.expectEqual(@as(f32, 1), live.call("glowworks.majority", .{ 1, 1, 0, 0 }, 0));
    var incomplete: Host = .init(a);
    defer incomplete.deinit();
    try incomplete.add("glowworks", bytes, &.{"majority"}, 20000, 4);
    try std.testing.expectError(error.MissingExport, live.replaceFrom(&incomplete));
    try std.testing.expectEqual(@as(usize, 2), live.script_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), live.call("glowworks.breathe", .{ 1, 0, 0, 0 }, 0), 1e-6);
}

test "external glTF buffer edits reload even when the JSON source is unchanged" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/crate.gltf", .{tmp.sub_path});
    defer a.free(path);
    const Doc = struct { buffers: []const struct { uri: []const u8 } };
    const parsed = try std.json.parseFromSlice(Doc, a, @embedFile("crate.gltf"), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const uri = parsed.value.buffers[0].uri;
    const encoded = uri[(std.mem.indexOfScalar(u8, uri, ',').? + 1)..];
    const decoder = std.base64.standard.Decoder;
    const binary = try a.alloc(u8, try decoder.calcSizeForSlice(encoded));
    defer a.free(binary);
    try decoder.decode(binary, encoded);
    const source = try std.mem.replaceOwned(u8, a, @embedFile("crate.gltf"), uri, "mesh.bin");
    defer a.free(source);
    const meta = try Meta.refresh(a, null, path, source, .{ .value = 45 });
    defer a.free(meta);
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf", .data = source });
    try tmp.dir.writeFile(io, .{ .sub_path = "crate.gltf.meta", .data = meta });
    try tmp.dir.writeFile(io, .{ .sub_path = "mesh.bin", .data = binary });
    const watcher = try create(a, io);
    defer watcher.destroy();
    try watcher.add(.{ .guid = .{ .value = 45 }, .kind = .model, .path = path });
    var first = try testEvent(watcher);
    defer first.deinit(a);
    try std.testing.expect(first.failure == null);
    // First position's X changes; every other source byte stays identical.
    const x = first.value.?.model.mesh.vertices[0].position[0] + 0.25;
    std.mem.writeInt(u32, binary[0..4], @bitCast(x), .little);
    try tmp.dir.writeFile(io, .{ .sub_path = "mesh.bin", .data = binary });
    var edited = try testEvent(watcher);
    defer edited.deinit(a);
    try std.testing.expect(edited.failure == null);
    try std.testing.expectApproxEqAbs(x, edited.value.?.model.mesh.vertices[0].position[0], 0.001);
    try std.testing.expectEqual(@as(u64, 2), watcher.snapshot().imports);
}
