const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Mesh = @import("../render/Mesh.zig");
const Model = @import("Model.zig");
const Designs = @import("../vehicle/Designs.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Catalog = @This();
const Arbor = @import("../procedural/Arbor.zig");
const Seed = @import("../procedural/Seed.zig");
const District = @import("../procedural/District.zig");
const Guid = @import("Guid.zig");
pub const Registry = @import("Registry.zig").For(MeshHandle);
pub const Ref = @import("Registry.zig").Ref;
pub const arbor_count = 2;
pub const ArborAsset = struct { tree: Arbor.Tree, mesh: MeshHandle, lod: MeshHandle };

pub const mesh_capacity = 128;
pub const material_capacity = 256;
const MeshTag = struct {};
const MaterialTag = struct {};
pub const MeshHandle = Handle.Handle(MeshTag);
pub const MaterialHandle = Handle.Handle(MaterialTag);
/// Bumped whenever shipped content changes meaning (IDs, dimensions); persisted in saves.
/// v6 adds the market blueprints (proximity gate, street lamp, signal relay); v7 the Rootdeep
/// shrines and their Rootsong reward blueprints.
pub const content_version: u32 = 7;
pub const max_blueprints = 12;

pub const Entry = struct {
    /// False while a deferred mesh is still being built or loaded; the handle is valid but
    /// draws nothing until `install`.
    ready: bool = true,
    model: Model,
    /// Material handle for each submesh, in submesh order.
    materials: [Model.max_submeshes]MaterialHandle = @splat(.none),
};
/// Named content the game refers to. Model reload rebinds these handles; cached copies expire.
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
    sap_beacon: *const Blueprint,
    /// Sold at district markets, in `Market.Ware` order.
    wares: [3]*const Blueprint,
    /// Shrine rewards, by shrine index.
    rewards: [2]*const Blueprint,
    district: MeshHandle,
    /// Hover car designs (see `vehicle/Designs.zig`), in `Design` order.
    cars: [Designs.count]CarAsset,
    /// Hive units and nests (dark shell + emissive glow), and the pickup gem.
    drone: MeshHandle,
    drone_glow: MeshHandle,
    sentinel: MeshHandle,
    sentinel_glow: MeshHandle,
    spire: MeshHandle,
    spire_glow: MeshHandle,
    gem: MeshHandle,
};
/// One hover car design: its body, a rotor drawn spinning at each pivot, emissive light strips,
/// and the mass properties the simulation flies it with.
pub const CarAsset = struct {
    body: MeshHandle,
    rotor: MeshHandle,
    lights: MeshHandle,
    physical: Designs.Physical,
};

meshes: Handle.Pool(MeshTag, Entry, mesh_capacity) = .{},
materials: Handle.Pool(MaterialTag, Model.Material, material_capacity) = .{},
content: Content = undefined,
blueprints: [max_blueprints]Blueprint = undefined,
blueprint_count: usize = 0,
arbors: [arbor_count]ArborAsset = undefined,
district: District.Layout = undefined,
/// Meshes reserved by `loadSeededDeferred`, to be built by the asset loader and installed.
pending: [arbor_count * 2 + 1]Pending = undefined,
pending_count: usize = 0,
/// GUID → content for everything above: the build manifest's compiled assets plus
/// engine-generated meshes under GUIDs derived from "generated:<name>".
registry: Registry = .{},

/// Built-in procedural meshes plus compiled runtime models. Immutable after load, so the
/// application and render threads may read it concurrently.
pub fn load(self: *Catalog, allocator: std.mem.Allocator) !void {
    return self.loadSeeded(allocator, 0x4845415659);
}

pub const Pending = struct { handle: MeshHandle, generator: @import("Loader.zig").Generator };

/// Loads everything now (tests and tools).
pub fn loadSeeded(self: *Catalog, allocator: std.mem.Allocator, seed: u64) !void {
    try self.loadSeededDeferred(allocator, seed);
    errdefer self.deinit(allocator);
    for (self.pending[0..self.pending_count]) |p| try self.install(allocator, p.handle, try p.generator.build(p.generator.context, allocator));
    self.pending_count = 0;
}

