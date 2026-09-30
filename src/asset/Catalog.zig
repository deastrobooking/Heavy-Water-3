const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Mesh = @import("../render/Mesh.zig");
const Model = @import("Model.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Catalog = @This();

pub const mesh_capacity = 16;
pub const material_capacity = 64;
const MeshTag = struct {};
const MaterialTag = struct {};
pub const MeshHandle = Handle.Handle(MeshTag);
pub const MaterialHandle = Handle.Handle(MaterialTag);
/// Bumped whenever shipped content changes meaning (IDs, dimensions); persisted in saves.
pub const content_version: u32 = 3;
pub const max_blueprints = 8;

pub const Entry = struct {
    model: Model,
    /// Material handle for each submesh, in submesh order.
    materials: [Model.max_submeshes]MaterialHandle = @splat(.none),
};
/// Named content the game refers to. Handles stay valid for the catalog's lifetime.
pub const Content = struct {
    relic: MeshHandle,
    plant: MeshHandle,
    crate: MeshHandle,
    /// Centered unit cube; machine parts and device bodies scale it per axis.
    block: MeshHandle,
    /// Unit cylinder along X for wheels.
    wheel: MeshHandle,
    /// The hand-authored test Arbor (phase 6), relative to its trunk-base origin.
    test_arbor: MeshHandle,
    /// Coarse distance proxy for the test Arbor; see `World.Prop.effectiveMesh`.
    test_arbor_lod: MeshHandle,
    powered_door: *const Blueprint,
    elevator: *const Blueprint,
    rover: *const Blueprint,
};

meshes: Handle.Pool(MeshTag, Entry, mesh_capacity) = .{},
materials: Handle.Pool(MaterialTag, Model.Material, material_capacity) = .{},
content: Content = undefined,
blueprints: [max_blueprints]Blueprint = undefined,
blueprint_count: usize = 0,

/// Built-in procedural meshes plus compiled runtime models. Immutable after load, so the
/// application and render threads may read it concurrently.
pub fn load(self: *Catalog, allocator: std.mem.Allocator) !void {
    self.* = .{};
    errdefer self.deinit(allocator);
    self.content.relic = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.cube(allocator), .named("relic", .{ 1, 1, 1, 1 })));
    self.content.plant = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.vegetation(allocator), .named("plant", .{ 1, 1, 1, 1 })));
    self.content.crate = try self.register(allocator, try Model.decode(allocator, @embedFile("crate.hwmesh")));
    self.content.block = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.block(allocator), .named("block", .{ 1, 1, 1, 1 })));
    self.content.test_arbor = try self.register(allocator, try Model.fromMesh(allocator, try @import("../procedural/TestArbor.zig").renderMesh(allocator), .named("test arbor", .{ 1, 1, 1, 1 })));
    self.content.test_arbor_lod = try self.register(allocator, try Model.fromMesh(allocator, try @import("../procedural/TestArbor.zig").lodMesh(allocator), .named("test arbor lod", .{ 1, 1, 1, 1 })));
    self.content.wheel = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.wheel(allocator), .named("tire", .{ 0.16, 0.16, 0.17, 1 })));
    // Blueprints were validated at build time; parsing again guards against a stale build.
    self.content.powered_door = try self.addBlueprint(allocator, @embedFile("powered_door.blueprint"));
    self.content.elevator = try self.addBlueprint(allocator, @embedFile("elevator.blueprint"));
    self.content.rover = try self.addBlueprint(allocator, @embedFile("rover.blueprint"));
}

fn addBlueprint(self: *Catalog, allocator: std.mem.Allocator, json: []const u8) !*const Blueprint {
    if (self.blueprint_count == max_blueprints) return error.TooManyBlueprints;
    self.blueprints[self.blueprint_count] = try Blueprint.parse(allocator, json);
    self.blueprint_count += 1;
    return &self.blueprints[self.blueprint_count - 1];
}

pub fn findBlueprint(self: *const Catalog, name: []const u8) ?*const Blueprint {
    for (self.blueprints[0..self.blueprint_count]) |*bp| if (std.mem.eql(u8, bp.name(), name)) return bp;
    return null;
}

/// Takes ownership of `model`, including on failure.
pub fn register(self: *Catalog, allocator: std.mem.Allocator, model: Model) !MeshHandle {
    var entry: Entry = .{ .model = model };
    errdefer {
        for (entry.materials[0..model.submeshes.len]) |m| _ = self.materials.remove(m);
        model.deinit(allocator);
    }
    for (model.submeshes, 0..) |submesh, i| entry.materials[i] = try self.materials.add(model.materials[submesh.material]);
    return self.meshes.add(entry);
}

pub fn mesh(self: *const Catalog, handle: MeshHandle) ?*const Entry {
    return self.meshes.getConst(handle);
}

pub fn material(self: *const Catalog, handle: MaterialHandle) ?*const Model.Material {
    return self.materials.getConst(handle);
}

pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
    var live = self.meshes.live.iterator(.{});
    while (live.next()) |i| self.meshes.items[i].model.deinit(allocator);
    self.* = .{};
}

test "catalog loads the compiled crate and resolves typed handles" {
    var catalog: Catalog = undefined;
    try catalog.load(std.testing.allocator);
    defer catalog.deinit(std.testing.allocator);
    const crate = catalog.mesh(catalog.content.crate).?;
    try std.testing.expectEqual(@as(usize, 2), crate.model.submeshes.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), crate.model.halfExtents()[1], 0.0001);
    const band = catalog.material(crate.materials[1]).?;
    try std.testing.expectEqualStrings("band", std.mem.sliceTo(&band.name, 0));
    try std.testing.expect(catalog.mesh(.none) == null);
    try std.testing.expectEqualStrings("elevator", catalog.content.elevator.name());
    try std.testing.expectEqual(@as(usize, 4), catalog.content.rover.vehicle.?.wheel_count);
    try std.testing.expect(catalog.findBlueprint("powered_door") == catalog.content.powered_door);
}

fn loadProbe(allocator: std.mem.Allocator) !void {
    var catalog: Catalog = undefined;
    try catalog.load(allocator);
    catalog.deinit(allocator);
}

test "catalog load cleans up on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, loadProbe, .{});
}
