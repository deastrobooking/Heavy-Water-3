//! GUID → asset resolution. The build writes a manifest from every source's sidecar (GUID, kind,
//! name, output); the catalog binds each entry to what it loaded, and registers engine-generated
//! content under GUIDs derived from fixed names. Saves, scenes, mods, and the network refer to
//! assets by GUID and resolve through here; code keeps using typed handles.
const std = @import("std");
const Guid = @import("Guid.zig");
const Meta = @import("Meta.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Heightmap = @import("../procedural/Heightmap.zig");
const Handle = @import("../engine/Handle.zig");
const Registry = @This();

pub const manifest_format: u32 = 1;
pub const capacity = 96;
pub const name_len = 32;
pub const ManifestEntry = struct { guid: Guid, kind: Meta.Kind, name: []const u8, output: []const u8 };
pub const Manifest = struct { format: u32, assets: []const ManifestEntry };
pub const Error = error{ InvalidManifest, DuplicateGuid, DuplicateName, TooManyAssets, UnknownAsset, WrongKind, Unbound };

pub fn Target(comptime MeshHandle: type) type {
    return union(enum) { unbound, mesh: MeshHandle, blueprint: *const Blueprint, heightmap: *const Heightmap };
}

/// A typed reference: serializes as the GUID string, resolves only to its own kind.
pub fn Ref(comptime kind: Meta.Kind) type {
    return struct {
        guid: Guid,
        pub const asset_kind = kind;
        pub fn jsonStringify(self: @This(), jw: anytype) !void {
            try self.guid.jsonStringify(jw);
        }
        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            return .{ .guid = try Guid.jsonParse(allocator, source, options) };
        }
    };
}