const Build = struct {
    fn arborFull(context: *const anyopaque, allocator: std.mem.Allocator) anyerror!Model {
        const tree: *const Arbor.Tree = @ptrCast(@alignCast(context));
        return Model.fromMesh(allocator, try Arbor.mesh(allocator, tree, .full), .named("arbor", .{ 1, 1, 1, 1 }));
    }
    fn arborProxy(context: *const anyopaque, allocator: std.mem.Allocator) anyerror!Model {
        const tree: *const Arbor.Tree = @ptrCast(@alignCast(context));
        return Model.fromMesh(allocator, try Arbor.mesh(allocator, tree, .proxy), .named("arbor proxy", .{ 1, 1, 1, 1 }));
    }
    fn district(context: *const anyopaque, allocator: std.mem.Allocator) anyerror!Model {
        const layout: *const District.Layout = @ptrCast(@alignCast(context));
        const city = try District.geometry(layout);
        return Model.fromMesh(allocator, try District.mesh(allocator, city.slice(), false), .named("canopy district", .{ 1, 1, 1, 1 }));
    }
};

/// Builds a hover car design (a few milliseconds) and registers its three meshes.
fn registerCar(self: *Catalog, allocator: std.mem.Allocator, design: Designs.Design) !CarAsset {
    const car = @import("../vehicle/car.zig");
    var parts = try car.build(allocator, Designs.spec(design));
    defer parts.deinit(allocator);
    const p = Designs.palette(design);
    const white: [4]f32 = .{ 1, 1, 1, 1 };
    return .{
        .body = try self.register(allocator, try Model.fromMesh(allocator, try Designs.renderMesh(allocator, &parts.body, p), .named(Designs.name(design), white))),
        .rotor = try self.register(allocator, try Model.fromMesh(allocator, try Designs.renderMesh(allocator, &parts.rotor, p), .named("rotor", white))),
        .lights = try self.register(allocator, try Model.fromMesh(allocator, try Designs.renderMesh(allocator, &parts.lights, p), .named("car lights", white))),
        .physical = .{ .mass = parts.mass, .pivots = parts.pivots },
    };
}

/// Takes a handle for content that will be installed later.
pub fn reserve(self: *Catalog) !MeshHandle {
    return self.meshes.add(.{ .ready = false, .model = .{ .mesh = .{ .vertices = &.{}, .indices = &.{} }, .submeshes = &.{}, .materials = &.{}, .bounds_min = @splat(0), .bounds_max = @splat(0) } });
}

/// Fills a reserved handle (takes ownership of `model`). Call only where no other thread reads
/// the catalog: the application installs inside the render mutex, between frames.
pub fn install(self: *Catalog, allocator: std.mem.Allocator, handle: MeshHandle, model: Model) !void {
    errdefer model.deinit(allocator);
    const entry = self.meshes.get(handle) orelse return error.UnknownHandle;
    if (entry.ready) return error.AlreadyInstalled;
    var materials: [Model.max_submeshes]MaterialHandle = @splat(.none);
    var added: usize = 0;
    errdefer for (materials[0..added]) |m| {
        _ = self.materials.remove(m);
    };
    for (model.submeshes, 0..) |submesh, i| {
        materials[i] = try self.materials.add(model.materials[submesh.material]);
        added += 1;
    }
    entry.* = .{ .ready = true, .model = model, .materials = materials };
}

