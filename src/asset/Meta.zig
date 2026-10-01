//! `.meta` sidecars: one next to every source asset, holding its GUID, the hash of the source it
//! was imported from, the importer and its version, and typed import settings. The build
//! refuses a source whose sidecar is missing or stale, so identity and import settings are
//! always deliberate and versioned with the asset.
const std = @import("std");
const Guid = @import("Guid.zig");
const Meta = @This();

pub const format_version: u32 = 1;
pub const Kind = enum { model, blueprint, scene, animation, texture };
/// Current importer versions; raising one makes every asset of that kind stale.
pub const importers = struct {
    pub const gltf: u32 = 1;
    pub const blueprint: u32 = 1;
};
pub const ModelSettings = struct {
    /// Uniform scale applied to positions at import.
    scale: f32 = 1,
};
pub const Importer = struct { name: []const u8, version: u32 };
pub const Doc = struct {
    format: u32,
    guid: Guid,
    kind: Kind,
    source_hash: []const u8,
    importer: Importer,
    settings: std.json.Value = .null,
};
pub const Error = error{ InvalidMeta, UnsupportedMetaFormat, WrongKind, StaleMeta, OldImporter, InvalidSettings, UnknownSourceType };

guid: Guid,
kind: Kind,
model: ModelSettings = .{},

/// "blake3:" + 64 hex characters of the source bytes.
pub fn hashSource(source: []const u8) [71]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(source, &digest, .{});
    var out: [71]u8 = undefined;
    @memcpy(out[0..7], "blake3:");
    _ = std.fmt.bufPrint(out[7..], "{x}", .{&digest}) catch unreachable;
    return out;
}

/// The kind a source path imports as (blueprints are JSON documents).
pub fn kindOf(path: []const u8) Error!Kind {
    if (std.mem.endsWith(u8, path, ".gltf") or std.mem.endsWith(u8, path, ".glb")) return .model;
    if (std.mem.endsWith(u8, path, ".json")) return .blueprint;
    return error.UnknownSourceType;
}

fn importerFor(kind: Kind) Importer {
    return switch (kind) {
        .model => .{ .name = "gltf", .version = importers.gltf },
        .blueprint => .{ .name = "blueprint", .version = importers.blueprint },
        else => .{ .name = "none", .version = 0 },
    };
}

/// Parses and checks a sidecar against its source: format, kind, importer, settings, and that
/// the source has not changed since import.
pub fn check(allocator: std.mem.Allocator, meta_bytes: []const u8, source_path: []const u8, source: []const u8) (Error || error{OutOfMemory})!Meta {
    const parsed = std.json.parseFromSlice(Doc, allocator, meta_bytes, .{}) catch return error.InvalidMeta;
    defer parsed.deinit();
    const doc = parsed.value;
    if (doc.format != format_version) return error.UnsupportedMetaFormat;
    const kind = try kindOf(source_path);
    if (doc.kind != kind) return error.WrongKind;
    const importer = importerFor(kind);
    if (!std.mem.eql(u8, doc.importer.name, importer.name)) return error.WrongKind;
    if (doc.importer.version != importer.version) return error.OldImporter;
    if (!std.mem.eql(u8, doc.source_hash, &hashSource(source))) return error.StaleMeta;
    var meta: Meta = .{ .guid = doc.guid, .kind = kind };
    switch (kind) {
        .model => {
            if (doc.settings != .null) {
                const s = std.json.parseFromValue(ModelSettings, allocator, doc.settings, .{}) catch return error.InvalidSettings;
                defer s.deinit();
                if (!std.math.isFinite(s.value.scale) or s.value.scale <= 0 or s.value.scale > 1000) return error.InvalidSettings;
                meta.model = s.value;
            }
        },
        else => if (doc.settings != .null and !(doc.settings == .object and doc.settings.object.count() == 0)) return error.InvalidSettings,
    }
    return meta;
}

/// The sidecar for `source` after `zig build import`: the existing GUID and settings are kept
/// (a new GUID only when there is no sidecar), the hash and importer version are refreshed.
pub fn refresh(allocator: std.mem.Allocator, existing: ?[]const u8, source_path: []const u8, source: []const u8, fresh: Guid) ![]u8 {
    const kind = try kindOf(source_path);
    var guid = fresh;
    var model: ModelSettings = .{};
    if (existing) |bytes| {
        const parsed = std.json.parseFromSlice(Doc, allocator, bytes, .{}) catch return error.InvalidMeta;
        defer parsed.deinit();
        guid = parsed.value.guid;
        if (kind == .model and parsed.value.settings != .null) {
            const s = std.json.parseFromValue(ModelSettings, allocator, parsed.value.settings, .{}) catch return error.InvalidSettings;
            defer s.deinit();
            model = s.value;
        }
    }
    const hash = hashSource(source);
    const Out = struct { format: u32, guid: Guid, kind: Kind, source_hash: []const u8, importer: Importer, settings: ?ModelSettings };
    return std.json.Stringify.valueAlloc(allocator, Out{ .format = format_version, .guid = guid, .kind = kind, .source_hash = &hash, .importer = importerFor(kind), .settings = if (kind == .model) model else null }, .{ .whitespace = .indent_2, .emit_null_optional_fields = false });
}

test "sidecars keep identity and settings, detect stale sources, and reject bad settings" {
    const a = std.testing.allocator;
    const g = Guid.generate(std.testing.io);
    const first = try refresh(a, null, "crate.gltf", "v1", g);
    defer a.free(first);
    const m = try check(a, first, "crate.gltf", "v1");
    try std.testing.expect(m.guid.eql(g) and m.kind == .model and m.model.scale == 1);
    // A changed source is stale until re-imported; re-import keeps the GUID.
    try std.testing.expectError(error.StaleMeta, check(a, first, "crate.gltf", "v2"));
    const second = try refresh(a, first, "crate.gltf", "v2", Guid.generate(std.testing.io));
    defer a.free(second);
    try std.testing.expect((try check(a, second, "crate.gltf", "v2")).guid.eql(g));
    // Settings survive re-import; invalid or unknown settings are rejected.
    const scaled = try std.mem.replaceOwned(u8, a, second, "\"scale\": 1", "\"scale\": 2.5");
    defer a.free(scaled);
    try std.testing.expectEqual(@as(f32, 2.5), (try check(a, scaled, "crate.gltf", "v2")).model.scale);
    const kept = try refresh(a, scaled, "crate.gltf", "v3", Guid.generate(std.testing.io));
    defer a.free(kept);
    try std.testing.expectEqual(@as(f32, 2.5), (try check(a, kept, "crate.gltf", "v3")).model.scale);
    for ([_][]const u8{ "\"scale\": -1", "\"scale\": 1, \"spin\": 2" }) |bad| {
        const text = try std.mem.replaceOwned(u8, a, second, "\"scale\": 1", bad);
        defer a.free(text);
        try std.testing.expectError(error.InvalidSettings, check(a, text, "crate.gltf", "v2"));
    }
    // Kind follows the source type, and old importers are stale.
    try std.testing.expectError(error.WrongKind, check(a, first, "door.json", "v1"));
    const old = try std.mem.replaceOwned(u8, a, first, "\"version\": 1", "\"version\": 0");
    defer a.free(old);
    try std.testing.expectError(error.OldImporter, check(a, old, "crate.gltf", "v1"));
    try std.testing.expectError(error.UnknownSourceType, kindOf("notes.txt"));
}
