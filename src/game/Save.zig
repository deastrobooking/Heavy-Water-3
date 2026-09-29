const std = @import("std");
const Seed = @import("../procedural/Seed.zig");
const Catalog = @import("../asset/Catalog.zig");
const Modifications = @import("../world/Modifications.zig");
const Player = @import("Player.zig");
const Blueprint = @import("../machine/Blueprint.zig");

/// JSON save document. Any change to its meaning bumps `format_version`. A save is only loaded
/// into a world with the same seed, generator version, and content version; old worlds must not
/// silently regenerate with different rules.
/// v2 added machine state; v3 vehicle bodies; v4 made the save describe the whole world:
/// every placed machine as a full blueprint document (so rewiring persists) with its origin
/// and quarter-turn yaw, and every crate; v5 added the captured prefab library.
/// Older saves are rejected, not migrated.
pub const format_version: u32 = 5;
pub const default_path = "saves/quicksave.json";
pub const max_bytes = 4 << 20;

/// A crate slot; `id` is its slot index in the session.
pub const PropState = struct { id: u32, position: [3]f32, velocity: [3]f32 };
/// Persistent per-device machine state, in blueprint device order.
/// A placed machine: its (possibly edited) blueprint, placement, and persistent state.
pub const MachineState = struct {
    slot: u32,
    blueprint: Blueprint.Doc,
    origin: [3]f32,
    yaw: u8 = 0,
    workshop: bool = false,
    states: []const f32,
    body: ?BodyState = null,
};
/// A vehicle chassis: pose and velocities.
pub const BodyState = struct { position: [3]f32, orientation: [4]f32, linear: [3]f32, angular: [3]f32 };
pub const PlayerState = struct { feet: [3]f32, yaw: f32, pitch: f32, mode: Player.Mode };
pub const Document = struct {
    format: u32 = format_version,
    seed: u64,
    generator: u32 = Seed.generator_version,
    content: u32 = Catalog.content_version,
    tick: u64,
    player: PlayerState,
    props: []const PropState,
    collected: []const Modifications.ObjectRef,
    machines: []const MachineState,
    prefabs: []const Blueprint.Doc,
};

pub fn encode(allocator: std.mem.Allocator, doc: Document) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, doc, .{ .whitespace = .indent_2 });
}

pub const LoadError = error{ UnsupportedSaveFormat, SeedMismatch, GeneratorMismatch, ContentMismatch, InvalidSave };

/// Parses and validates the document's own structure (versions, ranges, finite values).
/// Blueprints and machine state are validated by the caller before anything is applied.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, seed: u64, prop_count: usize, machine_slots: usize) !std.json.Parsed(Document) {
    const parsed = std.json.parseFromSlice(Document, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidSave;
    errdefer parsed.deinit();
    const doc = parsed.value;
    if (doc.format != format_version) return error.UnsupportedSaveFormat;
    if (doc.seed != seed) return error.SeedMismatch;
    if (doc.generator != Seed.generator_version) return error.GeneratorMismatch;
    if (doc.content != Catalog.content_version) return error.ContentMismatch;
    if (doc.collected.len > Modifications.capacity or doc.props.len > prop_count) return error.InvalidSave;
    for (doc.player.feet) |v| if (!finite(v)) return error.InvalidSave;
    if (!finite(doc.player.yaw) or !finite(doc.player.pitch)) return error.InvalidSave;
    if (doc.machines.len > machine_slots) return error.InvalidSave;
    for (doc.machines, 0..) |m, i| {
        if (m.slot >= machine_slots or m.yaw > 3) return error.InvalidSave;
        for (doc.machines[0..i]) |other| if (other.slot == m.slot) return error.InvalidSave;
        for (m.origin) |v| if (!finite(v)) return error.InvalidSave;
    }
    for (doc.machines) |m| if (m.body) |b| {
        for (b.position ++ b.orientation ++ b.linear ++ b.angular) |v| if (!finite(v)) return error.InvalidSave;
        const q = b.orientation;
        if (@abs(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3] - 1) > 0.01) return error.InvalidSave;
    };
    for (doc.props, 0..) |p, i| {
        if (p.id >= prop_count) return error.InvalidSave;
        for (doc.props[0..i]) |q| if (q.id == p.id) return error.InvalidSave;
        for (p.position ++ p.velocity) |v| if (!finite(v)) return error.InvalidSave;
    }
    return parsed;
}