/// Loads everything the simulation needs now, and reserves handles for the big procedural render
/// meshes (the generated Arbors and the district) for the asset loader to build in the
/// background; see `pending`.
pub fn loadSeededDeferred(self: *Catalog, allocator: std.mem.Allocator, seed: u64) !void {
    self.* = .{};
    errdefer self.deinit(allocator);
    self.content.relic = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.cube(allocator), .named("relic", .{ 1, 1, 1, 1 })));
    self.content.plant = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.vegetation(allocator), .named("plant", .{ 1, 1, 1, 1 })));
    self.content.crate = try self.register(allocator, try Model.decode(allocator, @embedFile("crate.hwmesh")));
    self.content.block = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.block(allocator), .named("block", .{ 1, 1, 1, 1 })));
    self.content.test_arbor = try self.register(allocator, try Model.fromMesh(allocator, try @import("../procedural/TestArbor.zig").renderMesh(allocator), .named("test arbor", .{ 1, 1, 1, 1 })));
    self.content.test_arbor_lod = try self.register(allocator, try Model.fromMesh(allocator, try @import("../procedural/TestArbor.zig").lodMesh(allocator), .named("test arbor lod", .{ 1, 1, 1, 1 })));
    self.content.wheel = try self.register(allocator, try Model.fromMesh(allocator, try Mesh.wheel(allocator), .named("tire", .{ 0.16, 0.16, 0.17, 1 })));
    for (&self.arbors, 0..) |*asset, i| {
        const genome: Arbor.Genome = if (i == 0)
            .{ .height = 420, .apical_dominance = 0.8, .vascular_capacity = 150, .lumen = .{ 0.15, 0.85, 0.7 } }
        else
            .{ .height = 340, .apical_dominance = 0.1, .gravitropism = 0.55, .platform_tendency = 0.9, .vascular_capacity = 300, .bark = .{ 0.42, 0.28, 0.18 }, .lumen = .{ 1, 0.65, 0.15 } };
        asset.tree = try Arbor.grow(Seed.mix(seed ^ (0x4152424f52 + @as(u64, @intCast(i)))), genome);
        asset.mesh = try self.reserve();
        self.pending[self.pending_count] = .{ .handle = asset.mesh, .generator = .{ .context = &asset.tree, .build = Build.arborFull } };
        asset.lod = try self.reserve();
        self.pending[self.pending_count + 1] = .{ .handle = asset.lod, .generator = .{ .context = &asset.tree, .build = Build.arborProxy } };
        self.pending_count += 2;
    }
    for (&self.content.cars, 0..) |*asset, i| asset.* = try self.registerCar(allocator, @enumFromInt(i));
    {
        const H = @import("../vehicle/HiveMeshes.zig");
        const white: [4]f32 = .{ 1, 1, 1, 1 };
        inline for (.{ .{ "drone", H.drone }, .{ "sentinel", H.sentinel }, .{ "spire", H.spire } }) |entry| {
            const pair = try entry[1](allocator);
            // The glow mesh is ours until its model takes it.
            var glow_owned = true;
            errdefer if (glow_owned) pair.glow.deinit(allocator);
            @field(self.content, entry[0]) = try self.register(allocator, try Model.fromMesh(allocator, pair.shell, .named(entry[0], white)));
            glow_owned = false;
            @field(self.content, entry[0] ++ "_glow") = try self.register(allocator, try Model.fromMesh(allocator, pair.glow, .named(entry[0] ++ " glow", white)));
        }
        self.content.gem = try self.register(allocator, try Model.fromMesh(allocator, try H.gem(allocator), .named("gem", white)));
    }
    self.district = try District.generate(seed);
    self.content.district = try self.reserve();
    self.pending[self.pending_count] = .{ .handle = self.content.district, .generator = .{ .context = &self.district, .build = Build.district } };
    self.pending_count += 1;
    // Generated meshes have no sidecar: their GUIDs derive from fixed names.
    const generated = [_]struct { name: []const u8, handle: MeshHandle }{
        .{ .name = "relic", .handle = self.content.relic },           .{ .name = "plant", .handle = self.content.plant },
        .{ .name = "block", .handle = self.content.block },           .{ .name = "wheel", .handle = self.content.wheel },
        .{ .name = "test_arbor", .handle = self.content.test_arbor }, .{ .name = "test_arbor_lod", .handle = self.content.test_arbor_lod },
        .{ .name = "district", .handle = self.content.district },     .{ .name = "arbor_1", .handle = self.arbors[0].mesh },
        .{ .name = "arbor_1_lod", .handle = self.arbors[0].lod },     .{ .name = "arbor_2", .handle = self.arbors[1].mesh },
        .{ .name = "arbor_2_lod", .handle = self.arbors[1].lod },
    };
    for (generated) |g| {
        var full: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&full, "generated:{s}", .{g.name}) catch unreachable;
        (try self.registry.add(Guid.derived(key), .model, g.name)).target = .{ .mesh = g.handle };
    }
    try self.registry.loadManifest(allocator, @embedFile("assets.manifest"));
    try self.registry.bind(.model, "crate", .{ .mesh = self.content.crate });
    // Blueprints were validated at build time; parsing again guards against a stale build.
    self.content.powered_door = try self.addBlueprint(allocator, @embedFile("powered_door.blueprint"));
    self.content.elevator = try self.addBlueprint(allocator, @embedFile("elevator.blueprint"));
    self.content.rover = try self.addBlueprint(allocator, @embedFile("rover.blueprint"));
    self.content.sap_beacon = try self.addBlueprint(allocator, @embedFile("sap_beacon.blueprint"));
    self.content.wares = .{
        try self.addBlueprint(allocator, @embedFile("proximity_gate.blueprint")),
        try self.addBlueprint(allocator, @embedFile("street_lamp.blueprint")),
        try self.addBlueprint(allocator, @embedFile("signal_relay.blueprint")),
    };
    self.content.rewards = .{
        try self.addBlueprint(allocator, @embedFile("rootsong_hearth.blueprint")),
        try self.addBlueprint(allocator, @embedFile("rootsong_call.blueprint")),
    };
    for (self.blueprints[0..self.blueprint_count]) |*bp| try self.registry.bind(.blueprint, bp.name(), .{ .blueprint = bp });
    if (!self.registry.complete()) return error.UnboundAsset;
}