/// A registry over the catalog's mesh handle type.
pub fn For(comptime MeshHandle: type) type {
    return struct {
        const Self = @This();
        pub const Entry = struct { guid: Guid, kind: Meta.Kind, name: [name_len]u8 = @splat(0), name_length: usize = 0, target: Target(MeshHandle) = .unbound };
        entries: [capacity]Entry = undefined,
        count: usize = 0,

        pub fn add(self: *Self, guid: Guid, kind: Meta.Kind, name: []const u8) Error!*Entry {
            if (self.count == capacity) return error.TooManyAssets;
            if (name.len == 0 or name.len > name_len) return error.InvalidManifest;
            for (self.entries[0..self.count]) |*e| {
                if (e.guid.eql(guid)) return error.DuplicateGuid;
                if (e.kind == kind and std.mem.eql(u8, e.name[0..e.name_length], name)) return error.DuplicateName;
            }
            const e = &self.entries[self.count];
            e.* = .{ .guid = guid, .kind = kind, .name_length = name.len };
            @memcpy(e.name[0..name.len], name);
            self.count += 1;
            return e;
        }

        /// Adds every manifest entry, unbound. Nothing is added unless the whole manifest is valid.
        pub fn loadManifest(self: *Self, allocator: std.mem.Allocator, bytes: []const u8) (Error || error{OutOfMemory})!void {
            const parsed = std.json.parseFromSlice(Manifest, allocator, bytes, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidManifest;
            defer parsed.deinit();
            if (parsed.value.format != manifest_format) return error.InvalidManifest;
            var scratch = self.*;
            for (parsed.value.assets) |a| _ = try scratch.add(a.guid, a.kind, a.name);
            self.* = scratch;
        }

        pub fn findByName(self: *Self, kind: Meta.Kind, name: []const u8) ?*Entry {
            for (self.entries[0..self.count]) |*e| if (e.kind == kind and std.mem.eql(u8, e.name[0..e.name_length], name)) return e;
            return null;
        }

        pub fn find(self: *const Self, guid: Guid) ?*const Entry {
            for (self.entries[0..self.count]) |*e| if (e.guid.eql(guid)) return e;
            return null;
        }

        /// Binds a manifest entry (by kind and name) to what was loaded for it.
        pub fn bind(self: *Self, kind: Meta.Kind, name: []const u8, target: Target(MeshHandle)) Error!void {
            const e = self.findByName(kind, name) orelse return error.UnknownAsset;
            e.target = target;
        }

        pub fn mesh(self: *const Self, ref: Ref(.model)) Error!MeshHandle {
            const e = self.find(ref.guid) orelse return error.UnknownAsset;
            if (e.kind != .model) return error.WrongKind;
            return switch (e.target) {
                .mesh => |h| h,
                else => error.Unbound,
            };
        }

        pub fn blueprint(self: *const Self, ref: Ref(.blueprint)) Error!*const Blueprint {
            const e = self.find(ref.guid) orelse return error.UnknownAsset;
            if (e.kind != .blueprint) return error.WrongKind;
            return switch (e.target) {
                .blueprint => |b| b,
                else => error.Unbound,
            };
        }

        pub fn heightmap(self: *const Self, ref: Ref(.heightmap)) Error!*const Heightmap {
            const e = self.find(ref.guid) orelse return error.UnknownAsset;
            if (e.kind != .heightmap) return error.WrongKind;
            return switch (e.target) {
                .heightmap => |map| map,
                else => error.Unbound,
            };
        }

        /// Every entry is bound to loaded content (checked after catalog load).
        pub fn complete(self: *const Self) bool {
            for (self.entries[0..self.count]) |e| if (e.target == .unbound) return false;
            return true;
        }
    };
}

test "manifests load atomically, refuse duplicates, and resolve typed references by kind" {
    const H = Handle.Handle(struct {});
    var r: For(H) = .{};
    const crate = try Guid.parse("11111111111111111111111111111111");
    const door = try Guid.parse("22222222222222222222222222222222");
    const valley = try Guid.parse("33333333333333333333333333333333");
    const good =
        \\{"format":1,"assets":[{"guid":"11111111111111111111111111111111","kind":"model","name":"crate","output":"crate.hwmesh"},
        \\ {"guid":"22222222222222222222222222222222","kind":"blueprint","name":"powered_door","output":"blueprints/powered_door.json"},
        \\ {"guid":"33333333333333333333333333333333","kind":"heightmap","name":"valley","output":"valley.hwmh"}]}
    ;
    try r.loadManifest(std.testing.allocator, good);
    try std.testing.expectEqual(@as(usize, 3), r.count);
    try std.testing.expectError(error.Unbound, r.mesh(.{ .guid = crate }));
    try std.testing.expectError(error.Unbound, r.heightmap(.{ .guid = valley }));
    try r.bind(.model, "crate", .{ .mesh = .{ .index = 3, .generation = 1 } });
    var map_samples = [_]u16{ 0, 0, 0, 0 };
    const map: Heightmap = .{ .width = 2, .height = 2, .settings = .{}, .samples = &map_samples };
    try r.bind(.heightmap, "valley", .{ .heightmap = &map });
    try std.testing.expectEqual(@as(u16, 3), (try r.mesh(.{ .guid = crate })).index);
    try std.testing.expect(r.heightmap(.{ .guid = valley }) catch unreachable == &map);
    try std.testing.expectError(error.WrongKind, r.mesh(.{ .guid = door }));
    try std.testing.expectError(error.WrongKind, r.blueprint(.{ .guid = valley }));
    try std.testing.expectError(error.UnknownAsset, r.blueprint(.{ .guid = try Guid.parse("55555555555555555555555555555555") }));
    try std.testing.expect(!r.complete());
    // A manifest that repeats a GUID is rejected whole, leaving the registry unchanged.
    const dup =
        \\{"format":1,"assets":[{"guid":"44444444444444444444444444444444","kind":"model","name":"a","output":"a"},
        \\ {"guid":"11111111111111111111111111111111","kind":"model","name":"b","output":"b"}]}
    ;
    try std.testing.expectError(error.DuplicateGuid, r.loadManifest(std.testing.allocator, dup));
    try std.testing.expectEqual(@as(usize, 3), r.count);
    // References serialize as their GUID string.
    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, struct { model: Ref(.model) }{ .model = .{ .guid = crate } }, .{});
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings("{\"model\":\"11111111111111111111111111111111\"}", json);
}