fn finite(v: f32) bool {
    return std.math.isFinite(v) and @abs(v) < 1e6;
}

/// Writes to a temporary file, then renames it over the save, so a crash never leaves a torn save.
pub fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |dir| try cwd.createDirPath(io, dir);
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const temporary = try std.fmt.bufPrint(&buffer, "{s}.tmp", .{path});
    try cwd.writeFile(io, .{ .sub_path = temporary, .data = bytes });
    try cwd.rename(temporary, cwd, path, io);
}

pub fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes));
}

test "save documents round-trip and reject mismatched or malformed input" {
    const allocator = std.testing.allocator;
    const props = [_]PropState{.{ .id = 1, .position = .{ 1, 2, 3 }, .velocity = .{ 0, 0, 0 } }};
    const collected = [_]Modifications.ObjectRef{.{ .x = -3, .z = 2, .id = 17 }};
    const devices = [_]Blueprint.DocDevice{.{ .id = "lamp", .kind = .lamp, .watts = 5 }};
    const machines = [_]MachineState{.{ .slot = 3, .blueprint = .{ .format = 1, .name = "bench", .devices = &devices }, .origin = .{ 1, 2, 3 }, .yaw = 1, .states = &.{0} }};
    const doc: Document = .{ .seed = 0xFFFF_FFFF_FFFF_FFF1, .tick = 9, .player = .{ .feet = .{ 0, 1, 0 }, .yaw = 0.5, .pitch = -0.1, .mode = .walk }, .props = &props, .collected = &collected, .machines = &machines, .prefabs = &.{} };
    const bytes = try encode(allocator, doc);
    defer allocator.free(bytes);
    const back = try decode(allocator, bytes, doc.seed, 4, 8);
    defer back.deinit();
    try std.testing.expectEqualDeep(props[0], back.value.props[0]);
    try std.testing.expectEqualDeep(collected[0], back.value.collected[0]);
    try std.testing.expectEqual(Player.Mode.walk, back.value.player.mode);
    try std.testing.expectEqualSlices(f32, machines[0].states, back.value.machines[0].states);
    try std.testing.expectEqualStrings("lamp", back.value.machines[0].blueprint.devices[0].id);
    try std.testing.expectEqual(@as(u8, 1), back.value.machines[0].yaw);
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes, doc.seed, 4, 2));

    try std.testing.expectError(error.SeedMismatch, decode(allocator, bytes, 1, 4, 8));
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes, doc.seed, 1, 8));
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes[0 .. bytes.len / 2], doc.seed, 4, 8));
    const old = try std.mem.replaceOwned(u8, allocator, bytes, "\"generator\": 2", "\"generator\": 1");
    defer allocator.free(old);
    try std.testing.expectError(error.GeneratorMismatch, decode(allocator, old, doc.seed, 4, 8));
    const future = try std.mem.replaceOwned(u8, allocator, bytes, "\"format\": 5", "\"format\": 4");
    defer allocator.free(future);
    try std.testing.expectError(error.UnsupportedSaveFormat, decode(allocator, future, doc.seed, 4, 8));
}

test "save files are written atomically and read back" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // Exercise the path-based API relative to the test's temporary directory.
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/nested/save.json", .{tmp.sub_path});
    try writeFile(std.testing.io, path, "{\"ok\":true}");
    const bytes = try readFile(std.testing.io, std.testing.allocator, path);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("{\"ok\":true}", bytes);
}