/// The GUID of a named asset (built-in content), for code that writes references.
pub fn guidOf(self: *Catalog, kind: @import("Meta.zig").Kind, name: []const u8) ?Guid {
    return if (self.registry.findByName(kind, name)) |e| e.guid else null;
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
    while (live.next()) |i| if (self.meshes.items[i].ready) self.meshes.items[i].model.deinit(allocator);
    self.* = .{};
}

test "every catalog asset resolves by GUID: compiled through the manifest, generated by name" {
    var catalog: Catalog = undefined;
    try catalog.load(std.testing.allocator);
    defer catalog.deinit(std.testing.allocator);
    try std.testing.expect(catalog.registry.complete());
    const crate = catalog.guidOf(.model, "crate").?;
    try std.testing.expect((try catalog.registry.mesh(.{ .guid = crate })).eql(catalog.content.crate));
    const door = catalog.guidOf(.blueprint, "powered_door").?;
    try std.testing.expectEqual(catalog.content.powered_door, try catalog.registry.blueprint(.{ .guid = door }));
    try std.testing.expectError(error.WrongKind, catalog.registry.mesh(.{ .guid = door }));
    // Generated content has the same GUID in every build.
    try std.testing.expect((try catalog.registry.mesh(.{ .guid = Guid.derived("generated:block") })).eql(catalog.content.block));
    // Every shipped blueprint is reachable by GUID.
    for (catalog.blueprints[0..catalog.blueprint_count]) |*bp| {
        try std.testing.expectEqual(@as(*const Blueprint, bp), try catalog.registry.blueprint(.{ .guid = catalog.guidOf(.blueprint, bp.name()).? }));
    }
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

test "deferred meshes reserve handles at load and install once, later" {
    var catalog: Catalog = undefined;
    try catalog.loadSeededDeferred(std.testing.allocator, 42);
    defer catalog.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 5), catalog.pending_count);
    // Reserved handles are valid but not ready: renderers draw nothing for them yet.
    const district = catalog.mesh(catalog.content.district).?;
    try std.testing.expect(!district.ready);
    for (catalog.pending[0..catalog.pending_count]) |p| {
        try catalog.install(std.testing.allocator, p.handle, try p.generator.build(p.generator.context, std.testing.allocator));
    }
    try std.testing.expect(catalog.mesh(catalog.content.district).?.ready);
    try std.testing.expect(catalog.mesh(catalog.content.district).?.model.mesh.vertices.len > 1000);
    try std.testing.expect(catalog.material(catalog.mesh(catalog.arbors[0].mesh).?.materials[0]) != null);
    // A second install, or one into an unknown handle, is refused (and frees the model).
    const extra = try Model.fromMesh(std.testing.allocator, try Mesh.block(std.testing.allocator), .named("x", .{ 1, 1, 1, 1 }));
    try std.testing.expectError(error.AlreadyInstalled, catalog.install(std.testing.allocator, catalog.content.district, extra));
    const other = try Model.fromMesh(std.testing.allocator, try Mesh.block(std.testing.allocator), .named("y", .{ 1, 1, 1, 1 }));
    try std.testing.expectError(error.UnknownHandle, catalog.install(std.testing.allocator, .{ .index = 120, .generation = 9 }, other));
}

/// Atomically replaces a model by GUID, consuming `model` even on failure. All allocation
/// and material-capacity checks finish before the old entry is touched. Call under the
/// render mutex; the renderer detects the new generation and uploads under its budget.
pub fn replaceModel(self: *Catalog, allocator: std.mem.Allocator, guid: Guid, model: Model) !MeshHandle {
    errdefer model.deinit(allocator);
    const old = try self.registry.mesh(.{ .guid = guid });
    const entry = self.meshes.get(old) orelse return error.UnknownHandle;
    if (!entry.ready) return error.AssetNotReady;
    if (old.eql(self.content.crate)) for (model.halfExtents()) |half| {
        if (!std.math.isFinite(half) or half <= 0) return error.InvalidColliderBounds;
    };
    if (old.generation == std.math.maxInt(u16)) return error.GenerationExhausted;
    var staged = self.materials;
    for (entry.materials[0..entry.model.submeshes.len]) |m| _ = staged.remove(m);
    var materials: [Model.max_submeshes]MaterialHandle = @splat(.none);
    for (model.submeshes, 0..) |submesh, i| materials[i] = try staged.add(model.materials[submesh.material]);
    const retired = entry.model;
    const next: MeshHandle = .{ .index = old.index, .generation = old.generation + 1 };
    self.materials = staged;
    entry.* = .{ .model = model, .materials = materials };
    self.meshes.generations[old.index] = next.generation;
    for (self.registry.entries[0..self.registry.count]) |*e| if (e.target == .mesh and e.target.mesh.eql(old)) {
        e.target = .{ .mesh = next };
    };
    inline for (std.meta.fields(Content)) |field| {
        if (field.type == MeshHandle) {
            const handle = &@field(self.content, field.name);
            if (handle.eql(old)) handle.* = next;
        }
    }
    for (&self.arbors) |*arbor| {
        if (arbor.mesh.eql(old)) arbor.mesh = next;
        if (arbor.lod.eql(old)) arbor.lod = next;
    }
    retired.deinit(allocator);
    return next;
}

test "model reload bumps generation and rebinds GUID and content without consuming pool slots" {
    const a = std.testing.allocator;
    var catalog: Catalog = undefined;
    try catalog.load(a);
    defer catalog.deinit(a);
    const guid = catalog.guidOf(.model, "crate").?;
    const old = catalog.content.crate;
    const count = catalog.meshes.count();
    const material_count = catalog.materials.count();
    for (0..10) |_| {
        const model = try Model.decode(a, @embedFile("crate.hwmesh"));
        const next = try catalog.replaceModel(a, guid, model);
        try std.testing.expectEqual(old.index, next.index);
        try std.testing.expectEqual(count, catalog.meshes.count());
        try std.testing.expectEqual(material_count, catalog.materials.count());
    }
    try std.testing.expect(catalog.mesh(old) == null);
    try std.testing.expect((try catalog.registry.mesh(.{ .guid = guid })).eql(catalog.content.crate));
    const before = catalog.content.crate;
    const wrong = catalog.guidOf(.blueprint, "rover").?;
    try std.testing.expectError(error.WrongKind, catalog.replaceModel(a, wrong, try Model.decode(a, @embedFile("crate.hwmesh"))));
    try std.testing.expectEqual(before, catalog.content.crate);
    catalog.meshes.generations[before.index] = std.math.maxInt(u16);
    for (catalog.registry.entries[0..catalog.registry.count]) |*e| if (e.guid.eql(guid)) {
        e.target.mesh.generation = std.math.maxInt(u16);
    };
    try std.testing.expectError(error.GenerationExhausted, catalog.replaceModel(a, guid, try Model.decode(a, @embedFile("crate.hwmesh"))));
}
