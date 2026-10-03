const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Scatter = @import("../procedural/Scatter.zig");
const Catalog = @import("../asset/Catalog.zig");
const Key = @import("../world/ChunkKey.zig");
const Camera = @import("../world/Camera.zig");
const World = @import("../world/World.zig");
const Modifications = @import("../world/Modifications.zig");
const Input = @import("../engine/Input.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Machine = @import("../machine/Machine.zig");
const Vehicle = @import("../physics/Vehicle.zig");
const R = Physics.Rotation;
const Player = @import("Player.zig");
const Save = @import("Save.zig");
const Build = @import("Build.zig");
const Profile = @import("Profile.zig");
const Avatar = @import("Avatar.zig");
const Creator = @import("Creator.zig");
const TestArbor = @import("../procedural/TestArbor.zig");
const Sandbox = @This();
const Arbor = @import("../procedural/Arbor.zig");
const Sap = @import("../machine/Sap.zig");
const District = @import("../procedural/District.zig");
const Rootsong = @import("../machine/Rootsong.zig");
const Shrine = @import("../procedural/Shrine.zig");
const Seed = @import("../procedural/Seed.zig");
const Host = @import("../script/Host.zig");
const Mod = @import("../mod/Mod.zig");
const Life = @import("../city/Life.zig");
const Market = @import("../city/Market.zig");
const Routes = @import("../city/Routes.zig");
const Sky = @import("../engine/Sky.zig");
const Progress = @import("Progress.zig");
const Dialogue = @import("Dialogue.zig");
const Garage = @import("Garage.zig");
const Collectibles = @import("Collectibles.zig");
const Enemies = @import("Enemies.zig");
const Combat = @import("Combat.zig");
const Fabricator = @import("Fabricator.zig");
const Frontier = @import("Frontier.zig");
const Hangar = @import("Hangar.zig");
const Skies = @import("Skies.zig");
const Rig = @import("Rig.zig");
const Specials = @import("Specials.zig");
/// `closing`: removed from the road graph, standing until the traffic on it has crossed.
pub const PlacedBridge = struct { edge: District.Edge, parts: District.BridgeParts, collider: Physics.MeshCollider, closing: bool = false };
pub const sap_tree_count = 1 + Catalog.arbor_count;
pub const SapLink = struct { tree: u8, node: u16 };

/// The interactive session: a walking player, physical crates, placed machines (a powered
/// door, an elevator, a drivable rover, and a player-built workshop circuit), three tools
/// (hands, build, wire), and versioned saves that describe the whole world.
pub const max_crates = 32;
pub const max_machines = 16;
pub const max_prefabs = 16;
pub const reach: f32 = 6;
pub const hold_distance: f32 = 2.2;
pub const spawn: Physics.Vec3 = .{ 0, 0, -58 };
/// Default world: crate layout relative to the spawn point (a row, plus one stacked).
const crate_offsets = [_]Physics.Vec3{ .{ -2.2, 0, 6 }, .{ 0, 0, 6 }, .{ 2.2, 0, 6 }, .{ 0, 1, 6 }, .{ -1.1, 0, 9 }, .{ 1.1, 0, 9 } };
/// Default world: machine placements relative to the spawn point.
const Placement = struct { blueprint: enum { powered_door, elevator, rover }, offset: [2]f32 };
const placements = [_]Placement{
    .{ .blueprint = .powered_door, .offset = .{ 9, 10 } },
    .{ .blueprint = .elevator, .offset = .{ -10, 8 } },
    .{ .blueprint = .rover, .offset = .{ -6, -3 } },
};
pub const chase_distance: f32 = 7.5;

pub const DeviceRef = struct { machine: u8, device: u8 };
pub const Target = union(enum) {
    none,
    prop: u32,
    relic: struct { ref: Modifications.ObjectRef, position: Physics.Vec3 },
    device: DeviceRef,
    /// A machine's static structure.
    structure: u8,
    bridge: u8,
    /// A market stall, by `Market` stall index.
    stall: u8,
    /// A pedestrian, by `Life` walker index.
    walker: u8,
    /// A parked hover car, by design.
    car: u8,
    /// The fabricator kiosk at the garage.
    fabricator,
    /// The parked Kestrel fighter.
    jet,
};
/// Panels the tinker opens from a conversation: suit upgrades or the armor wardrobe.
/// A sound for the application to play, placed in the world when it has a position.
pub const Cue = struct { sound: @import("../audio/Synth.zig").Sound, position: ?Physics.Vec3 = null, pitch: f32 = 1 };

pub fn cue(self: *Sandbox, sound: @import("../audio/Synth.zig").Sound, position: ?Physics.Vec3) void {
    self.cuePitch(sound, position, 1);
}

pub fn cuePitch(self: *Sandbox, sound: @import("../audio/Synth.zig").Sound, position: ?Physics.Vec3, pitch: f32) void {
    if (self.cue_count == self.cues.len) return;
    self.cues[self.cue_count] = .{ .sound = sound, .position = position, .pitch = pitch };
    self.cue_count += 1;
}

pub const Shop = struct { kind: enum { upgrades, wardrobe, fabricate }, row: u8 = 0, tab: u8 = 0 };
pub const ShopKey = enum { up, down, left, right, confirm, close };
pub const wardrobe_rows = @typeInfo(Profile.Clothing).@"enum".fields.len;
/// Keys the trade panel understands while a stall is open.
pub const TradeKey = enum { up, down, confirm, close };
/// Trade panel rows: sell parts, then one row per ware.
pub const trade_rows: u8 = 1 + Market.ware_count;
pub const Actions = packed struct {
    /// Tool primary: grab/press/enter (hands), place (build), connect (wire).
    interact: bool = false,
    /// Tool secondary: salvage a relic (hands), remove (build), disconnect (wire).
    secondary: bool = false,
    toggle_mode: bool = false,
    reset: bool = false,
    /// Palette item (build) or port pair (wire).
    next_item: bool = false,
    rotate: bool = false,
    /// Capture the aimed machine as a prefab (build or wire tool).
    capture: bool = false,
    /// Step the aimed transmitter or receiver's channel down or up (any tool).
    channel_down: bool = false,
    channel_up: bool = false,
    /// Switch between first- and third-person view.
    toggle_view: bool = false,
    /// Open the character creator.
    open_creator: bool = false,
    /// 0 = unchanged, 1 hands, 2 build, 3 wire, 4 bridges.
    select_tool: u3 = 0,
    /// Climb out of the Kestrel (its primary button fires).
    leave_jet: bool = false,
    /// Class specials 1–3 (Z, C, H).
    special_1: bool = false,
    special_2: bool = false,
    special_3: bool = false,
};
const NearbyChunk = struct { key: Key, count: usize, objects: [Scatter.capacity]Scatter.Object };
/// A machine slot: its own editable blueprint copy, runtime, placement, and bodies.
/// `machine.blueprint` points at `blueprint`, so slots must not be copied while active.
pub const Placed = struct {
    active: bool = false,
    blueprint: Blueprint = .{},
    machine: Machine = undefined,
    yaw: u2 = 0,
    workshop: bool = false,
    devices: [Blueprint.max_devices]Physics.Body = @splat(.none),
    parts: [Blueprint.max_parts]Physics.Body = @splat(.none),
    /// Vehicle blueprints: the chassis rigid body and wheels. Parts and devices ride on it.
    vehicle: ?Vehicle = null,
    /// Placed from a market kit; removing it returns the kit, and it cannot be captured.
    kit: ?Market.Ware = null,
    /// A Rootdeep shrine: protected from removal, capture, rewiring, and building inside.
    shrine: ?u8 = null,
};
pub const shrine_count = 2;
pub const max_mods = Host.max_modules;
pub const ModRef = struct {
    name_buffer: [Mod.name_len]u8 = @splat(0),
    name_length: usize = 0,
    version: Mod.Version,
    pub fn name(self: *const ModRef) []const u8 {
        return self.name_buffer[0..self.name_length];
    }
};
/// A generated Rootdeep shrine: its verified puzzle, where it stands, and its machine slot.
pub const PlacedShrine = struct {
    generated: Shrine.Generated,
    origin: Physics.Vec3,
    machine: ?u8 = null,
    completed: bool = false,
};

// Physics user data: crates are their slot index; machine bodies set the top bit.
const machine_flag: u32 = 1 << 31;
const part_flag: u32 = 1 << 30;
const chassis_flag: u32 = 1 << 29;
/// Arbor geometry: occludes picking, never a removable target.
const world_flag: u32 = 1 << 28;
const bridge_flag: u32 = 1 << 27;
/// Test Arbor placement relative to the spawn point.
pub const arbor_offset: [2]f32 = .{ 60, 80 };

pub const View = enum { first, third };
pub const third_person_distance: f32 = 4;
pub const max_players = 4;
/// A drop-in local co-op player (P2–P4): the full traversal controller, its own camera and
/// view, and hands that press buttons. P1 alone builds, drives, carries, and saves; guests
/// are session-only and are not written to saves.
pub const Guest = struct {
    active: bool = false,
    player: Player = .{},
    camera: Camera = .{},
    view: View = .third,
    profile: Profile = .{},
    body_yaw: f32 = 0,
    walk_phase: f32 = 0,
    walk_amount: f32 = 0,
    target: Target = .none,
    /// Written by the application before each fixed step; edges are consumed by it.
    input: Input = .{},
    interact: bool = false,
    toggle_view: bool = false,
    /// Market stall this guest is trading at (the party shares P1's wallet), and its row.
    trading: ?u8 = null,
    trade_row: u8 = 0,
    /// Trade-panel edges from the pad (D-pad up/down; B closes; X confirms via `interact`).
    trade_up: bool = false,
    trade_down: bool = false,
    /// Right trigger held (fire the party's selected weapon) and a weapon-switch edge (D-pad).
    fire: bool = false,
    /// Right stick click held: the weapon's alternate (saber guard, scope, charge).
    alt: bool = false,
    next_weapon: bool = false,
    /// Class special press edges (D-pad up and down; up with the right stick held is the third).
    special: [3]bool = @splat(false),
};
/// Where guests appear relative to P1's facing: left, right, and behind.
const guest_offsets = [_]Physics.Vec3{ .{ -1.6, 0, -0.6 }, .{ 1.6, 0, -0.6 }, .{ 0, 0, -2 } };

seed: u64,
catalog: *const Catalog,
/// Owns mesh-collider storage; `deinit` frees it.
allocator: std.mem.Allocator,
arbor_origin: ?Physics.Vec3 = null,
district_collider: Physics.MeshCollider = .none,
bridges: [District.max_bridges]?PlacedBridge = @splat(null),
/// Stable tree IDs: 0 is the test Arbor; 1 and 2 are seeded genome Arbors.
generated_origins: [Catalog.arbor_count]Physics.Vec3 = undefined,
generated_colliders: [Catalog.arbor_count]Physics.MeshCollider = @splat(.none),
test_arbor_sap: Arbor.Tree = undefined,
sap_stats: [sap_tree_count]Sap.Result = @splat(.{}),
tap_links: [max_machines][Blueprint.max_devices]?SapLink = @splat(@splat(null)),
arbor_colliders: [5]Physics.MeshCollider = @splat(.none),
profile: Profile = .{},
creator: Creator = .{},
view: View = .first,
/// The body's facing; follows the camera except while the creator is open.
body_yaw: f32 = 0,
walk_phase: f32 = 0,
walk_amount: f32 = 0,
physics: Physics,
player: Player = .{},
guests: [max_players - 1]Guest = @splat(.{}),
/// Class specials: energy, cooldowns, grenades and sentries (session-only, like vitals).
specials: Specials = .{},
/// Each player's skeleton in the simulation (built on first use), for where blades are.
rigs: [max_players]?Rig = @splat(null),
/// Traffic and pedestrians; off until `enableLife` (the application enables it).
life: Life = .{},
/// Bumped whenever the road graph changes, so traffic replans.
road_revision: u64 = 0,
shrines: [shrine_count]PlacedShrine = undefined,
/// Mod scripts for `script` devices, and the installed mods (recorded in saves).
scripts: Host,
mods: [max_mods]ModRef = undefined,
mod_count: usize = 0,
/// Mods the last loaded save used that are missing or at another version.
mod_warnings: usize = 0,
market: Market = .{},
wallet: Market.Wallet = .{},
/// Suit upgrades, owned armor and story flags (saved).
progress: Progress = .{},
/// Conversation data (embedded and validated at init) and the open conversation.
dialogue: Dialogue = undefined,
talk: ?Dialogue.Session = null,
/// Open tinker panel.
shop: ?Shop = null,
/// Hover cars, pickups, the Hive and P1's arsenal (see `Frontier.zig`).
garage: Garage = .{},
/// The Kestrel fighter and the air war (see `Hangar.zig`, `Skies.zig`).
hangar: Hangar = .{},
skies: Skies = .{},
collectibles: Collectibles = .{},
enemies: Enemies = .{},
combat: Combat = .{},
/// Sounds the step produced (shots, hits, pickups), drained by the application each frame.
cues: [32]Cue = undefined,
cue_count: usize = 0,
/// Weapon triggers held this step (primary and alternate), set by the application.
trigger: struct { fire: bool = false, alt: bool = false } = .{},
/// Stall whose trade panel is open (P1 only), and the selected row.
trading: ?u8 = null,
trade_row: u8 = 0,
crates: [max_crates]Physics.Body = @splat(.none),
machines: [max_machines]Placed = @splat(.{}),
/// Slot of the machine that holds loose devices placed from the palette.
workshop: ?u8 = null,
/// Button pressed during the last step; the machines see it on the next step.
press: ?DeviceRef = null,
/// Root group per tree ID (see `machine/Rootsong.zig`), fixed for the resident grove.
root_groups: [sap_tree_count]u8 = undefined,
/// Rootsong buses per root group, written last step and heard this step.
songs: [sap_tree_count]Machine.Bus = @splat(@splat(0)),
/// World signal bus written by transmitters last step, read by receivers this step.
bus: Machine.Bus = @splat(0),
/// Vehicle machine the player is driving.
seated: ?u8 = null,
driver_input: Machine.Controls = .{},
held: ?u32 = null,
target: Target = .none,
modifications: Modifications = .{},
nearby_center: ?Key = null,
nearby: [9]NearbyChunk = undefined,
tick: u64 = 0,
tools: Build.State = .{},
/// Player-captured blueprints, placeable from the build palette after the built-ins.
prefabs: [max_prefabs]Blueprint = undefined,
prefab_count: usize = 0,
/// Prefab captured this step, for the application to export to disk.
exported: ?usize = null,
/// Short status text for the HUD (uppercase-safe), shown until `notice_until`.
notice: [64]u8 = undefined,
notice_len: usize = 0,
notice_until: u64 = 0,

/// Initializes in place: physics keeps a pointer to `seed` for terrain queries.
pub fn init(self: *Sandbox, allocator: std.mem.Allocator, seed: u64, catalog: *const Catalog, camera: *Camera) !void {
    self.* = .{ .seed = seed, .catalog = catalog, .allocator = allocator, .physics = undefined, .scripts = .init(allocator) };
    self.physics = .init(.{ .context = &self.seed, .sample = groundSample });
    errdefer self.physics.deinit();
    self.dialogue = try Dialogue.load(allocator, Dialogue.builtin);
    errdefer self.dialogue.deinit();
    try self.placeArbor(spawn[0] + arbor_offset[0], spawn[2] + arbor_offset[1]);
    self.test_arbor_sap = .{ .seed = seed, .genome = .{ .height = TestArbor.height, .base_radius = TestArbor.base_radius }, .count = 2 };
    self.test_arbor_sap.nodes[0] = .{ .position = .{ 0, -TestArbor.bury, 0 }, .radius = TestArbor.base_radius, .parent = Arbor.none, .depth = 0 };
    self.test_arbor_sap.nodes[1] = .{ .position = .{ 0, TestArbor.height, 0 }, .radius = TestArbor.top_radius, .parent = 0, .depth = 0 };
    const grove = [_][2]f32{ .{ 240, 180 }, .{ -340, 300 } };
    for (grove, &self.generated_origins, &self.generated_colliders, &catalog.arbors) |point, *origin, *collider, *asset| {
        origin.* = .{ point[0], Terrain.surface(seed, point[0], point[1]).height, point[1] };
        collider.* = try Arbor.createCollider(allocator, &self.physics, &asset.tree, origin.*, world_flag);
    }
    var roots: [sap_tree_count]Rootsong.Tree = undefined;
    for (&roots, 0..) |*r, i| r.* = .{ .origin = self.treeOrigin(i), .height = self.tree(i).genome.height };
    self.root_groups = Rootsong.groups(sap_tree_count, roots);
    const city = try District.geometry(&catalog.district);
    self.district_collider = try District.collider(allocator, &self.physics, city.slice(), world_flag);
    const half = self.crateHalf();
    for (crate_offsets) |offset| {
        const x = spawn[0] + offset[0];
        const z = spawn[2] + offset[2];
        const y = Terrain.surface(seed, x, z).height + half[1] + offset[1] * (half[1] * 2 + 0.05) + 0.02;
        _ = try self.spawnCrate(.{ x, y, z }, .{ 0, 0, 0 });
    }
    for (placements) |placement| {
        const bp = switch (placement.blueprint) {
            .powered_door => catalog.content.powered_door,
            .elevator => catalog.content.elevator,
            .rover => catalog.content.rover,
        };
        const x = spawn[0] + placement.offset[0];
        const z = spawn[2] + placement.offset[1];
        _ = try self.spawnMachine(null, bp.*, self.groundOrigin(bp, x, z, 0), 0, false);
    }
    for (&self.shrines, 0..) |*shrine, k| {
        const generated = Shrine.generate(Seed.mix(seed ^ (0x524f4f54 + k)));
        const bp = try Shrine.blueprint(generated.puzzle, if (k == 0) "shrine_0" else "shrine_1");
        const site = self.shrineSite(k, bp);
        shrine.* = .{ .generated = generated, .origin = self.groundOrigin(&bp, site[0], site[1], 0) };
        const m = try self.spawnMachine(null, bp, shrine.origin, 0, false);
        self.machines[m].shrine = @intCast(k);
        shrine.machine = m;
        try self.spawnShrineCrates(k);
    }
    self.market = .init(seed, 0);
    self.resetPlayer(camera);
    Frontier.init(self);
}

/// Installs a validated mod package: its scripts into the host and its blueprints into the
/// build palette. Nothing changes unless its name is free and each blueprint name is either
/// free or already holds an identical design (a save made with the mod carries its blueprints).
pub fn installMod(self: *Sandbox, pkg: *const Mod.Package) !void {
    for (self.mods[0..self.mod_count]) |*m| if (std.mem.eql(u8, m.name(), pkg.name())) return error.DuplicateMod;
    if (self.mod_count == max_mods) return error.TooManyMods;
    var added: usize = 0;
    for (pkg.blueprints[0..pkg.blueprint_count]) |*bp| {
        if (self.catalog.findBlueprint(bp.name()) != null) return error.NameConflict;
        const existing = for (self.prefabs[0..self.prefab_count]) |*p| {
            if (std.mem.eql(u8, p.name(), bp.name())) break p;
        } else null;
        if (existing) |p| {
            if (!try sameDesign(self.allocator, p, bp)) return error.NameConflict;
        } else added += 1;
    }
    if (self.prefab_count + added > max_prefabs) return error.TooManyPrefabs;
    if (pkg.wasm) |wasm| {
        var names: [Mod.max_exports][]const u8 = undefined;
        try self.scripts.add(pkg.name(), wasm, pkg.exports(&names), pkg.fuel, pkg.memory_pages);
    }
    // `addPrefab` keeps an existing same-named (identical) design.
    for (pkg.blueprints[0..pkg.blueprint_count]) |bp| _ = self.addPrefab(bp) catch unreachable;
    var ref: ModRef = .{ .version = pkg.version, .name_length = pkg.name().len };
    @memcpy(ref.name_buffer[0..ref.name_length], pkg.name());
    self.mods[self.mod_count] = ref;
    self.mod_count += 1;
}

/// Live data edits keep state and bodies only when physical layout and device IDs match.
/// Locally edited copies stay independent. Validation of every affected copy precedes commit.
pub fn reloadBlueprint(self: *Sandbox, catalog: *Catalog, guid: @import("../asset/Guid.zig"), replacement: *const Blueprint) !usize {
    const old = try catalog.registry.blueprint(.{ .guid = guid });
    if (!std.mem.eql(u8, old.name(), replacement.name())) return error.AssetNameChanged;
    if (try sameDesign(self.allocator, old, replacement)) return 0;
    if (!sameLayout(old, replacement)) return error.PhysicalLayoutChanged;
    var affected: [max_machines]bool = @splat(false);
    var count: usize = 0;
    for (&self.machines, 0..) |*placed, i| {
        if (!placed.active) continue;
        if (try sameDesign(self.allocator, &placed.blueprint, old)) {
            affected[i] = true;
            count += 1;
        }
    }
    // Registry blueprint pointers refer into this mutable catalog's fixed storage.
    for (catalog.blueprints[0..catalog.blueprint_count]) |*bp| if (bp == old) {
        bp.* = replacement.*;
        break;
    };
    for (&self.machines, affected) |*placed, applies| {
        if (!applies) continue;
        placed.blueprint = replacement.*;
        placed.machine.reconfigure();
    }
    return count;
}
fn sameLayout(a: *const Blueprint, b: *const Blueprint) bool {
    if (a.part_count != b.part_count or a.device_count != b.device_count) return false;
    if ((a.vehicle == null) != (b.vehicle == null)) return false;
    // Vehicle tuning affects instantiated physics. A vehicle edit currently requires restart.
    if (a.vehicle != null) return false;
    for (a.parts[0..a.part_count], b.parts[0..b.part_count]) |x, y| {
        if (!std.meta.eql(x.offset, y.offset) or !std.meta.eql(x.size, y.size)) return false;
    }
    for (a.devices[0..a.device_count], b.devices[0..b.device_count]) |x, y| {
        if (!std.meta.eql(x.id, y.id) or x.kind != y.kind or x.hasBody() != y.hasBody() or !std.meta.eql(x.offset, y.offset) or !std.meta.eql(x.size, y.size) or !std.meta.eql(x.travel, y.travel)) return false;
    }
    return true;
}
pub fn refreshCrateGeometry(self: *Sandbox) void {
    const half = self.crateHalf();
    for (0..max_crates) |i| if (self.crateLive(i)) self.physics.resizeBody(self.crates[i], half);
}

fn sameDesign(allocator: std.mem.Allocator, a: *const Blueprint, b: *const Blueprint) !bool {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const x = try std.json.Stringify.valueAlloc(arena.allocator(), try a.toDoc(arena.allocator()), .{});
    const y = try std.json.Stringify.valueAlloc(arena.allocator(), try b.toDoc(arena.allocator()), .{});
    return std.mem.eql(u8, x, y);
}

pub fn modInstalled(self: *const Sandbox, name: []const u8) ?Mod.Version {
    for (self.mods[0..self.mod_count]) |*m| if (std.mem.eql(u8, m.name(), name)) return m.version;
    return null;
}

/// Rootdeep: the flattest of sixteen seeded forest-floor sites 110–260 m from spawn, clear of
/// trunks, tower bases, the spawn area, and earlier shrines.
fn shrineSite(self: *const Sandbox, k: usize, bp: Blueprint) [2]f32 {
    const bounds = Build.footprint(&bp, 0);
    var best: [2]f32 = .{ spawn[0] - 150, spawn[2] + 40 * @as(f32, @floatFromInt(k)) };
    var best_score = std.math.inf(f32);
    for (0..16) |c| {
        const h = Seed.mix(self.seed ^ (0x53495445 + k * 64 + c));
        const angle = Seed.unit(h) * 2 * std.math.pi;
        const radius = 110 + 150 * Seed.unit(h >> 20);
        const x = spawn[0] + @sin(angle) * radius;
        const z = spawn[2] + @cos(angle) * radius;
        const center: [2]f32 = .{ x, z + (bounds.lo[2] + bounds.hi[2]) / 2 };
        var clear = true;
        for (0..sap_tree_count) |t| clear = clear and planar(center, self.treeOrigin(t)) > 70;
        for (self.catalog.district.nodes) |node| clear = clear and planar(center, node.position) > 50;
        for (self.shrines[0..k]) |other| clear = clear and planar(center, other.origin) > 90;
        for (self.catalog.district.buildings[0..self.catalog.district.building_count]) |b| clear = clear and planar(center, b.base) > b.radius() + 45;
        if (!clear) continue;
        var lo = std.math.inf(f32);
        var hi = -std.math.inf(f32);
        var sx = bounds.lo[0];
        while (sx <= bounds.hi[0]) : (sx += 2) {
            var sz = bounds.lo[2];
            while (sz <= bounds.hi[2]) : (sz += 2) {
                const y = Terrain.surface(self.seed, x + sx, z + sz).height;
                lo = @min(lo, y);
                hi = @max(hi, y);
            }
        }
        if (hi - lo < best_score) {
            best_score = hi - lo;
            best = .{ x, z };
        }
    }
    return best;
}

fn planar(a: [2]f32, b: Physics.Vec3) f32 {
    return @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[2]) * (a[1] - b[2]));
}

/// World position of a point in shrine `k`'s local frame.
pub fn shrinePoint(self: *const Sandbox, k: usize, local: [3]f32) Physics.Vec3 {
    return R.add(self.shrines[k].origin, local);
}

/// Whether `p` is inside shrine `k`'s walls (floor to roof).
pub fn insideShrine(self: *const Sandbox, k: usize, p: Physics.Vec3) bool {
    const l = R.sub(p, self.shrines[k].origin);
    return @abs(l[0]) < Shrine.width / 2 + 0.5 and l[2] > -0.5 and l[2] < Shrine.length(self.shrines[k].generated.puzzle) + 0.5 and l[1] > -1 and l[1] < Shrine.height + 0.5;
}

fn spawnShrineCrates(self: *Sandbox, k: usize) !void {
    const p = self.shrines[k].generated.puzzle;
    const half = self.crateHalf();
    for (0..p.plates) |c| _ = try self.spawnCrate(R.add(self.shrinePoint(k, Shrine.crateStart(p, c)), .{ 0, half[1] + 0.02, 0 }), .{ 0, 0, 0 });
}

/// The shrine's reset button: crates inside it return to their starts, latches reopen, and
/// doors close. Crates carried out of the shrine stay where they are.
pub fn resetShrine(self: *Sandbox, k: usize) !void {
    const m = self.shrines[k].machine orelse return;
    if (self.shrines[k].completed) return self.say("this seed vault is already open", .{});
    for (0..max_crates) |i| if (self.crateLive(i) and self.insideShrine(k, self.cratePosition(@intCast(i)))) self.removeCrate(@intCast(i));
    const placed = &self.machines[m];
    var states: [Blueprint.max_devices]f32 = @splat(0);
    try placed.machine.restore(states[0..placed.machine.states().len]);
    for (placed.blueprint.devices[0..placed.blueprint.device_count], 0..) |def, d| {
        if (def.kind == .actuator) self.physics.setTransform(placed.devices[d], placed.machine.devicePosition(d), .{ 0, 0, 0 });
    }
    try self.spawnShrineCrates(k);
    self.say("shrine reset", .{});
}

/// A shrine is complete when its vault latch is set; the first time, its reward blueprint joins
/// the build palette (and so the saved prefab library).
fn checkShrines(self: *Sandbox) void {
    for (&self.shrines, 0..) |*shrine, k| {
        if (shrine.completed) continue;
        const m = shrine.machine orelse continue;
        const machine = &self.machines[m].machine;
        const sealed = machine.blueprint.findDevice("sealed") orelse continue;
        if (machine.outputs[sealed][1] < 0.5) continue;
        shrine.completed = true;
        self.progress.setFlag("shrine_complete");
        const reward = self.catalog.content.rewards[k];
        _ = self.addPrefab(reward.*) catch return self.say("seed vault opened: palette full", .{});
        self.say("seed vault opened: {s} added to your palette", .{reward.name()});
    }
}

/// Frees mesh colliders. Bodies and machines own no heap memory.
pub fn deinit(self: *Sandbox) void {
    self.dialogue.deinit();
    self.scripts.deinit();
    for (&self.rigs) |*slot| if (slot.*) |*r| r.deinit(self.allocator);
    self.physics.deinit();
}

/// Places the test Arbor with its ramp starting on the terrain at the given trunk center.
fn placeArbor(self: *Sandbox, x: f32, z: f32) !void {
    const start = TestArbor.rampPoint(0);
    const origin: Physics.Vec3 = .{ x, Terrain.surface(self.seed, x + start[0], z + start[2]).height, z };
    _ = try TestArbor.createColliders(self.allocator, &self.physics, origin, world_flag, &self.arbor_colliders);
    self.arbor_origin = origin;
}

pub fn say(self: *Sandbox, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&self.notice, fmt, args) catch self.notice[0..];
    self.notice_len = text.len;
    self.notice_until = self.tick + 3 * 60;
}

pub fn noticeText(self: *const Sandbox) []const u8 {
    return if (self.tick < self.notice_until) self.notice[0..self.notice_len] else "";
}

/// Adds a validated prefab; an existing name is kept, not duplicated.
pub fn addPrefab(self: *Sandbox, bp: Blueprint) !usize {
    for (self.prefabs[0..self.prefab_count], 0..) |*existing, i| if (std.mem.eql(u8, existing.name(), bp.name())) return i;
    if (self.prefab_count == max_prefabs) return error.TooManyPrefabs;
    self.prefabs[self.prefab_count] = bp;
    self.prefab_count += 1;
    return self.prefab_count - 1;
}

pub fn crateHalf(self: *const Sandbox) Physics.Vec3 {
    return self.catalog.mesh(self.catalog.content.crate).?.model.halfExtents();
}

pub fn crateLive(self: *const Sandbox, index: usize) bool {
    return self.physics.valid(self.crates[index]);
}

pub fn spawnCrate(self: *Sandbox, position: Physics.Vec3, velocity: Physics.Vec3) !u32 {
    const slot = for (self.crates, 0..) |c, i| {
        if (!self.physics.valid(c)) break i;
    } else return error.TooManyCrates;
    try self.spawnCrateAt(slot, position, velocity);
    return @intCast(slot);
}

fn spawnCrateAt(self: *Sandbox, slot: usize, position: Physics.Vec3, velocity: Physics.Vec3) !void {
    self.crates[slot] = try self.physics.createBody(.{ .half_extents = self.crateHalf(), .position = position, .velocity = velocity, .mass = 20, .user = @intCast(slot) });
}

pub fn removeCrate(self: *Sandbox, index: u32) void {
    if (self.held == index) self.release();
    self.physics.destroyBody(self.crates[index]);
    self.crates[index] = .none;
}

pub fn machineCount(self: *const Sandbox) usize {
    var n: usize = 0;
    for (self.machines) |placed| n += @intFromBool(placed.active);
    return n;
}

pub fn yawRotation(yaw: u2) R.Quat {
    return R.axisAngle(.{ 0, 1, 0 }, @as(f32, @floatFromInt(yaw)) * std.math.pi / 2.0);
}

/// Box half extents after a quarter-turn yaw.
pub fn turnedHalf(size: [3]f32, yaw: u2) Physics.Vec3 {
    return if (yaw % 2 == 1) .{ size[2] / 2, size[1] / 2, size[0] / 2 } else .{ size[0] / 2, size[1] / 2, size[2] / 2 };
}

/// Origin on the highest terrain under a blueprint's rotated structure footprint, so the
/// foundation never floats; parts are authored to extend below the origin. Vehicles get
/// their spawn height above their ride height.
pub fn groundOrigin(self: *const Sandbox, bp: *const Blueprint, x: f32, z: f32, yaw: u2) Physics.Vec3 {
    if (bp.vehicle) |v| {
        const wheel = v.wheels[0];
        return .{ x, Terrain.surface(self.seed, x, z).height + wheel.radius + wheel.rest - wheel.offset[1] + 0.1, z };
    }
    const bounds = Build.footprint(bp, yaw);
    var y = -std.math.inf(f32);
    var sx = bounds.lo[0];
    while (sx <= bounds.hi[0]) : (sx += 1) {
        var sz = bounds.lo[2];
        while (sz <= bounds.hi[2]) : (sz += 1) y = @max(y, Terrain.surface(self.seed, x + sx, z + sz).height);
    }
    return .{ x, if (std.math.isFinite(y)) y else Terrain.surface(self.seed, x, z).height, z };
}

fn deviceUser(m: usize, d: usize) u32 {
    return machine_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(d));
}

/// Places a copy of `bp` in a machine slot (a free one when `slot` is null) with bodies for
/// its structure and physical devices, or a chassis for vehicles.
pub fn spawnMachine(self: *Sandbox, slot: ?usize, bp: Blueprint, origin: Physics.Vec3, yaw: u2, workshop: bool) !u8 {
    const m = slot orelse for (self.machines, 0..) |placed, i| {
        if (!placed.active) break i;
    } else return error.TooManyMachines;
    const placed = &self.machines[m];
    std.debug.assert(!placed.active);
    placed.* = .{ .active = true, .blueprint = bp, .yaw = yaw, .workshop = workshop };
    placed.machine = .init(&placed.blueprint, origin);
    placed.machine.rotation = yawRotation(yaw);
    errdefer self.removeMachine(@intCast(m));
    if (bp.vehicle) |v| {
        const rigid = try self.physics.createRigid(.{ .half_extents = halve(v.size), .position = origin, .orientation = placed.machine.rotation, .mass = v.mass, .user = machine_flag | chassis_flag | @as(u32, @intCast(m)) << 8 | v.seat });
        var wheels: [Vehicle.max_wheels]Vehicle.Wheel = undefined;
        for (v.wheels[0..v.wheel_count], wheels[0..v.wheel_count]) |def, *w| w.* = .{ .mount = def.offset, .radius = def.radius, .rest = def.rest, .driven = def.driven, .steered = def.steered };
        placed.vehicle = .init(rigid, .{ .stiffness = v.stiffness, .damping = v.damping, .grip = v.grip, .max_force = v.max_force, .max_brake = v.max_brake, .max_steer = v.max_steer }, wheels[0..v.wheel_count]);
        return @intCast(m);
    }
    for (bp.parts[0..bp.part_count], 0..) |part, i| {
        placed.parts[i] = try self.physics.createBody(.{ .half_extents = turnedHalf(part.size, yaw), .position = placed.machine.worldOffset(part.offset), .motion = .static, .user = machine_flag | part_flag | @as(u32, @intCast(m)) << 8 | @as(u32, @intCast(i)) });
    }
    for (0..bp.device_count) |d| try self.createDeviceBody(m, d);
    return @intCast(m);
}

fn createDeviceBody(self: *Sandbox, m: usize, d: usize) !void {
    const placed = &self.machines[m];
    const def = placed.blueprint.devices[d];
    if (!def.hasBody() or placed.vehicle != null) return;
    placed.devices[d] = try self.physics.createBody(.{
        .half_extents = turnedHalf(def.size, placed.yaw),
        .position = placed.machine.devicePosition(d),
        .motion = if (def.kind == .actuator) .kinematic else .static,
        .user = deviceUser(m, d),
    });
}

pub fn removeMachine(self: *Sandbox, m: u8) void {
    const placed = &self.machines[m];
    if (!placed.active) return;
    if (self.seated == m) self.seated = null;
    for (placed.devices ++ placed.parts) |body| self.physics.destroyBody(body);
    if (placed.vehicle) |v| self.physics.destroyRigid(v.rigid);
    if (self.workshop == m) self.workshop = null;
    if (self.tools.wire_from) |w| if (w.machine == m) {
        self.tools.wire_from = null;
    };
    placed.* = .{};
}

/// Adds a validated device to the workshop machine (creating it at `point` if needed).
pub fn addWorkshopDevice(self: *Sandbox, def: Blueprint.DocDevice, point: Physics.Vec3) !DeviceRef {
    const m = self.workshop orelse blk: {
        var bp: Blueprint = .{};
        try bp.setName("workshop");
        const slot = try self.spawnMachine(null, bp, point, 0, true);
        self.workshop = slot;
        break :blk slot;
    };
    const placed = &self.machines[m];
    var local = def;
    local.offset = R.sub(point, placed.machine.origin);
    const d = try placed.blueprint.addDevice(local);
    placed.machine.reconfigure();
    self.createDeviceBody(m, d) catch |err| {
        placed.blueprint.removeDevice(d) catch {};
        placed.machine.reconfigure();
        return err;
    };
    return .{ .machine = m, .device = d };
}

/// Removes one workshop device; later devices shift down and their bodies are re-tagged.
pub fn removeWorkshopDevice(self: *Sandbox, ref: DeviceRef) !void {
    const placed = &self.machines[ref.machine];
    self.physics.destroyBody(placed.devices[ref.device]);
    try placed.blueprint.removeDevice(ref.device);
    placed.machine.removeDevice(ref.device);
    placed.machine.reconfigure();
    const count = placed.blueprint.device_count;
    std.mem.copyForwards(Physics.Body, placed.devices[ref.device..count], placed.devices[ref.device + 1 .. count + 1]);
    placed.devices[count] = .none;
    for (placed.devices[ref.device..count], ref.device..) |body, d| self.physics.setUser(body, deviceUser(ref.machine, d));
    if (self.tools.wire_from) |w| if (w.machine == ref.machine) {
        self.tools.wire_from = null;
    };
    if (count == 0) self.removeMachine(ref.machine);
}

pub fn halve(size: [3]f32) Physics.Vec3 {
    return .{ size[0] / 2, size[1] / 2, size[2] / 2 };
}

fn groundSample(context: ?*const anyopaque, x: f32, z: f32) Physics.GroundSample {
    const seed: *const u64 = @ptrCast(@alignCast(context.?));
    const s = Terrain.surface(seed.*, x, z);
    return .{ .height = s.height, .normal = s.normal };
}

pub fn resetPlayer(self: *Sandbox, camera: *Camera) void {
    self.release();
    self.seated = null;
    camera.* = .{ .yaw = 0, .pitch = -0.2 };
    self.player = .{ .feet = .{ spawn[0], Terrain.surface(self.seed, spawn[0], spawn[2]).height, spawn[2] }, .mode = self.player.mode };
    if (self.player.mode == .fly) {
        self.player.feet[1] += 20;
    }
    camera.position = self.player.eye();
}

/// Where aiming starts: the camera in first person, the character's eyes otherwise.
pub fn aimCameraPublic(self: *const Sandbox, camera: Camera) Camera {
    return self.aimCamera(camera);
}

fn aimCamera(self: *const Sandbox, camera: Camera) Camera {
    var aim = camera;
    if (self.bodyShown()) aim.position = self.player.eye();
    return aim;
}

/// The avatar is drawn in third person, the creator, conversations and the wardrobe, on foot only.
pub fn bodyShown(self: *const Sandbox) bool {
    return self.seated == null and self.garage.piloting == null and !self.hangar.piloting and self.player.mode == .walk and (self.view == .third or self.creator.open or self.talk != null or self.wardrobeOpen());
}

/// The wardrobe shows the character from the front, like the creator.
pub fn wardrobeOpen(self: *const Sandbox) bool {
    return if (self.shop) |shop| shop.kind == .wardrobe else false;
}

/// Guest `index` (0 = P2) joins beside P1 with a distinct accent and outfit.
pub fn joinGuest(self: *Sandbox, index: usize) void {
    var profile: Profile = .{ .accent = @intCast((index + 1) % Profile.accent_colors.len), .outfit = @intCast((index * 3 + 2) % Profile.outfit_colors.len), .hair_color = @intCast((index * 2 + 3) % Profile.hair_colors.len) };
    var name: [2]u8 = .{ 'P', '2' + @as(u8, @intCast(index)) };
    profile.setName(&name) catch unreachable;
    self.guests[index] = .{ .active = true, .profile = profile };
    self.respawnGuest(index);
}

pub fn leaveGuest(self: *Sandbox, index: usize) void {
    self.guests[index].active = false;
}

pub fn guestCount(self: *const Sandbox) usize {
    var n: usize = 0;
    for (self.guests) |g| n += @intFromBool(g.active);
    return n;
}

/// Places a guest on the floor beside P1, facing the same way, with fresh traversal state.
pub fn respawnGuest(self: *Sandbox, index: usize) void {
    const g = &self.guests[index];
    var feet = R.add(self.player.feet, R.rotate(R.axisAngle(.{ 0, 1, 0 }, self.body_yaw), guest_offsets[index]));
    const terrain = Terrain.surface(self.seed, feet[0], feet[2]).height;
    feet[1] = if (self.physics.castRay(R.add(feet, .{ 0, 2, 0 }), .{ 0, -1, 0 }, 8, .none)) |hit| @max(hit.point[1], terrain) + 0.01 else terrain;
    g.player = .{ .feet = feet };
    g.camera = .{ .yaw = self.body_yaw, .pitch = -0.2 };
    g.body_yaw = self.body_yaw;
    g.camera.position = g.player.eye();
    g.target = .none;
}

fn stride(player: Player, phase: *f32, amount: *f32, dt: f32) void {
    const ground_speed = @sqrt(player.velocity[0] * player.velocity[0] + player.velocity[2] * player.velocity[2]);
    phase.* = @mod(phase.* + ground_speed * dt * 2.4, 2 * std.math.pi);
    amount.* = if (player.grounded) @min(1, ground_speed / Player.walk_speed) else 0.3;
}

fn stepGuest(self: *Sandbox, g: *Guest, dt: f32) void {
    defer {
        g.interact = false;
        g.toggle_view = false;
        g.trade_up = false;
        g.trade_down = false;
    }
    if (g.toggle_view) g.view = if (g.view == .first) .third else .first;
    // At a stall the pad drives the trade panel and the body stands still.
    if (g.trading) |stall| {
        const key: ?TradeKey = if (g.input.dodge) .close else if (g.interact) .confirm else if (g.trade_up) .up else if (g.trade_down) .down else null;
        if (key) |k| if (self.trade(stall, &g.trade_row, k)) {
            g.trading = null;
        };
        const d = R.sub(self.stallPosition(stall), g.player.feet);
        if (@sqrt(d[0] * d[0] + d[2] * d[2]) > reach + 4) g.trading = null;
        g.player.step(&self.physics, &g.camera, .{}, dt);
        if (g.view == .third) self.chase(g.player.eye(), &g.camera);
        return;
    }
    g.camera.turn(g.input.look_x, g.input.look_y, dt);
    g.player.step(&self.physics, &g.camera, g.input, dt);
    g.body_yaw = g.camera.yaw;
    stride(g.player, &g.walk_phase, &g.walk_amount, dt);
    if (g.view == .third) self.chase(g.player.eye(), &g.camera);
    // Hands only: aim from the eyes, press buttons, and open market stalls.
    const eye = g.player.eye();
    g.target = self.pick(eye, g.camera.forward(), reach, false, true);
    if (g.interact and g.target == .stall) {
        g.trading = g.target.stall;
        g.trade_row = 0;
    }
    if (g.interact and g.target == .device) {
        const d = g.target.device;
        if (self.machines[d.machine].blueprint.devices[d.device].kind == .button and self.press == null) self.press = d;
    }
}

pub fn step(self: *Sandbox, camera: *Camera, raw_input: Input, raw_actions: Actions, dt: f32) !void {
    if (raw_actions.open_creator and self.seated == null and !self.creator.open) self.creator.begin(self.profile);
    if (raw_actions.toggle_view) self.view = if (self.view == .first) .third else .first;
    // The creator, conversations and tinker panels freeze the character and every tool.
    self.creator.owned = self.progress.suits;
    self.creator.owned_armor = self.progress.armors;
    const frozen = self.creator.open or self.talk != null or self.shop != null;
    const suit = self.progress.suit();
    self.player.suit = suit;
    for (&self.guests) |*g| g.player.suit = suit;
    if (self.talk) |*session| Dialogue.advance(session, dt);
    const input: Input = if (frozen) .{} else raw_input;
    const actions: Actions = if (frozen) .{} else raw_actions;
    if (self.creator.open) camera.yaw = self.body_yaw;
    if (actions.reset) self.resetPlayer(camera);
    const riding = self.seated != null or self.garage.piloting != null or self.hangar.piloting;
    if (actions.toggle_mode and !riding) self.player.setMode(if (self.player.mode == .walk) .fly else .walk, camera.*);
    if (actions.select_tool != 0 and !riding) Build.selectTool(self, @enumFromInt(actions.select_tool - 1));
    var primary = actions.interact;
    if (self.seated != null) {
        if (primary) self.exitVehicle(camera) else self.driver_input = .{ .throttle = input.forward, .steer = input.right, .brake = @floatFromInt(@intFromBool(input.jump)) };
        primary = false;
    }
    if (self.garage.piloting != null) {
        if (primary) Frontier.leave(self, camera);
        primary = false;
    }
    // In the Kestrel the primary button fires; climbing out is its own action (F).
    if (self.hangar.piloting) {
        if (actions.leave_jet) Frontier.leaveJet(self, camera);
        primary = false;
    }
    if (self.seated == null and self.garage.piloting == null and !self.hangar.piloting) self.player.step(&self.physics, camera, input, dt);
    if (!frozen) self.body_yaw = camera.yaw;
    stride(self.player, &self.walk_phase, &self.walk_amount, dt);
    for (&self.guests) |*g| if (g.active) self.stepGuest(g, dt);
    self.stepMachines(dt);
    self.checkShrines();
    self.stepLife(dt);
    Frontier.step(self, camera, input, actions, frozen, dt);
    const aim = self.aimCamera(camera.*);
    if (self.held) |i| {
        // Spring the held crate toward a point in front of the eye; physics still resolves contacts.
        const body = self.crates[i];
        const p = self.physics.position(body).?;
        const f = aim.forward();
        const goal = aim.position.add(&f.mulScalar(hold_distance));
        var v: Physics.Vec3 = .{ (goal.x() - p[0]) * 12, (goal.y() - p[1]) * 12, (goal.z() - p[2]) * 12 };
        const speed = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (speed > 15) v = .{ v[0] * 15 / speed, v[1] * 15 / speed, v[2] * 15 / speed };
        self.physics.setVelocity(body, v);
        // Drop it if something wedges it far from the hold point.
        const gap = goal.sub(&math.vec3(p[0], p[1], p[2]));
        if (gap.dot(&gap) > 4 * 4) self.release();
    }
    self.physics.step(dt);
    self.tick += 1;
    if (self.market.update(self.tick)) self.say("markets restocked for day {d}", .{self.market.day});
    if (self.trading) |stall| {
        const d = R.sub(self.stallPosition(stall), self.player.feet);
        if (self.seated != null or @sqrt(d[0] * d[0] + d[2] * d[2]) > reach + 4) self.trading = null;
    }
    if (self.seated) |m| {
        self.followVehicle(m, camera);
        self.target = .none;
        return;
    }
    if (self.hangar.follow(self.seed, camera)) |feet| {
        self.player.feet = feet;
        self.player.velocity = .{ 0, 0, 0 };
        self.target = .none;
        return;
    }
    if (self.garage.follow(self.seed, camera, dt)) |feet| {
        self.player.feet = feet;
        self.player.velocity = .{ 0, 0, 0 };
        self.target = .none;
        return;
    }
    self.placeCamera(camera);
    if (frozen) {
        self.target = .none;
        return;
    }
    self.refreshNearby(aim.position);
    // Build and wire tools reach farther and ignore relics.
    const hands = self.tools.tool == .hands;
    self.target = self.pick(aim.position, aim.forward(), if (hands) reach else Build.build_reach, hands, hands);
    if (hands and self.target == .none) {
        const f = aim.forward();
        if (Frontier.pick(self, .{ aim.position.x(), aim.position.y(), aim.position.z() }, .{ f.x(), f.y(), f.z() }, reach + 2, reach + 2)) |t| self.target = t;
    }
    if (actions.channel_down or actions.channel_up) Build.adjustChannel(self, if (actions.channel_up) 1 else -1);
    switch (self.tools.tool) {
        .hands => {
            if (primary) {
                if (self.held != null) self.release() else switch (self.target) {
                    .prop => |i| self.hold(i),
                    .stall => |i| self.startTalk(.{ .keeper = i }),
                    .walker => |i| self.startTalk(.{ .walker = i }),
                    .car => |i| Frontier.board(self, i, camera),
                    .fabricator => self.shop = .{ .kind = .fabricate },
                    .jet => Frontier.boardJet(self, camera),
                    .device => |d| switch (self.machines[d.machine].blueprint.devices[d.device].kind) {
                        .button => if (self.machines[d.machine].shrine != null and std.mem.eql(u8, self.machines[d.machine].blueprint.devices[d.device].name(), "reset")) {
                            try self.resetShrine(self.machines[d.machine].shrine.?);
                        } else {
                            self.press = d;
                        },
                        .seat => self.enterVehicle(d.machine, camera),
                        else => {},
                    },
                    else => {},
                }
            }
            if (actions.secondary) switch (self.target) {
                .relic => |relic| {
                    _ = try self.modifications.remove(relic.ref);
                    // Salvage yields parts a market will buy (more with the salvage kit upgrade).
                    self.wallet.parts += self.progress.partsPerSalvage();
                    self.progress.setFlag("salvaged");
                },
                else => {},
            };
        },
        .build, .wire, .bridge => try Build.update(self, aim, primary, actions),
        // The arsenal fires from `Frontier.step`, from the held triggers.
        .weapon => {},
    }
}

/// Creator: face the character from the front. Third person: behind and above the eyes,
/// kept above the terrain. First person: at the eyes (set by the player step).
fn placeCamera(self: *const Sandbox, camera: *Camera) void {
    if (self.player.mode != .walk) return;
    const eye = self.player.eye();
    // In conversation the camera frames the partner over the player's right shoulder.
    if (self.talk) |session| {
        const head = R.add(self.partnerPosition(session.partner), .{ 0, 1.5, 0 });
        const to = R.sub(head, .{ eye.x(), eye.y(), eye.z() });
        const flat = R.normalize(.{ to[0], 0, to[2] });
        const right: Physics.Vec3 = .{ flat[2], 0, -flat[0] };
        const from = R.add(.{ eye.x(), eye.y() + 0.15, eye.z() }, R.add(R.scale(flat, -1.6), R.scale(right, -0.75)));
        const d = R.sub(head, from);
        camera.position = math.vec3(from[0], from[1], from[2]);
        camera.yaw = std.math.atan2(d[0], d[2]);
        camera.pitch = std.math.atan2(d[1], @sqrt(d[0] * d[0] + d[2] * d[2]));
        return;
    }
    if (self.creator.open or self.wardrobeOpen()) {
        const front = R.rotate(R.axisAngle(.{ 0, 1, 0 }, self.body_yaw), .{ 0, 0, 2.8 });
        camera.position = math.vec3(self.player.feet[0] + front[0], self.player.feet[1] + 1.35, self.player.feet[2] + front[2]);
        camera.yaw = self.body_yaw + std.math.pi;
        camera.pitch = -0.1;
        return;
    }
    if (self.view == .first) return;
    self.chase(eye, camera);
}

/// Third person: behind and above the eyes along the view direction, kept above the terrain.
fn chase(self: *const Sandbox, eye: math.Vec3, camera: *Camera) void {
    const f = camera.forward();
    var p = math.vec3(eye.x() - f.x() * third_person_distance, eye.y() + 0.3 - f.y() * third_person_distance, eye.z() - f.z() * third_person_distance);
    const ground = Terrain.surface(self.seed, p.x(), p.z()).height + 0.4;
    if (p.y() < ground) p = math.vec3(p.x(), ground, p.z());
    camera.position = p;
}

pub fn enterVehicle(self: *Sandbox, machine: u8, camera: *Camera) void {
    self.release();
    self.seated = machine;
    self.driver_input = .{};
    const pose = self.physics.rigidPose(self.machines[machine].vehicle.?.rigid).?;
    camera.yaw = R.yaw(pose.orientation);
    camera.pitch = -0.25;
    self.followVehicle(machine, camera);
}

/// Steps out to the vehicle's left, onto the nearest floor.
pub fn exitVehicle(self: *Sandbox, camera: *Camera) void {
    const m = self.seated orelse return;
    self.seated = null;
    const placed = &self.machines[m];
    const pose = self.physics.rigidPose(placed.vehicle.?.rigid).?;
    const side = R.add(pose.position, R.rotate(pose.orientation, .{ -(placed.blueprint.vehicle.?.size[0] / 2 + 1.2), 0, 0 }));
    // Leave onto the nearest surface beside the chassis, including canopy decks. If there
    // is no nearby floor, start falling from the vehicle rather than teleporting to terrain.
    const floor = self.physics.castRay(R.add(side, .{ 0, 0.5, 0 }), .{ 0, -1, 0 }, 3, placed.vehicle.?.rigid);
    self.player = .{ .feet = .{ side[0], if (floor) |hit| hit.point[1] + 0.01 else side[1], side[2] }, .mode = .walk };
    camera.pitch = -0.2;
    camera.position = self.player.eye();
}

/// Seats the player and places the chase camera behind and above the chassis.
fn followVehicle(self: *Sandbox, m: u8, camera: *Camera) void {
    const placed = &self.machines[m];
    const v = placed.blueprint.vehicle.?;
    const seat = placed.machine.devicePosition(v.seat);
    self.player.feet = .{ seat[0], seat[1] - 0.5, seat[2] };
    self.player.velocity = .{ 0, 0, 0 };
    self.player.grounded = false;
    self.player.support = .none;
    const pose = self.physics.rigidPose(placed.vehicle.?.rigid).?;
    const f = camera.forward();
    var eye = math.vec3(pose.position[0] - f.x() * chase_distance, pose.position[1] + 1.5 - f.y() * chase_distance, pose.position[2] - f.z() * chase_distance);
    const ground = Terrain.surface(self.seed, eye.x(), eye.z()).height + 0.6;
    if (eye.y() < ground) eye = math.vec3(eye.x(), ground, eye.z());
    camera.position = eye;
}

/// Advances every machine one fixed step, then drives actuator bodies to their new positions
/// through velocity so physics pushes whatever they touch, and feeds vehicle controls.
fn stepMachines(self: *Sandbox, dt: f32) void {
    const previous = self.bus;
    self.bus = @splat(0);
    const heard = self.songs;
    self.songs = @splat(@splat(0));
    defer for (&self.machines) |*placed| if (placed.active) placed.machine.sing(&self.songs);
    var weights: [max_crates][3]f32 = undefined;
    var weight_count: usize = 0;
    for (0..max_crates) |i| if (self.crateLive(i)) {
        weights[weight_count] = self.cratePosition(@intCast(i));
        weight_count += 1;
    };
    var others: [max_players - 1][3]f32 = undefined;
    var other_count: usize = 0;
    for (self.guests) |g| if (g.active) {
        others[other_count] = g.player.feet;
        other_count += 1;
    };
    defer for (&self.machines) |*placed| if (placed.active) placed.machine.transmit(&self.bus);
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        var env: Machine.Environment = .{ .player_feet = self.player.feet, .other_feet = others[0..other_count], .bus = &previous, .songs = &heard, .weights = weights[0..weight_count] };
        // Script devices run now on last step's signals, like logic (one step per hop).
        const time = @as(f32, @floatFromInt(self.tick % (1 << 24))) / 60;
        for (placed.blueprint.devices[0..placed.blueprint.device_count], 0..) |*def, d| {
            if (def.kind != .script) continue;
            const mc = &placed.machine;
            mc.script_out[d] = self.scripts.call(def.scriptName(), .{ mc.inputNow(d, 0), mc.inputNow(d, 1), mc.inputNow(d, 2), mc.inputNow(d, 3) }, time);
        }
        // Rootsong devices are heard only while within reach of wood.
        for (placed.blueprint.devices[0..placed.blueprint.device_count], 0..) |def, d| {
            placed.machine.root_group[d] = null;
            if (def.kind != .root_sender and def.kind != .root_listener) continue;
            if (self.sapAttachment(placed.machine.devicePosition(d))) |link| placed.machine.root_group[d] = self.root_groups[link.tree];
        }
        if (self.press) |p| if (p.machine == m) {
            env.pressed = p.device;
        };
        if (placed.vehicle) |vehicle| {
            const driving = self.seated == @as(u8, @intCast(m));
            const pose = self.physics.rigidPose(vehicle.rigid).?;
            placed.machine.origin = pose.position;
            placed.machine.rotation = pose.orientation;
            if (driving) env.controls = self.driver_input;
        }
        placed.machine.prepare(env);
    }
    self.distributeSap();
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        placed.machine.finish(dt);
        if (placed.vehicle) |*vehicle| {
            const driving = self.seated == @as(u8, @intCast(m));
            const v = placed.blueprint.vehicle.?;
            const out = placed.machine.outputs;
            const brake = if (driving) out[v.seat][3] else 1;
            vehicle.step(&self.physics, .{ .drive = out[v.motor][2], .steer = out[v.steering][1], .brake = brake }, dt);
            continue;
        }
        const bp = &placed.blueprint;
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (def.kind != .actuator) continue;
            const goal = placed.machine.devicePosition(d);
            const now = self.physics.position(placed.devices[d]).?;
            self.physics.setVelocity(placed.devices[d], .{ (goal[0] - now[0]) / dt, (goal[1] - now[1]) / dt, (goal[2] - now[2]) / dt });
        }
    }
    self.press = null;
}

pub fn bridgeEdges(self: *const Sandbox, out: *[District.max_bridges]District.Edge) []const District.Edge {
    var n: usize = 0;
    for (self.bridges) |maybe| if (maybe) |bridge| {
        out[n] = bridge.edge;
        n += 1;
    };
    return out[0..n];
}

/// The current road graph: generated roads plus player bridges.
pub fn routes(self: *const Sandbox) Routes {
    var edges: [District.max_bridges]District.Edge = undefined;
    return Routes.init(&self.catalog.district, self.openBridgeEdges(&edges));
}

/// Player bridges open to traffic; a closing bridge is already gone as far as routing and
/// saves are concerned.
pub fn openBridgeEdges(self: *const Sandbox, out: *[District.max_bridges]District.Edge) []const District.Edge {
    var n: usize = 0;
    for (self.bridges) |maybe| if (maybe) |bridge| if (!bridge.closing) {
        out[n] = bridge.edge;
        n += 1;
    };
    return out[0..n];
}

/// Removes player bridge `slot` now if nothing is on it; otherwise closes it to new traffic
/// and removes it once the cars and pedestrians on it have crossed. Returns whether it is gone.
pub fn closeBridge(self: *Sandbox, slot: usize) bool {
    if (slot >= self.bridges.len) return true;
    const bridge = &(self.bridges[slot] orelse return true);
    if (!self.bridgeOccupied(slot)) {
        self.removeBridge(slot);
        return true;
    }
    if (!bridge.closing) self.road_revision += 1;
    bridge.closing = true;
    return false;
}

/// Starts ambient traffic and pedestrians (cars take rigid-body slots while it runs).
pub fn enableLife(self: *Sandbox) void {
    if (self.life.active) self.life.despawn(&self.physics);
    const graph = self.routes();
    self.life.spawn(&self.physics, &graph, self.seed, self.catalog.content.rover.vehicle.?, world_flag, self.road_revision);
}

/// Whether a car or pedestrian is on player bridge `slot`.
pub fn bridgeOccupied(self: *const Sandbox, slot: usize) bool {
    const bridge = self.bridges[slot] orelse return false;
    const graph = self.routes();
    return self.life.occupies(&self.physics, &graph, bridge.edge);
}

/// Floor centre of market stall `i`.
pub fn stallPosition(self: *const Sandbox, i: usize) Physics.Vec3 {
    return District.marketPosition(&self.catalog.district, Market.stall_plazas[i]);
}

/// Trade panel input. Confirm on the first row sells every salvaged part; on a ware row it
/// buys one kit of that blueprint for the build palette.
pub fn tradeKey(self: *Sandbox, key: TradeKey) void {
    const stall = self.trading orelse return;
    if (self.trade(stall, &self.trade_row, key)) self.trading = null;
}

/// One trade-panel key for any player at `stall`; returns true when the panel closes.
fn trade(self: *Sandbox, stall: u8, row: *u8, key: TradeKey) bool {
    switch (key) {
        .up => row.* = (row.* + trade_rows - 1) % trade_rows,
        .down => row.* = (row.* + 1) % trade_rows,
        .close => return true,
        .confirm => if (row.* == 0) {
            const earned = self.market.sellParts(stall, &self.wallet) catch {
                self.say("no salvaged parts to sell", .{});
                return false;
            };
            self.say("sold parts for {d} scrap", .{earned});
        } else {
            const ware: Market.Ware = @enumFromInt(row.* - 1);
            self.market.buy(stall, ware, &self.wallet) catch |err| {
                self.say("cannot buy: {s}", .{reason(err)});
                return false;
            };
            self.say("bought a {s} kit: place it with the build tool", .{@tagName(ware)});
        },
    }
    return false;
}

/// One trade-panel row's text (row 0 sells parts; others are wares), marked when selected.
pub fn tradeRow(self: *const Sandbox, stall: u8, row: u8, selected: bool, out: *TradeLine) void {
    const marker = if (selected) "> " else "  ";
    if (row == 0) return out.set("{s}SELL {d} PARTS AT {d} SCRAP EACH", .{ marker, self.wallet.parts, self.market.partPrice(stall) });
    const w = row - 1;
    const ware: Market.Ware = @enumFromInt(w);
    out.set("{s}{s} KIT  {d} SCRAP  STOCK {d}  HELD {d}", .{ marker, @tagName(ware), self.market.price(stall, ware), self.market.stalls[stall].stock[w], self.wallet.kits[w] });
}

pub const TradeLine = @import("Build.zig").PanelLine;
/// The open stall's panel: header, one line per row (the selected one marked), and help.
pub fn tradeLines(self: *const Sandbox, out: []TradeLine) usize {
    const stall = self.trading orelse return 0;
    out[0].set("MARKET {d}  DAY {d}  SCRAP {d}  PARTS {d}", .{ Market.stall_plazas[stall], self.market.day, self.wallet.scrap, self.wallet.parts });
    for (0..trade_rows) |r| self.tradeRow(stall, @intCast(r), r == self.trade_row, &out[1 + r]);
    out[1 + trade_rows].set("UP/DOWN CHOOSE  ENTER TRADE  ESC CLOSE  RESTOCKS AT DAWN", .{});
    return 2 + trade_rows;
}

/// Feet of the keeper behind stall `i`'s counter.
pub fn keeperPosition(self: *const Sandbox, i: usize) Physics.Vec3 {
    const stall = self.stallPosition(i);
    const toward = R.sub(self.catalog.district.nodes[Market.stall_plazas[i]].position, stall);
    return R.sub(stall, R.scale(R.normalize(.{ toward[0], 0, toward[2] }), 1.2));
}

pub fn partnerPosition(self: *const Sandbox, partner: Dialogue.Partner) Physics.Vec3 {
    return switch (partner) {
        .keeper => |i| self.keeperPosition(i),
        .walker => |i| self.life.walkers[i].player.feet,
    };
}

/// Opens a conversation with a keeper or pedestrian (P1). The pedestrian stops and turns.
pub fn startTalk(self: *Sandbox, partner: Dialogue.Partner) void {
    var buffer: [16]u8 = undefined;
    const index = switch (partner) {
        .keeper => |i| self.dialogue.find(std.fmt.bufPrint(&buffer, "keeper_{d}", .{i}) catch unreachable),
        .walker => |i| self.dialogue.walker(i),
    } orelse return;
    self.talk = self.dialogue.begin(index, partner, &self.progress) orelse return;
    self.trading = null;
    self.shop = null;
    const there = self.partnerPosition(partner);
    const d = R.sub(there, self.player.feet);
    self.body_yaw = std.math.atan2(d[0], d[2]);
    if (partner == .walker) {
        self.life.chatting = partner.walker;
        self.life.walkers[partner.walker].camera.yaw = std.math.atan2(-d[0], -d[2]);
    }
}

fn endTalk(self: *Sandbox) void {
    self.talk = null;
    self.life.chatting = null;
}

/// Conversation input. A choice with an action ends the conversation and opens its panel.
pub fn talkKey(self: *Sandbox, key: Dialogue.Key) void {
    const session = if (self.talk) |*t| t else return;
    const scrap = self.wallet.scrap;
    const outcome = self.dialogue.key(session, key, &self.progress, &self.wallet);
    if (self.wallet.scrap > scrap) self.say("received {d} scrap", .{self.wallet.scrap - scrap});
    switch (outcome) {
        .talking => {},
        .ended => self.endTalk(),
        .action => |action| {
            const partner = session.partner;
            self.endTalk();
            switch (action) {
                .none => {},
                .trade => if (partner == .keeper) {
                    self.trading = partner.keeper;
                    self.trade_row = 0;
                },
                .upgrades => self.shop = .{ .kind = .upgrades },
                .wardrobe => self.shop = .{ .kind = .wardrobe },
            }
        },
    }
}

/// Player-facing wording for a failed purchase.
fn reason(err: anyerror) []const u8 {
    return switch (err) {
        error.NotEnoughScrap => "not enough scrap",
        error.NotEnoughParts => "not enough parts",
        error.MaxLevel => "already fully tuned",
        error.AlreadyOwned => "already owned",
        error.SoldOut => "sold out until dawn",
        error.NoParts => "no parts to sell",
        error.AlreadyMade => "already fabricated",
        error.NotEnoughLumen => "not enough lumen shards",
        error.NotEnoughRotors => "not enough rotor cores",
        error.NotEnoughAlloy => "not enough hive alloy",
        else => "the stall cannot do that",
    };
}

pub fn shopRows(self: *const Sandbox) u8 {
    const shop = self.shop orelse return 0;
    return switch (shop.kind) {
        .upgrades => Progress.upgrade_count,
        .wardrobe => wardrobe_rows,
        .fabricate => blk: {
            var buffer: [Fabricator.recipes.len]u8 = undefined;
            break :blk @intCast(Fabricator.onTab(@enumFromInt(shop.tab), &buffer).len);
        },
    };
}

/// Tinker panel input: buy the selected upgrade level, or buy (when not owned) and wear a suit.
pub fn shopKey(self: *Sandbox, key: ShopKey) void {
    const shop = if (self.shop) |*s| s else return;
    const rows = self.shopRows();
    switch (key) {
        .up => shop.row = (shop.row + rows - 1) % rows,
        .down => shop.row = (shop.row + 1) % rows,
        .left, .right => if (shop.kind == .fabricate) {
            const tabs: u8 = Fabricator.tab_count;
            shop.tab = if (key == .left) (shop.tab + tabs - 1) % tabs else (shop.tab + 1) % tabs;
            shop.row = 0;
        },
        .close => self.shop = null,
        .confirm => switch (shop.kind) {
            .upgrades => {
                const u: Progress.Upgrade = @enumFromInt(shop.row);
                self.progress.buy(u, &self.wallet) catch |err| return self.say("cannot upgrade: {s}", .{reason(err)});
                self.say("{s} now level {d}", .{ Progress.info[shop.row].name, self.progress.level(u) });
            },
            .fabricate => {
                var buffer: [Fabricator.recipes.len]u8 = undefined;
                const index = Fabricator.onTab(@enumFromInt(shop.tab), &buffer)[shop.row];
                const made = Fabricator.make(&self.progress, &self.wallet, index) catch |err| return self.say("cannot fabricate: {s}", .{reason(err)});
                var name_buffer: [24]u8 = undefined;
                const name = Fabricator.name(made, &name_buffer);
                switch (made) {
                    .vehicle => |d| {
                        self.garage.park(self.seed, spawn, self.catalog, d);
                        self.say("{s} is on its garage pad", .{name});
                    },
                    .fighter => {
                        self.hangar.place(self.seed, spawn, null, 0);
                        self.say("the Kestrel stands on its pad beyond the garage", .{});
                    },
                    .suit => |c| {
                        self.profile.clothing = c;
                        self.say("fabricated and wearing the {s}", .{name});
                    },
                    .armor => |a| {
                        self.profile.armor = a;
                        self.say("fabricated and wearing {s} armor", .{name});
                    },
                    .weapon => |w| {
                        self.combat.arsenals[0].active = w;
                        self.say("{s} ready: tool 5 to wield", .{name});
                    },
                }
                self.progress.setFlag("fabricated");
            },
            .wardrobe => {
                const c: Profile.Clothing = @enumFromInt(shop.row);
                if (!self.progress.owns(c)) self.progress.buySuit(c, &self.wallet) catch |err| return self.say("cannot buy: {s}", .{reason(err)});
                self.profile.clothing = c;
                self.say("wearing the {s}", .{@tagName(c)});
            },
        },
    }
}

fn stepLife(self: *Sandbox, dt: f32) void {
    if (!self.life.active) return;
    var others: [16]Physics.Vec3 = undefined;
    var n: usize = 0;
    if (self.seated == null) {
        others[n] = self.player.feet;
        n += 1;
    }
    for (self.guests) |g| if (g.active) {
        others[n] = g.player.feet;
        n += 1;
    };
    for (self.machines) |placed| if (placed.active) if (placed.vehicle) |v| if (n < others.len) {
        others[n] = self.physics.rigidPose(v.rigid).?.position;
        n += 1;
    };
    const graph = self.routes();
    self.life.step(&self.physics, &graph, self.road_revision, others[0..n], dt);
    for (self.bridges, 0..) |maybe, i| if (maybe) |bridge| if (bridge.closing and !self.bridgeOccupied(i)) self.removeBridge(i);
}

pub fn validateBridge(self: *const Sandbox, edge: District.Edge) !void {
    var edges: [District.max_bridges]District.Edge = undefined;
    const current = self.bridgeEdges(&edges);
    if (current.len == edges.len) return error.TooManyBridges;
    edges[current.len] = edge;
    try District.validate(&self.catalog.district, edges[0 .. current.len + 1]);
}

fn prepareBridge(self: *Sandbox, edge: District.Edge, slot: usize) !PlacedBridge {
    const parts = try District.bridgeParts(&self.catalog.district, District.span(&self.catalog.district, edge), edge.style);
    return .{ .edge = edge, .parts = parts, .collider = try District.collider(self.allocator, &self.physics, parts.slice(), bridge_flag | @as(u32, @intCast(slot))) };
}

pub fn addBridge(self: *Sandbox, edge: District.Edge) !u8 {
    try self.validateBridge(edge);
    const slot = for (self.bridges, 0..) |bridge, i| {
        if (bridge == null) break i;
    } else return error.TooManyBridges;
    // A failed allocation leaves the graph and existing geometry untouched.
    self.bridges[slot] = try self.prepareBridge(edge, slot);
    self.road_revision += 1;
    self.progress.setFlag("bridge_built");
    return @intCast(slot);
}

pub fn removeBridge(self: *Sandbox, slot: usize) void {
    if (slot >= self.bridges.len) return;
    if (self.bridges[slot]) |bridge| {
        self.physics.destroyMesh(bridge.collider);
        self.road_revision += 1;
    }
    self.bridges[slot] = null;
}

pub fn tree(self: *const Sandbox, index: usize) *const Arbor.Tree {
    return if (index == 0) &self.test_arbor_sap else &self.catalog.arbors[index - 1].tree;
}

pub fn treeOrigin(self: *const Sandbox, index: usize) Physics.Vec3 {
    return if (index == 0) self.arbor_origin.? else self.generated_origins[index - 1];
}

/// Resolve by physical proximity, so copies and moving taps reconnect to the tree they touch.
/// The lowest stable tree ID wins an exact tie. No arbitrary stored index can supply a remote tap.
pub fn sapAttachment(self: *const Sandbox, position: Physics.Vec3) ?SapLink {
    var best: ?SapLink = null;
    var distance: f32 = 4;
    for (0..sap_tree_count) |i| {
        if (self.tree(i).attachment(R.sub(position, self.treeOrigin(i)), 4)) |hit| {
            if (hit.distance <= distance and (best == null or hit.distance < distance)) {
                best = .{ .tree = @intCast(i), .node = hit.node };
                distance = hit.distance;
            }
        }
    }
    return best;
}

fn distributeSap(self: *Sandbox) void {
    const capacity = max_machines * Blueprint.max_devices;
    var requests: [sap_tree_count][capacity]Sap.Request = undefined;
    var refs: [sap_tree_count][capacity]DeviceRef = undefined;
    var counts: [sap_tree_count]usize = @splat(0);
    self.tap_links = @splat(@splat(null));
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        for (placed.blueprint.devices[0..placed.blueprint.device_count], 0..) |def, d| {
            if (def.kind != .sap_tap) continue;
            const link = self.sapAttachment(placed.machine.devicePosition(d)) orelse continue;
            self.tap_links[m][d] = link;
            placed.machine.connected_taps[d] = true;
        }
    }
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        for (self.tap_links[m], 0..) |maybe_link, d| {
            const link = maybe_link orelse continue;
            const n = counts[link.tree];
            requests[link.tree][n] = .{ .node = link.node, .watts = placed.machine.sapRequest(d) };
            refs[link.tree][n] = .{ .machine = @intCast(m), .device = @intCast(d) };
            counts[link.tree] += 1;
        }
    }
    for (counts, 0..) |count, t| {
        self.sap_stats[t] = Sap.allocate(self.tree(t), requests[t][0..count]);
        for (requests[t][0..count], refs[t][0..count]) |request, ref| self.machines[ref.machine].machine.grantSap(ref.device, request.granted);
    }
}

fn hold(self: *Sandbox, index: u32) void {
    self.held = index;
    self.physics.setGravityScale(self.crates[index], 0);
}

pub fn release(self: *Sandbox) void {
    if (self.held) |i| self.physics.setGravityScale(self.crates[i], 1);
    self.held = null;
}

/// Regenerates scatter for the 3×3 chunks around the eye when the eye changes chunk.
/// Deterministic, so it agrees with what the streamer renders without sharing its buffers.
fn refreshNearby(self: *Sandbox, eye: math.Vec3) void {
    const center = Key.fromPosition(eye.x(), eye.z());
    if (self.nearby_center) |c| if (Key.eql(c, center)) return;
    self.nearby_center = center;
    for (&self.nearby, 0..) |*chunk, i| {
        chunk.key = .{ .x = center.x + @as(i32, @intCast(i % 3)) - 1, .z = center.z + @as(i32, @intCast(i / 3)) - 1 };
        chunk.count = if (chunk.key.valid()) Scatter.generate(self.seed, chunk.key, &chunk.objects) else 0;
    }
}

/// Nearest crate, machine device or structure, or (when `relics`) uncollected relic along
/// the view ray within `max_distance`. Terrain and machine structure occlude what is behind.
pub fn pick(self: *const Sandbox, eye: math.Vec3, forward: math.Vec3, max_distance: f32, relics: bool, stalls: bool) Target {
    const origin: Physics.Vec3 = .{ eye.x(), eye.y(), eye.z() };
    const dir: Physics.Vec3 = .{ forward.x(), forward.y(), forward.z() };
    var best: Target = .none;
    var best_distance = self.terrainDistance(origin, dir, max_distance);
    const ignore: Physics.Body = if (self.held) |i| self.crates[i] else .none;
    if (self.physics.raycast(origin, dir, best_distance, ignore)) |hit| {
        best_distance = hit.distance;
        // Crates carry their slot; machine devices and vehicle chassis (→ seat) carry machine
        // and device; structure parts carry their machine.
        const machine: u8 = @intCast((hit.user >> 8) & 0xFF);
        best = if (hit.user & bridge_flag != 0) .{ .bridge = @intCast(hit.user & 0xff) } else if (hit.user & world_flag != 0) .none else if (hit.user & machine_flag == 0) .{ .prop = hit.user } else if (hit.user & part_flag != 0) .{ .structure = machine } else .{ .device = .{ .machine = machine, .device = @intCast(hit.user & 0xFF) } };
    }
    // Pedestrians, as a body-sized box (hands only).
    if (stalls and self.life.active) for (self.life.walkers, 0..) |w, i| {
        const hit = Physics.rayBox(origin, dir, R.add(w.player.feet, .{ 0, 0.9, 0 }), .{ 0.4, 0.9, 0.4 }) orelse continue;
        if (hit.distance >= best_distance and hit.distance > 0) continue;
        best = .{ .walker = @intCast(i) };
        best_distance = hit.distance;
    };
    // Market stalls: the space under each canopy (hands only).
    if (stalls) for (0..Market.stall_count) |i| {
        const hit = Physics.rayBox(origin, dir, R.add(self.stallPosition(i), .{ 0, 1.75, 0 }), .{ 2.4, 1.75, 2 }) orelse continue;
        if (hit.distance >= best_distance and hit.distance > 0) continue;
        best = .{ .stall = @intCast(i) };
        best_distance = hit.distance;
    };
    if (relics) for (self.nearby) |chunk| for (chunk.objects[0..chunk.count]) |object| {
        if (object.kind != .relic) continue;
        const ref = Modifications.ObjectRef.of(chunk.key, object.local_id);
        const s = object.transform.scale;
        const p = object.transform.position;
        // Relic cube spans y ∈ [0, 2] × scale in model space.
        const hit = Physics.rayBox(origin, dir, .{ p[0], p[1] + s, p[2] }, .{ 0.5 * s, s, 0.5 * s }) orelse continue;
        if (hit.distance >= best_distance or self.modifications.contains(ref)) continue;
        best = .{ .relic = .{ .ref = ref, .position = p } };
        best_distance = hit.distance;
    };
    return best;
}

fn terrainDistance(self: *const Sandbox, origin: Physics.Vec3, dir: Physics.Vec3, max_distance: f32) f32 {
    var t: f32 = 0;
    while (t < max_distance) : (t += 0.1) {
        if (origin[1] + dir[1] * t < Terrain.surface(self.seed, origin[0] + dir[0] * t, origin[2] + dir[2] * t).height) return t;
    }
    return max_distance;
}

pub fn cratePosition(self: *const Sandbox, index: u32) Physics.Vec3 {
    return self.physics.position(self.crates[index]).?;
}

pub fn findDevice(self: *const Sandbox, machine: usize, id: []const u8) ?DeviceRef {
    const d = self.machines[machine].blueprint.findDevice(id) orelse return null;
    return .{ .machine = @intCast(machine), .device = d };
}

pub fn devicePosition(self: *const Sandbox, ref: DeviceRef) Physics.Vec3 {
    const placed = &self.machines[ref.machine];
    return self.physics.position(placed.devices[ref.device]) orelse placed.machine.devicePosition(ref.device);
}

/// Render view of crates, machines, and (with the build or wire tool) previews and wires.
pub fn publishProps(self: *const Sandbox, out: []World.Prop) usize {
    if (out.len == 0) return 0;
    out[0] = .{ .mesh = self.catalog.content.district, .transform = .{}, .tint = .{ 1, 1, 1, 1 } };
    var n: usize = 1;
    for (self.bridges) |maybe| if (maybe) |bridge| {
        for (bridge.parts.slice()) |p| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = p.center }, .tint = p.color ++ [_]f32{1}, .size = p.size, .rotation = p.rotation };
            n += 1;
        }
    };
    if (self.arbor_origin) |origin| if (n < out.len) {
        out[n] = .{ .mesh = self.catalog.content.test_arbor, .transform = .{ .position = origin }, .tint = .{ 1, 1, 1, 1 }, .lod = self.catalog.content.test_arbor_lod, .lod_distance = 450 };
        n += 1;
    };
    for (&self.catalog.arbors, self.generated_origins, 0..) |*asset, origin, i| {
        if (n == out.len) return n;
        out[n] = .{ .mesh = asset.mesh, .transform = .{ .position = origin }, .tint = .{ 1, 1, 1, 1 }, .lod = asset.lod, .lod_distance = 600 };
        n += 1;
        const health = self.sap_stats[i + 1].satisfaction;
        const color = asset.tree.genome.lumen;
        // Low trunk lumen marks where players can tap; shelf markers show stress in the crown.
        const markers: usize = 1 + asset.tree.platform_count;
        for (0..markers) |marker| {
            if (n == out.len) return n;
            const local: Physics.Vec3 = if (marker == 0) .{ asset.tree.genome.base_radius + 0.3, 2, 0 } else R.add(asset.tree.platforms[marker - 1].center, .{ 0, 2, 0 });
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = R.add(origin, local) }, .size = .{ 0.8, 2, 0.8 }, .tint = @import("../render/Material.zig").emissive(.{ color[0] * (0.25 + 0.75 * health), color[1] * (0.25 + 0.75 * health), color[2] * (0.25 + 0.75 * health), 1 }, health) };
            n += 1;
        }
    }
    for (0..max_crates) |i| {
        if (!self.crateLive(i)) continue;
        if (n == out.len) return n;
        const index: u32 = @intCast(i);
        const glow: f32 = if (self.held == index) 1.35 else if (self.target == .prop and self.target.prop == index) 1.18 else 1;
        out[n] = .{ .mesh = self.catalog.content.crate, .transform = .{ .position = self.cratePosition(index) }, .tint = .{ glow, glow, glow, 1 } };
        n += 1;
    }
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        const bp = &placed.blueprint;
        if (placed.vehicle) |vehicle| {
            n = self.publishVehicle(placed, vehicle, m, out, n);
            continue;
        }
        const rotation = placed.machine.rotation;
        const structure_glow: f32 = if (self.tools.tool == .build and self.target == .structure and self.target.structure == m) 1.25 else 1;
        for (bp.parts[0..bp.part_count]) |part| {
            if (n == out.len) return n;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = placed.machine.worldOffset(part.offset) }, .tint = .{ part.color[0] * structure_glow, part.color[1] * structure_glow, part.color[2] * structure_glow, 1 }, .size = part.size, .rotation = rotation };
            n += 1;
        }
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (!def.hasBody()) continue;
            if (n == out.len) return n;
            const targeted = self.target == .device and self.target.device.machine == m and self.target.device.device == d;
            const selected = if (self.tools.wire_from) |w| w.machine == m and w.device == d else false;
            const glow: f32 = if (selected) 1.6 else if (targeted) 1.3 else structure_glow;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = self.devicePosition(.{ .machine = @intCast(m), .device = @intCast(d) }) }, .tint = deviceTint(&placed.machine, d, glow), .size = def.size, .rotation = rotation };
            n += 1;
        }
    }
    // Every walking body is published; each player's own first-person view hides its owner tag.
    if (self.seated == null and self.player.mode == .walk and n < out.len) {
        n = avatar(if (self.creator.open) self.creator.draft else self.profile, .{ .feet = self.player.feet, .yaw = self.body_yaw, .walk_phase = self.walk_phase, .walk_amount = self.walk_amount, .motion = self.player.motion, .time = @as(f32, @floatFromInt(self.tick)) / 60 }, self.specials.stance(0) orelse self.combat.arsenals[0].stance(), 1, self.catalog.content.block, out, n);
    }
    const night = Sky.at(Sky.timeOfDay(self.tick)).night;
    n = self.life.publish(&self.physics, self.catalog, night, out, n);
    // The skyline at night: warning beacons on the spires, and columns of lit windows on each
    // facade of the main tier that read as glass by day and glow warm after dusk.
    const Material = @import("../render/Material.zig");
    // Lit rails outline every road after dusk, district and player-built alike.
    var all_edges: [District.base_edge_count + District.max_bridges]District.Edge = undefined;
    @memcpy(all_edges[0..District.base_edge_count], &self.catalog.district.edges);
    var edge_count: usize = District.base_edge_count;
    for (self.bridges) |maybe| if (maybe) |bridge| {
        all_edges[edge_count] = bridge.edge;
        edge_count += 1;
    };
    for (all_edges[0..edge_count]) |edge| {
        const s = District.span(&self.catalog.district, edge);
        var strings: [@import("../procedural/Bridges.zig").max_lights]@import("../procedural/Bridges.zig").Light = undefined;
        for (@import("../procedural/Bridges.zig").lights(&self.catalog.district, s, edge.style, &strings)) |l| {
            if (n == out.len) break;
            const seg: District.Span = .{ .a = l.a, .b = l.b };
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = seg.point(0.5) }, .size = .{ 0.3, 0.3, seg.length() }, .rotation = seg.rotation(), .tint = Material.emissive(.{ 1.0, 0.88, 0.62, 1 }, night) };
            n += 1;
        }
        const q = s.rotation();
        for ([_]f32{ -6.75, 6.75 }) |x| {
            if (n == out.len) break;
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = R.add(s.point(0.5), R.rotate(q, .{ x, 1.15, 0 })) }, .size = .{ 0.22, 0.12, s.length() }, .rotation = q, .tint = Material.emissive(.{ 0.35 + 0.4 * night, 0.85, 0.95, 1 }, 0.15 + 0.85 * night) };
            n += 1;
        }
    }
    for (self.catalog.district.buildings[0..self.catalog.district.building_count], 0..) |b, k| {
        if (n == out.len) break;
        out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = b.beacon() }, .size = .{ 1.4, 1.4, 1.4 }, .tint = Material.emissive(.{ 1, 0.25, 0.18, 1 }, 0.35 + 0.65 * night) };
        n += 1;
        const top = b.base[1] + (b.roof - b.base[1]) * (if (b.tiers > 1) @as(f32, 0.5) else 0.92);
        const bottom = b.base[1] + 6;
        const lit = night * (0.55 + 0.45 * @as(f32, @floatFromInt((k * 7) % 5)) / 4);
        const glass: [4]f32 = .{ 0.55 + 0.45 * night, 0.62 + 0.25 * night, 0.66 - 0.16 * night, 1 };
        for ([_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |face| for ([_]f32{ -0.45, 0.2 }) |along| {
            if (n == out.len) break;
            const across = if (face[0] != 0) b.half[1] else b.half[0];
            const center: Physics.Vec3 = if (face[0] != 0)
                .{ b.base[0] + face[0] * (b.half[0] + 0.08), (top + bottom) / 2, b.base[2] + along * across }
            else
                .{ b.base[0] + along * across, (top + bottom) / 2, b.base[2] + face[1] * (b.half[1] + 0.08) };
            const size: [3]f32 = if (face[0] != 0) .{ 0.2, top - bottom, across * 0.4 } else .{ across * 0.4, top - bottom, 0.2 };
            out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = center }, .size = size, .tint = Material.emissive(glass, lit) };
            n += 1;
        };
    }
    // A keeper behind each stall's counter, facing its plaza.
    for (0..Market.stall_count) |i| if (n < out.len) {
        const stall = self.stallPosition(i);
        const plaza = self.catalog.district.nodes[Market.stall_plazas[i]].position;
        const keeper: Profile = .{ .presentation = if (i % 2 == 0) .masculine else .feminine, .outfit = @intCast((i * 3 + 1) % Profile.outfit_colors.len), .accent = @intCast((i + 1) % Profile.accent_colors.len), .hair_style = @enumFromInt(i % 5), .skin = @intCast((i * 3) % Profile.skin_tones.len) };
        const toward = R.sub(plaza, stall);
        const keeper_index = n;
        n += Avatar.build(keeper, .{ .feet = self.keeperPosition(i), .yaw = std.math.atan2(toward[0], toward[2]) }, self.catalog.content.block, out[n..]);
        if (n > keeper_index) out[keeper_index].character.?.id = @intCast(4 + i);
    };
    for (self.guests, 0..) |g, i| if (g.active and n < out.len) {
        n = avatar(g.profile, .{ .feet = g.player.feet, .yaw = g.body_yaw, .walk_phase = g.walk_phase, .walk_amount = g.walk_amount, .motion = g.player.motion }, self.specials.stance(i + 1) orelse self.combat.arsenals[i + 1].stance(), @intCast(i + 2), self.catalog.content.block, out, n);
    };
    n = Frontier.publish(self, out, n);
    return Build.publish(self, out, n);
}

fn avatar(profile: Profile, pose: Avatar.Pose, stance: Combat.Stance, owner: u8, block: Catalog.MeshHandle, out: []World.Prop, start: usize) usize {
    const end = start + Avatar.build(profile, stance.apply(pose), block, out[start..]);
    for (out[start..end]) |*part| {
        part.owner = owner;
        part.character.?.id = owner - 1;
    }
    return end;
}

/// Static and vehicle-mounted lamps share the same power-driven emissive material.
fn deviceTint(machine: *const Machine, d: usize, highlight: f32) [4]f32 {
    const def = machine.blueprint.devices[d];
    var glow = highlight;
    if (((def.kind == .generator or def.kind == .sap_tap) and machine.outputs[d][0] == 0) or (def.kind == .actuator and machine.satisfaction(d) == 0)) glow *= 0.45;
    const emission: f32 = if (def.kind == .lamp) machine.outputs[d][2] else 0;
    if (def.kind == .lamp) glow *= 0.2 + 0.8 * std.math.clamp(emission, 0, 1);
    return @import("../render/Material.zig").emissive(.{ def.color[0] * glow, def.color[1] * glow, def.color[2] * glow, 1 }, emission);
}

/// Chassis parts and devices follow the rigid pose; wheels follow the suspension and spin.
fn publishVehicle(self: *const Sandbox, placed: *const Placed, vehicle: Vehicle, m: usize, out: []World.Prop, start: usize) usize {
    var n = start;
    const pose = self.physics.rigidPose(vehicle.rigid).?;
    const frame: Machine = blk: {
        var copy = placed.machine;
        copy.origin = pose.position;
        copy.rotation = pose.orientation;
        break :blk copy;
    };
    const bp = &placed.blueprint;
    const glow: f32 = if (self.target == .device and self.target.device.machine == m) 1.2 else 1;
    for (bp.parts[0..bp.part_count]) |part| {
        if (n == out.len) return n;
        out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = frame.worldOffset(part.offset) }, .tint = .{ part.color[0] * glow, part.color[1] * glow, part.color[2] * glow, 1 }, .size = part.size, .rotation = pose.orientation };
        n += 1;
    }
    for (bp.devices[0..bp.device_count], 0..) |def, d| {
        if (!def.visible()) continue;
        if (n == out.len) return n;
        out[n] = .{ .mesh = self.catalog.content.block, .transform = .{ .position = frame.devicePosition(d) }, .tint = deviceTint(&placed.machine, d, glow), .size = def.size, .rotation = pose.orientation };
        n += 1;
    }
    for (0..vehicle.wheel_count) |i| {
        if (n == out.len) return n;
        const wheel = vehicle.wheelPose(&self.physics, i);
        const r = vehicle.wheels[i].radius;
        out[n] = .{ .mesh = self.catalog.content.wheel, .transform = .{ .position = wheel.position }, .tint = .{ 1, 1, 1, 1 }, .size = .{ 0.32, r * 2, r * 2 }, .rotation = wheel.orientation };
        n += 1;
    }
    return n;
}

pub fn save(self: *const Sandbox, allocator: std.mem.Allocator, camera: Camera) ![]u8 {
    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var crates: [max_crates]Save.PropState = undefined;
    var crate_count: usize = 0;
    for (0..max_crates) |i| {
        if (!self.crateLive(i)) continue;
        crates[crate_count] = .{ .id = @intCast(i), .position = self.cratePosition(@intCast(i)), .velocity = self.physics.velocity(self.crates[i]).? };
        crate_count += 1;
    }
    var machines: [max_machines]Save.MachineState = undefined;
    var machine_count: usize = 0;
    for (&self.machines, 0..) |*placed, m| {
        if (!placed.active) continue;
        var state: Save.MachineState = .{
            .slot = @intCast(m),
            .blueprint = try placed.blueprint.toDoc(arena),
            .origin = placed.machine.origin,
            .yaw = placed.yaw,
            .workshop = placed.workshop,
            .states = placed.machine.states(),
            .kit = if (placed.kit) |k| @intFromEnum(k) else null,
            .shrine = placed.shrine,
        };
        if (placed.vehicle) |vehicle| {
            const pose = self.physics.rigidPose(vehicle.rigid).?;
            const motion = self.physics.rigidVelocity(vehicle.rigid).?;
            state.body = .{ .position = pose.position, .orientation = pose.orientation, .linear = motion.linear, .angular = motion.angular };
        }
        machines[machine_count] = state;
        machine_count += 1;
    }
    var bridge_edges: [District.max_bridges]District.Edge = undefined;
    return Save.encode(allocator, .{
        .seed = self.seed,
        .bridges = self.openBridgeEdges(&bridge_edges),
        .tick = self.tick,
        .player = .{ .feet = self.player.feet, .yaw = camera.yaw, .pitch = camera.pitch, .mode = self.player.mode },
        .profile = self.profile.toDoc(),
        .props = crates[0..crate_count],
        .collected = self.modifications.slice(),
        .machines = machines[0..machine_count],
        .wallet = self.wallet,
        .progress = try self.progress.toDoc(arena),
        .fighter = if (self.hangar.fighter) |f| .{ .position = .{ f.body.pos.x, f.body.pos.y, f.body.pos.z }, .yaw = f.heading() } else null,
        .cars = cars: {
            var list: std.ArrayList(Save.CarState) = .empty;
            for (self.garage.cars) |slot| if (slot) |c| {
                const p = c.flyer.body.pos;
                try list.append(arena, .{ .design = c.design, .position = .{ p.x, p.y, p.z }, .yaw = c.flyer.heading() });
            };
            break :cars list.items;
        },
        .mods = mods: {
            const refs = try arena.alloc(Save.ModState, self.mod_count);
            for (refs, self.mods[0..self.mod_count]) |*out, *m| out.* = .{ .name = try arena.dupe(u8, m.name()), .version = try std.fmt.allocPrint(arena, "{d}.{d}.{d}", .{ m.version.major, m.version.minor, m.version.patch }) };
            break :mods refs;
        },
        .market_day = self.market.day,
        .market_stock = stock: {
            const rows = try arena.alloc([Market.ware_count]u8, Market.stall_count);
            for (rows, self.market.stalls) |*row, stall| row.* = stall.stock;
            break :stock rows;
        },
        .prefabs = prefabs: {
            const docs = try arena.alloc(Blueprint.Doc, self.prefab_count);
            for (docs, self.prefabs[0..self.prefab_count]) |*doc, *bp| doc.* = try bp.toDoc(arena);
            break :prefabs docs;
        },
    });
}

/// Rebuilds the world from a save. Every blueprint is re-validated, every machine state is
/// restored into a scratch copy, and body capacity is checked before anything is torn down;
/// on any error the session is unchanged.
pub fn restore(self: *Sandbox, allocator: std.mem.Allocator, bytes: []const u8, camera: *Camera) !void {
    const parsed = try Save.decode(allocator, bytes, self.seed, max_crates, max_machines);
    defer parsed.deinit();
    const doc = parsed.value;
    const profile = try Profile.fromDoc(doc.profile);
    const progress = Progress.fromDoc(doc.progress) catch return error.InvalidSave;
    const blueprints = try allocator.alloc(Blueprint, doc.machines.len);
    defer allocator.free(blueprints);
    var bodies: usize = doc.props.len;
    var rigids: usize = 0;
    var workshops: usize = 0;
    for (doc.machines, blueprints) |state, *bp| {
        bp.* = try Blueprint.fromDoc(state.blueprint);
        if ((state.body != null) != (bp.vehicle != null)) return error.MachineMismatch;
        var scratch = Machine.init(bp, state.origin);
        try scratch.restore(state.states);
        workshops += @intFromBool(state.workshop);
        if (bp.vehicle != null) {
            rigids += 1;
        } else {
            bodies += bp.part_count;
            for (bp.devices[0..bp.device_count]) |d| bodies += @intFromBool(d.hasBody());
        }
    }
    if (bodies > Physics.max_bodies or rigids + self.life.rigidCount() > Physics.max_rigids or workshops > 1) return error.InvalidSave;
    if (doc.prefabs.len > max_prefabs) return error.InvalidSave;
    var prefabs: [max_prefabs]Blueprint = undefined;
    for (doc.prefabs, prefabs[0..doc.prefabs.len]) |source, *bp| bp.* = try Blueprint.fromDoc(source);

    var market = self.market;
    try market.restore(doc.market_day, doc.market_stock, doc.tick);
    try District.validate(&self.catalog.district, doc.bridges);
    // Stage all allocating bridge work before committing any saved state.
    var staged: [District.max_bridges]?PlacedBridge = @splat(null);
    errdefer for (staged) |maybe| if (maybe) |bridge| self.physics.destroyMesh(bridge.collider);
    for (doc.bridges, 0..) |edge, i| staged[i] = try self.prepareBridge(edge, i);

    // Validated: tear down and rebuild.
    self.release();
    self.seated = null;
    self.tools = .{};
    for (0..max_machines) |m| self.removeMachine(@intCast(m));
    for (0..max_crates) |i| if (self.crateLive(i)) self.removeCrate(@intCast(i));
    for (doc.props) |p| try self.spawnCrateAt(p.id, p.position, p.velocity);
    for (doc.machines, blueprints) |state, bp| {
        const m = try self.spawnMachine(state.slot, bp, state.origin, @intCast(state.yaw), state.workshop);
        const placed = &self.machines[m];
        try placed.machine.restore(state.states);
        if (state.kit) |k| placed.kit = @enumFromInt(k);
        if (state.shrine) |k| placed.shrine = k;
        if (state.workshop) self.workshop = m;
        if (placed.vehicle) |vehicle| {
            const body = state.body.?;
            self.physics.setRigidState(vehicle.rigid, .{ .position = body.position, .orientation = body.orientation }, body.linear, body.angular);
        }
        for (bp.devices[0..bp.device_count], 0..) |def, d| {
            if (def.kind == .actuator) self.physics.setTransform(placed.devices[d], placed.machine.devicePosition(d), .{ 0, 0, 0 });
        }
    }
    for (0..District.max_bridges) |i| self.removeBridge(i);
    self.bridges = staged;
    staged = @splat(null);
    @memcpy(self.prefabs[0..doc.prefabs.len], prefabs[0..doc.prefabs.len]);
    self.prefab_count = doc.prefabs.len;
    self.modifications.clear();
    for (doc.collected) |ref| _ = try self.modifications.remove(ref);
    self.profile = profile;
    self.creator = .{ .confirmed = true };
    self.player = .{ .feet = doc.player.feet, .mode = doc.player.mode };
    self.body_yaw = doc.player.yaw;
    camera.yaw = doc.player.yaw;
    camera.pitch = std.math.clamp(doc.player.pitch, -1.5, 1.5);
    camera.position = self.player.eye();
    self.tick = doc.tick;
    for (&self.shrines, 0..) |*shrine, k| {
        shrine.machine = null;
        shrine.completed = false;
        for (self.machines, 0..) |placed, m| if (placed.active and placed.shrine == @as(?u8, @intCast(k))) {
            shrine.machine = @intCast(m);
            const sealed = placed.blueprint.findDevice("sealed") orelse continue;
            shrine.completed = placed.machine.outputs[sealed][1] > 0.5 or placed.machine.state[sealed] > 0.5;
        };
    }
    self.market = market;
    self.wallet = doc.wallet;
    self.progress = progress;
    self.endTalk();
    self.shop = null;
    self.trading = null;
    self.target = .none;
    // Saves remember which mods they were made with; a missing or different mod is reported, not
    // fatal (its blueprints are in the save; its scripts output 0 until it is installed).
    self.mod_warnings = 0;
    for (doc.mods) |m| {
        const have = self.modInstalled(m.name);
        const want = Mod.Version.parse(m.version) catch null;
        if (have == null or want == null or !have.?.eql(want.?)) {
            self.mod_warnings += 1;
            self.say("save used mod {s} {s}: {s}", .{ m.name, m.version, if (have == null) "not installed" else "different version" });
        }
    }
    self.press = null;
    // City life and guests are not saved: traffic restarts on the restored roads, and guests
    // rejoin beside the restored P1.
    self.road_revision += 1;
    if (self.life.active) self.enableLife();
    for (&self.guests, 0..) |*g, i| if (g.active) self.respawnGuest(i);
    self.sap_stats = @splat(.{});
    self.tap_links = @splat(@splat(null));
    Frontier.refresh(self);
    for (doc.cars) |c| if (self.progress.ownsVehicle(c.design)) self.garage.place(self.seed, spawn, self.catalog, c.design, c.position, c.yaw);
    if (doc.fighter) |f| if (self.progress.fighter) self.hangar.place(self.seed, spawn, f.position, f.yaw);
}

pub fn testSandbox(sandbox: *Sandbox, catalog: *Catalog, camera: *Camera) !void {
    try catalog.load(std.testing.allocator);
    errdefer catalog.deinit(std.testing.allocator);
    try sandbox.init(std.testing.allocator, 310399555161, catalog, camera);
}

fn run(sandbox: *Sandbox, camera: *Camera, input: Input, actions: Actions, steps: usize) !void {
    try sandbox.step(camera, input, actions, 1.0 / 60.0);
    for (1..steps) |_| try sandbox.step(camera, input, .{}, 1.0 / 60.0);
}

test "walk to a crate, carry it, drop it, save, disturb, and reload the modification" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();

    // Settle: the player stands on the terrain and crates rest without sinking.
    try run(&sandbox, &camera, .{}, .{}, 120);
    try std.testing.expect(sandbox.player.grounded);
    const ground = Terrain.surface(sandbox.seed, sandbox.player.feet[0], sandbox.player.feet[2]).height;
    try std.testing.expectApproxEqAbs(ground, sandbox.player.feet[1], 0.001);
    const start = sandbox.cratePosition(1);

    // Walk forward until the middle crate blocks the player.
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 150);
    try std.testing.expect(sandbox.player.feet[2] < start[2]);
    // Look slightly down at the crate and pick it up.
    camera.pitch = -0.35;
    try run(&sandbox, &camera, .{}, .{}, 2);
    try std.testing.expect(sandbox.target == .prop);
    const picked = sandbox.target.prop;
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 1);
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);

    // Turn around over half a second, carry it, and drop it behind the spawn.
    camera.pitch = 0;
    for (0..30) |_| {
        camera.yaw += std.math.pi / 30.0;
        try run(&sandbox, &camera, .{}, .{}, 1);
    }
    try std.testing.expectEqual(@as(?u32, picked), sandbox.held);
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 180);
    try std.testing.expectEqual(@as(?u32, null), sandbox.held);
    const dropped = sandbox.cratePosition(picked);
    try std.testing.expect(dropped[2] < start[2] - 3);
    const rest = Terrain.surface(sandbox.seed, dropped[0], dropped[2]).height;
    try std.testing.expect(dropped[1] >= rest + 0.39);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);

    const saved_sky = @import("../engine/Sky.zig").timeOfDay(sandbox.tick);
    sandbox.tick += @import("../engine/Sky.zig").day_ticks / 2;
    // Disturb the world, then reload the saved state.
    sandbox.physics.setTransform(sandbox.crates[picked], .{ 50, 40, 50 }, .{ 0, 0, 0 });
    _ = try sandbox.modifications.remove(.{ .x = 0, .z = 0, .id = 7 });
    sandbox.player.feet = .{ 100, 100, 100 };
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqual(saved_sky, @import("../engine/Sky.zig").timeOfDay(sandbox.tick));
    try std.testing.expectEqualDeep(dropped, sandbox.cratePosition(picked));
    try std.testing.expect(!sandbox.modifications.contains(.{ .x = 0, .z = 0, .id = 7 }));
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi), camera.yaw, 0.0001);

    // A save from another seed is rejected without changing the session.
    var other: Sandbox = undefined;
    var other_camera: Camera = .{};
    try other.init(std.testing.allocator, 42, &catalog, &other_camera);
    defer other.deinit();
    try std.testing.expectError(error.SeedMismatch, other.restore(std.testing.allocator, bytes, &other_camera));
}

test "salvage removes a relic by stable ID, survives regeneration, and round-trips through a save" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    sandbox.player.mode = .fly;

    // Find a relic in the spawn chunk and aim at it from two meters away.
    var objects: [Scatter.capacity]Scatter.Object = undefined;
    const key = Key.fromPosition(spawn[0], spawn[2]);
    const count = Scatter.generate(sandbox.seed, key, &objects);
    const relic = for (objects[0..count]) |o| {
        if (o.kind == .relic) break o;
    } else return error.SkipZigTest;
    const p = relic.transform.position;
    camera.position = math.vec3(p[0], p[1] + relic.transform.scale, p[2] - 2 - relic.transform.scale);
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .relic);
    try std.testing.expectEqual(relic.local_id, sandbox.target.relic.ref.id);
    try run(&sandbox, &camera, .{}, .{ .secondary = true }, 1);
    const ref = Modifications.ObjectRef.of(key, relic.local_id);
    try std.testing.expect(sandbox.modifications.contains(ref));
    // Once removed it can no longer be targeted.
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target != .relic or sandbox.target.relic.ref.id != relic.local_id);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sandbox.modifications.clear();
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expect(sandbox.modifications.contains(ref));
    // Regeneration reproduces the same object at the same ID, so the removal still applies.
    var again: [Scatter.capacity]Scatter.Object = undefined;
    try std.testing.expectEqual(count, Scatter.generate(sandbox.seed, key, &again));
    try std.testing.expect(for (again[0..count]) |o| {
        if (o.local_id == relic.local_id) break std.meta.eql(o.transform.position, p);
    } else false);
}

/// Points the camera at a world position.
fn aimAt(camera: *Camera, point: Physics.Vec3) void {
    const dx = point[0] - camera.position.x();
    const dy = point[1] - camera.position.y();
    const dz = point[2] - camera.position.z();
    camera.yaw = std.math.atan2(dx, dz);
    camera.pitch = std.math.atan2(dy, @sqrt(dx * dx + dz * dz));
}

fn standAt(sandbox: *Sandbox, camera: *Camera, feet: Physics.Vec3) !void {
    sandbox.player = .{ .feet = feet };
    camera.position = sandbox.player.eye();
    try run(sandbox, camera, .{}, .{}, 30);
}

test "powered door blocks, opens from its button, lets the player through, and reloads open" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const door = sandbox.findDevice(0, "door").?;
    const button = sandbox.findDevice(0, "button").?;
    const origin = sandbox.machines[0].machine.origin;

    // Closed: walking toward the doorway from the -z side stops at the door.
    try standAt(&sandbox, &camera, .{ origin[0], origin[1] + 0.1, origin[2] - 3 });
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try std.testing.expect(sandbox.player.feet[2] < origin[2] - 0.2);

    // Press the button: latch → logic → actuator, then 2.9 m at 1.5 m/s.
    aimAt(&camera, sandbox.devicePosition(button));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device and sandbox.target.device.device == button.device);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 150);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sandbox.machines[0].machine.state[door.device], 0.0001);
    try std.testing.expectApproxEqAbs(origin[0] + 2.9, sandbox.devicePosition(door)[0], 0.001);

    // Walk through the open doorway.
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 90);
    try std.testing.expect(sandbox.player.feet[2] > origin[2] + 1);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    // Close it by hand, then reload: the door and its latch come back open.
    try sandbox.machines[0].machine.restore(&[_]f32{0} ** 6);
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqual(@as(f32, 1), sandbox.machines[0].machine.state[door.device]);
    try std.testing.expectApproxEqAbs(origin[0] + 2.9, sandbox.devicePosition(door)[0], 0.001);
    // Stepping keeps it open: the restored latch still drives the target.
    try run(&sandbox, &camera, .{}, .{}, 30);
    try std.testing.expectEqual(@as(f32, 1), sandbox.machines[0].machine.state[door.device]);
}

test "elevator carries the player to the landing with the same machine APIs" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const platform = sandbox.findDevice(1, "platform").?;
    const call_low = sandbox.findDevice(1, "call_low").?;
    const origin = sandbox.machines[1].machine.origin;

    // Stand on the platform and press the call button on its post.
    try standAt(&sandbox, &camera, .{ origin[0], origin[1] + 0.3, origin[2] });
    try std.testing.expect(sandbox.player.support.eql(sandbox.machines[1].devices[platform.device]));
    aimAt(&camera, sandbox.devicePosition(call_low));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device);
    // 3.9 m at 1.2 m/s ≈ 3.25 s plus signal latency.
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 220);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sandbox.machines[1].machine.state[platform.device], 0.0001);
    try std.testing.expectApproxEqAbs(origin[1] + 4.2, sandbox.player.feet[1], 0.05);
    try std.testing.expect(sandbox.player.grounded);

    // Step off onto the landing; it holds the player when the platform leaves.
    camera.yaw = std.math.pi / 2.0;
    camera.pitch = 0;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 45);
    try std.testing.expect(sandbox.player.feet[0] > origin[0] + 1.7);
    const call_high = sandbox.findDevice(1, "call_high").?;
    aimAt(&camera, sandbox.devicePosition(call_high));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 240);
    try std.testing.expectEqual(@as(f32, 0), sandbox.machines[1].machine.state[platform.device]);
    try std.testing.expectApproxEqAbs(origin[1] + 4.2, sandbox.player.feet[1], 0.05);
}

test "rover: enter from its side, drive forward on machine power, exit, park, and reload its pose" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const m: u8 = 2;
    const rigid = sandbox.machines[m].vehicle.?.rigid;
    try run(&sandbox, &camera, .{}, .{}, 120);
    const parked = sandbox.physics.rigidPose(rigid).?;
    // Settled on four wheels, aligned with the terrain it parked on (the spawn area slopes).
    const ground_normal = Terrain.surface(sandbox.seed, parked.position[0], parked.position[2]).normal;
    try std.testing.expect(R.dot(R.rotate(parked.orientation, .{ 0, 1, 0 }), ground_normal) > 0.98);
    try std.testing.expect(R.length(sandbox.physics.rigidVelocity(rigid).?.linear) < 0.02);
    for (sandbox.machines[m].vehicle.?.state[0..4]) |w| try std.testing.expect(w.contact);

    // Walk up beside it, aim at the chassis, and get in.
    try standAt(&sandbox, &camera, .{ parked.position[0] - 3, Terrain.surface(sandbox.seed, parked.position[0] - 3, parked.position[2]).height, parked.position[2] });
    aimAt(&camera, parked.position);
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(sandbox.target == .device and sandbox.target.device.machine == m);
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 1);
    try std.testing.expectEqual(@as(?u8, m), sandbox.seated);

    // Two seconds of throttle moves it forward along its heading.
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 120);
    const moved = sandbox.physics.rigidPose(rigid).?;
    const heading = R.rotate(parked.orientation, .{ 0, 0, 1 });
    try std.testing.expect(R.dot(R.sub(moved.position, parked.position), heading) > 4);
    try std.testing.expect(sandbox.machines[m].machine.network(sandbox.machines[m].machine.blueprint.vehicle.?.motor).?.demand > 0);

    // Exit: the parking brake stops it and the player stands beside it, outside the chassis.
    try run(&sandbox, &camera, .{}, .{ .interact = true }, 180);
    try std.testing.expectEqual(@as(?u8, null), sandbox.seated);
    try std.testing.expect(R.length(sandbox.physics.rigidVelocity(rigid).?.linear) < 0.1);
    try std.testing.expect(sandbox.player.grounded);
    const stopped = sandbox.physics.rigidPose(rigid).?;
    const offset = R.inverseRotate(stopped.orientation, R.sub(sandbox.player.feet, stopped.position));
    try std.testing.expect(@abs(offset[0]) > 1.1 + sandbox.player.shape.radius - 0.01);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sandbox.physics.setRigidState(rigid, parked, .{ 0, 0, 0 }, .{ 0, 0, 0 });
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    // Loading rebuilds the world, so the chassis has a new handle.
    try std.testing.expectEqualDeep(stopped, sandbox.physics.rigidPose(sandbox.machines[m].vehicle.?.rigid).?);
}

test "a named, customized character is shown in third person, aims from its eyes, and persists" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();

    // Creator: the character is frozen and faced; tools and movement do nothing.
    try run(&sandbox, &camera, .{}, .{ .open_creator = true }, 1);
    try std.testing.expect(sandbox.creator.open and sandbox.bodyShown());
    const feet = sandbox.player.feet;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{ .interact = true }, 30);
    try std.testing.expectApproxEqAbs(feet[2], sandbox.player.feet[2], 0.001);
    try std.testing.expectApproxEqAbs(sandbox.body_yaw + std.math.pi, camera.yaw, 1e-5);
    while (sandbox.creator.draft.name_len > 0) _ = sandbox.creator.key(.backspace);
    for ("Ash") |c| _ = sandbox.creator.key(.{ .char = c });
    for (0..4) |_| _ = sandbox.creator.key(.down);
    _ = sandbox.creator.key(.right);
    sandbox.profile = sandbox.creator.key(.enter).confirmed;
    try std.testing.expectEqualStrings("ASH", sandbox.profile.name());

    // Third person: the camera sits behind the eyes, but aiming still starts at the eyes,
    // so the crate ahead is still the target.
    try run(&sandbox, &camera, .{}, .{ .toggle_view = true }, 1);
    camera.yaw = 0;
    camera.pitch = -0.2;
    try run(&sandbox, &camera, .{ .forward = 1 }, .{}, 100);
    camera.pitch = -0.35;
    try run(&sandbox, &camera, .{}, .{}, 2);
    const eye = sandbox.player.eye();
    try std.testing.expect(camera.position.z() < eye.z() - 2);
    try std.testing.expect(sandbox.target == .prop);
    var parts: [World.max_props]World.Prop = undefined;
    const drawn = sandbox.publishProps(&parts);
    var avatar_parts: usize = 0;
    for (parts[0..drawn]) |part| avatar_parts += @intFromBool(part.character != null and part.owner == 1);
    try std.testing.expectEqual(@as(usize, 1), avatar_parts);

    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    var other_camera: Camera = .{};
    var other: Sandbox = undefined;
    try other.init(std.testing.allocator, sandbox.seed, &catalog, &other_camera);
    defer other.deinit();
    try other.restore(std.testing.allocator, bytes, &other_camera);
    try std.testing.expectEqualDeep(sandbox.profile, other.profile);
    try std.testing.expect(other.creator.confirmed);
}

test "walk the test Arbor: up the spiral ramp, onto the branch platform, across the bridge road" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    const origin = sandbox.arbor_origin.?;
    const start = R.add(origin, TestArbor.rampPoint(0));
    sandbox.player = .{ .feet = .{ start[0], start[1] + 0.2, start[2] } };
    camera.position = sandbox.player.eye();
    camera.pitch = 0;
    const end_angle = TestArbor.rampEndAngle();
    var travelled: f32 = 0;
    var previous_angle: f32 = 0;
    var worst: f32 = 0;
    var steps: usize = 0;
    // Steer along the ramp's center line until the ramp's full sweep is covered.
    while (travelled < end_angle and steps < 7000) : (steps += 1) {
        const local = R.sub(sandbox.player.feet, origin);
        const angle = std.math.atan2(local[2], local[0]);
        var delta = angle - previous_angle;
        if (delta < -std.math.pi) delta += 2 * std.math.pi;
        if (delta > std.math.pi) delta -= 2 * std.math.pi;
        travelled += delta;
        previous_angle = angle;
        // Height below the ramp surface at this point of the sweep: how far we fell, if at all.
        const expected = TestArbor.rampPoint(std.math.clamp(travelled / end_angle, 0, 1))[1];
        worst = @min(worst, local[1] - expected);
        const radius = @sqrt(local[0] * local[0] + local[2] * local[2]);
        const center = TestArbor.trunkRadius(local[1]) + TestArbor.ramp_clearance + TestArbor.ramp_width / 2;
        const tangent: Physics.Vec3 = .{ -@sin(angle), 0, @cos(angle) };
        const radial: Physics.Vec3 = .{ @cos(angle), 0, @sin(angle) };
        const heading = R.add(tangent, R.scale(radial, (center - radius) * 0.5));
        camera.yaw = std.math.atan2(heading[0], heading[2]);
        try sandbox.step(&camera, .{ .forward = 1, .fast = true }, .{}, 1.0 / 60.0);
    }
    try std.testing.expect(travelled >= end_angle);
    try std.testing.expect(worst > -0.6);
    try std.testing.expectApproxEqAbs(origin[1] + TestArbor.platform_height, sandbox.player.feet[1], 0.3);

    // Out along the branch platform and down the bridge road to the tower top.
    const out: Physics.Vec3 = .{ @cos(end_angle), 0, @sin(end_angle) };
    camera.yaw = std.math.atan2(out[0], out[2]);
    var lowest = std.math.inf(f32);
    for (0..1500) |_| {
        try sandbox.step(&camera, .{ .forward = 1 }, .{}, 1.0 / 60.0);
        lowest = @min(lowest, sandbox.player.feet[1] - origin[1]);
        if (R.dot(R.sub(sandbox.player.feet, origin), out) > 102) break;
    }
    const along = R.dot(R.sub(sandbox.player.feet, origin), out);
    try std.testing.expect(along > 90);
    try std.testing.expect(lowest > TestArbor.tower_top - 0.3);
    try std.testing.expectApproxEqAbs(origin[1] + TestArbor.tower_top, sandbox.player.feet[1], 0.1);
    try std.testing.expect(sandbox.player.grounded);
}

test "separate machines brown out on one Arbor, another tree stays independent, and saves reconnect taps" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const first = sb.treeOrigin(1);
    const radius = sb.tree(1).genome.base_radius;
    const beacon = catalog.content.sap_beacon.*;
    const a = try sb.spawnMachine(null, beacon, R.add(first, .{ radius + 2, 0, -3 }), 0, false);
    const b = try sb.spawnMachine(null, beacon, R.add(first, .{ radius + 2, 0, 3 }), 0, false);
    const c = try sb.spawnMachine(null, beacon, R.add(sb.treeOrigin(2), .{ sb.tree(2).genome.base_radius + 2, 0, 0 }), 0, false);
    try run(&sb, &camera, .{}, .{}, 4);
    try std.testing.expectEqual(@as(u8, 1), sb.tap_links[a][0].?.tree);
    try std.testing.expectEqual(@as(u8, 1), sb.tap_links[b][0].?.tree);
    try std.testing.expectEqual(@as(u8, 2), sb.tap_links[c][0].?.tree);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), sb.machines[a].machine.outputs[2][2], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), sb.machines[b].machine.outputs[2][2], 0.0001);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[c].machine.outputs[2][2]);
    try std.testing.expectEqual(@as(f32, 150), sb.sap_stats[1].supplied);
    var props: [World.max_props]World.Prop = undefined;
    const n = sb.publishProps(&props);
    const marker = R.add(first, .{ radius + 0.3, 2, 0 });
    var stress_shown = false;
    for (props[0..n]) |prop| if (std.meta.eql(prop.transform.position, marker)) {
        try std.testing.expectEqual(@as(f32, 1.5), prop.tint[3]);
        stress_shown = true;
    };
    try std.testing.expect(stress_shown);
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sb.removeMachine(a);
    try run(&sb, &camera, .{}, .{}, 2);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[b].machine.outputs[2][2]);
    try sb.restore(std.testing.allocator, bytes, &camera);
    try run(&sb, &camera, .{}, .{}, 4);
    try std.testing.expectEqual(@as(u8, 1), sb.tap_links[a][0].?.tree);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), sb.machines[a].machine.outputs[2][2], 0.0001);
    // A copied blueprint away from every tree cannot produce power.
    const remote = try sb.spawnMachine(null, beacon, .{ 900, 40, 900 }, 0, false);
    try run(&sb, &camera, .{}, .{}, 3);
    try std.testing.expect(sb.tap_links[remote][0] == null);
    try std.testing.expectEqual(@as(f32, 0), sb.machines[remote].machine.outputs[2][2]);
    // Old procedural content must never silently replace geometry beneath a saved player.
    const incompatible = try std.mem.replaceOwned(u8, std.testing.allocator, bytes, "\"arbor_generator\": 1", "\"arbor_generator\": 2");
    defer std.testing.allocator.free(incompatible);
    const tick_before = sb.tick;
    try std.testing.expectError(error.GeneratorMismatch, sb.restore(std.testing.allocator, incompatible, &camera));
    try std.testing.expectEqual(tick_before, sb.tick);
}

test "walk the entire canopy district loop continuously across every junction" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const nodes = catalog.district.nodes;
    sb.player = .{ .feet = R.add(nodes[0].position, .{ 0, 0.2, 0 }) };
    camera.position = sb.player.eye();
    for ([_]usize{ 1, 2, 3, 4, 5, 0 }) |next| {
        var steps: usize = 0;
        while (steps < 4000) : (steps += 1) {
            const delta = R.sub(nodes[next].position, sb.player.feet);
            if (@sqrt(delta[0] * delta[0] + delta[2] * delta[2]) < 0.2) break;
            camera.yaw = std.math.atan2(delta[0], delta[2]);
            try sb.step(&camera, .{ .forward = 1, .fast = true }, .{}, 1.0 / 60.0);
            try std.testing.expect(sb.player.feet[1] > nodes[0].position[1] - 0.3);
        }
        try std.testing.expect(steps < 4000);
        try std.testing.expectApproxEqAbs(nodes[next].position[1], sb.player.feet[1], 0.15);
        try std.testing.expect(sb.player.grounded);
    }
}

test "drive the canopy loop on machine power without resetting the rover between roads" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const nodes = catalog.district.nodes;
    const rigid = sb.machines[2].vehicle.?.rigid;
    const first = R.sub(nodes[1].position, nodes[0].position);
    sb.physics.setRigidState(rigid, .{ .position = R.add(nodes[0].position, .{ 0, 1.3, 0 }), .orientation = R.axisAngle(.{ 0, 1, 0 }, std.math.atan2(first[0], first[2])) }, @splat(0), @splat(0));
    sb.enterVehicle(2, &camera);
    var next: usize = 1;
    var steps: usize = 0;
    while (steps < 25000 and next <= nodes.len) : (steps += 1) {
        const pose = sb.physics.rigidPose(rigid).?;
        const delta = R.sub(nodes[next % nodes.len].position, pose.position);
        const distance = @sqrt(delta[0] * delta[0] + delta[2] * delta[2]);
        // Switch inside the broad plaza, leaving room for the vehicle's turning circle.
        if (distance < 7) {
            next += 1;
            continue;
        }
        var angle = std.math.atan2(delta[0], delta[2]) - R.yaw(pose.orientation);
        while (angle > std.math.pi) angle -= 2 * std.math.pi;
        while (angle < -std.math.pi) angle += 2 * std.math.pi;
        const speed = sb.machines[2].vehicle.?.forwardSpeed(&sb.physics);
        const desired: f32 = if (distance < 30 or @abs(angle) > 0.3) 4 else 9;
        try sb.step(&camera, .{ .forward = std.math.clamp((desired - speed) * 0.4, -0.5, 1), .right = std.math.clamp(angle * 3, -1, 1) }, .{}, 1.0 / 60.0);
        try std.testing.expect(pose.position[1] > nodes[0].position[1]);
        try std.testing.expect(R.rotate(pose.orientation, .{ 0, 1, 0 })[1] > 0.9);
    }
    if (next <= nodes.len) std.debug.print("rover stuck approaching plaza {d}, position {any}\n", .{ next % nodes.len, sb.physics.rigidPose(rigid).?.position });
    try std.testing.expect(next > nodes.len);
    sb.exitVehicle(&camera);
    try run(&sb, &camera, .{}, .{}, 60);
    try std.testing.expect(sb.player.grounded);
    try std.testing.expectApproxEqAbs(nodes[0].position[1], sb.player.feet[1], 0.15);
}

test "player bridge collision and stable endpoints survive save load; invalid deltas leave world intact" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const edge: District.Edge = .{ .a = 0, .b = 3 };
    const slot = try sb.addBridge(edge);
    const middle = District.span(&catalog.district, edge).point(0.5);
    const ray = R.add(middle, .{ 0, 5, 0 });
    const hit = sb.physics.raycast(ray, .{ 0, -1, 0 }, 10, .none).?;
    try std.testing.expect(hit.user & bridge_flag != 0);
    // Traverse the new span through both plaza seams before persisting it.
    sb.player = .{ .feet = R.add(catalog.district.nodes[0].position, .{ 0, 0.2, 0 }) };
    camera.position = sb.player.eye();
    const destination = catalog.district.nodes[3].position;
    var steps: usize = 0;
    while (steps < 3000) : (steps += 1) {
        const delta = R.sub(destination, sb.player.feet);
        if (R.length(delta) < 0.2) break;
        camera.yaw = std.math.atan2(delta[0], delta[2]);
        try sb.step(&camera, .{ .forward = 1, .fast = true }, .{}, 1.0 / 60.0);
        try std.testing.expect(sb.player.feet[1] > catalog.district.nodes[0].position[1] - 0.3);
    }
    try std.testing.expect(steps < 3000);
    try std.testing.expect(sb.player.grounded);
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sb.removeBridge(slot);
    try std.testing.expect(sb.physics.castRay(ray, .{ 0, -1, 0 }, 10, .none) == null);
    try sb.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqualDeep(edge, sb.bridges[0].?.edge);
    try std.testing.expectApproxEqAbs(middle[1], sb.physics.castRay(ray, .{ 0, -1, 0 }, 10, .none).?.point[1], 0.01);
    const parsed = try Save.decode(std.testing.allocator, bytes, sb.seed, max_crates, max_machines);
    defer parsed.deinit();
    var invalid = parsed.value;
    invalid.bridges = &.{.{ .a = 0, .b = 99 }};
    const bad = try Save.encode(std.testing.allocator, invalid);
    defer std.testing.allocator.free(bad);
    const before = sb.bridges[0].?.collider;
    try std.testing.expectError(error.InvalidAnchor, sb.restore(std.testing.allocator, bad, &camera));
    try std.testing.expectEqual(before, sb.bridges[0].?.collider);
    try std.testing.expectEqualDeep(edge, sb.bridges[0].?.edge);
}

test "bridge allocation failure leaves existing bridge and session intact" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    _ = try sb.addBridge(.{ .a = 0, .b = 3 });
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    const before = sb.bridges[0].?.collider;
    const feet = sb.player.feet;
    const machines = sb.machineCount();
    // Fail each allocation in staging, including triangle/BVH storage. Stop at the first
    // successful complete restore, freeing its collider before the allocator leaves scope.
    var fail_index: usize = 0;
    while (fail_index < 32) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        sb.allocator = failing.allocator();
        defer sb.allocator = std.testing.allocator;
        if (sb.restore(std.testing.allocator, bytes, &camera)) |_| {
            sb.removeBridge(0);
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(before, sb.bridges[0].?.collider);
            try std.testing.expectEqualDeep(feet, sb.player.feet);
            try std.testing.expectEqual(machines, sb.machineCount());
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
    }
    try std.testing.expect(fail_index < 32);
}

test "walk both Arbor spurs and their complete trunk plazas" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    for ([_]usize{ 2, 4 }) |node_id| {
        const node = catalog.district.nodes[node_id];
        const tree_center = catalog.district.trees[node.tree.?].position;
        sb.player = .{ .feet = R.add(node.position, .{ 0, 0.2, 0 }) };
        camera.position = sb.player.eye();
        const angle = std.math.atan2(node.position[0] - tree_center[0], node.position[2] - tree_center[2]);
        for (0..33) |i| {
            const theta = angle + @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 32;
            const destination: Physics.Vec3 = .{ tree_center[0] + @sin(theta) * 30, node.position[1], tree_center[2] + @cos(theta) * 30 };
            var steps: usize = 0;
            while (steps < 600) : (steps += 1) {
                const delta = R.sub(destination, sb.player.feet);
                if (R.length(delta) < 0.2) break;
                camera.yaw = std.math.atan2(delta[0], delta[2]);
                try sb.step(&camera, .{ .forward = 1, .fast = true }, .{}, 1.0 / 60.0);
                try std.testing.expect(sb.player.feet[1] > node.position[1] - 0.3);
            }
            try std.testing.expect(steps < 600);
            try std.testing.expect(sb.player.grounded);
        }
    }
}

test "four local players: guests join beside P1, move and look independently, press a button, and leave" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sandbox: Sandbox = undefined;
    try testSandbox(&sandbox, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sandbox.deinit();
    try run(&sandbox, &camera, .{}, .{}, 30);
    for (0..3) |i| sandbox.joinGuest(i);
    try std.testing.expectEqual(@as(usize, 3), sandbox.guestCount());
    try run(&sandbox, &camera, .{}, .{}, 30);
    const p1 = sandbox.player.feet;
    var starts: [3]Physics.Vec3 = undefined;
    for (sandbox.guests, &starts) |g, *start| {
        try std.testing.expect(g.player.grounded);
        try std.testing.expect(R.length(R.sub(g.player.feet, p1)) > 1.2);
        start.* = g.player.feet;
    }

    // Three different pads for one second; P1 stands still.
    const yaw = sandbox.guests[2].camera.yaw;
    sandbox.guests[0].input = .{ .forward = 1 };
    sandbox.guests[1].input = .{ .right = 1 };
    sandbox.guests[2].input = .{ .look_x = 1 };
    try run(&sandbox, &camera, .{}, .{}, 60);
    try std.testing.expect(R.length(R.sub(sandbox.player.feet, p1)) < 0.05);
    try std.testing.expect(sandbox.guests[0].player.feet[2] - starts[0][2] > 3);
    try std.testing.expect(sandbox.guests[1].player.feet[0] - starts[1][0] > 3);
    try std.testing.expect(R.length(R.sub(sandbox.guests[2].player.feet, starts[2])) < 0.05);
    try std.testing.expectApproxEqAbs(yaw + 2.8, sandbox.guests[2].camera.yaw, 0.05);
    // Guests default to third person: each camera sits behind its own eyes.
    for (sandbox.guests) |g| try std.testing.expect(g.camera.position.sub(&g.player.eye()).len() > 3);

    // Every body is published as one skinned character tagged with its owner (P1's included
    // while in first person), each in its own renderer slot.
    var parts: [World.max_props]World.Prop = undefined;
    const drawn = sandbox.publishProps(&parts);
    var owned: [5]usize = @splat(0);
    for (parts[0..drawn]) |part| if (part.character) |c| if (part.owner != 0) {
        owned[part.owner] += 1;
        try std.testing.expectEqual(part.owner - 1, c.id);
    };
    for (owned[1..]) |count| try std.testing.expectEqual(@as(usize, 1), count);

    // P3 walks up to the powered door's button and presses it; the door opens for everyone.
    for (&sandbox.guests) |*g| g.input = .{};
    const button = sandbox.findDevice(0, "button").?;
    const door = sandbox.findDevice(0, "door").?;
    const origin = sandbox.machines[0].machine.origin;
    const g = &sandbox.guests[1];
    g.player = .{ .feet = .{ origin[0], origin[1] + 0.1, origin[2] - 3 } };
    g.view = .first;
    try run(&sandbox, &camera, .{}, .{}, 30);
    g.camera.position = g.player.eye();
    aimAt(&g.camera, sandbox.devicePosition(button));
    try run(&sandbox, &camera, .{}, .{}, 1);
    try std.testing.expect(g.target == .device and g.target.device.device == button.device);
    g.interact = true;
    try run(&sandbox, &camera, .{}, .{}, 150);
    try std.testing.expectApproxEqAbs(@as(f32, 1), sandbox.machines[0].machine.state[door.device], 0.0001);

    // Leaving removes the body; saves ignore guests, and loading returns them beside P1.
    sandbox.leaveGuest(2);
    try std.testing.expectEqual(@as(usize, 2), sandbox.guestCount());
    owned = @splat(0);
    for (parts[0..sandbox.publishProps(&parts)]) |part| if (part.character != null and part.owner != 0) {
        owned[part.owner] += 1;
    };
    try std.testing.expectEqual(@as(usize, 0), owned[4]);
    const bytes = try sandbox.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "guest") == null);
    try sandbox.restore(std.testing.allocator, bytes, &camera);
    for (sandbox.guests[0..2]) |guest| try std.testing.expect(R.length(R.sub(guest.player.feet, sandbox.player.feet)) < 3);
}

test "city traffic drives its lanes, takes a new bridge, reroutes around a removed one; pedestrians walk" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.enableLife();
    try std.testing.expectEqual(@as(usize, Life.car_count), sb.life.rigidCount());
    var starts: [Life.walker_count]Physics.Vec3 = undefined;
    for (sb.life.walkers, &starts) |w, *start| start.* = w.player.feet;
    const deck = catalog.district.nodes[0].position[1];

    // Ninety seconds of free traffic: every car reaches other plazas (waiting its turn at busy
    // plazas), stays upright on the deck, and nothing needs recovering; pedestrians walk their
    // walkways without falling.
    for (0..5400) |_| {
        try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
        for (sb.life.cars) |slot| {
            const pose = sb.physics.rigidPose(slot.?.vehicle.rigid).?;
            try std.testing.expect(R.rotate(pose.orientation, .{ 0, 1, 0 })[1] > 0.9 and pose.position[1] > deck - 3);
        }
    }
    for (sb.life.cars) |slot| try std.testing.expect(@popCount(slot.?.visited) >= 3);
    for (sb.life.walkers, starts) |w, start| {
        try std.testing.expect(w.player.feet[1] > deck - 2);
        try std.testing.expect(R.length(R.sub(w.player.feet, start)) > 20);
    }
    try std.testing.expectEqual(@as(u32, 0), sb.life.resets);

    // A new 0 → 3 bridge is a shortcut: a car bound for 3 from 0 drives across it, and the
    // bridge counts as occupied (the build tool refuses to remove it) while it does.
    sb.life.park(2);
    const slot = try sb.addBridge(.{ .a = 0, .b = 3 });
    var graph = sb.routes();
    try sb.life.sendCar(&sb.physics, &graph, 1, 0, 3);
    var occupied = false;
    var steps: usize = 0;
    while (sb.life.cars[1].?.visited & (1 << 3) == 0 and steps < 4000) : (steps += 1) {
        try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
        occupied = occupied or sb.bridgeOccupied(slot);
    }
    try std.testing.expect(occupied and steps < 4000);
    try std.testing.expectEqual(@as(u8, 0), sb.life.cars[1].?.visited & (1 << 4 | 1 << 5));
    sb.life.park(1);

    // A car bound 1 → 0 → 3 over the bridge; the bridge is removed while it is on its way to 0,
    // so it continues around the loop instead.
    try sb.life.sendCar(&sb.physics, &graph, 0, 1, 3);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 3 }, sb.life.cars[0].?.path.slice());
    while (graph.progress(1, 0, sb.physics.rigidPose(sb.life.cars[0].?.vehicle.rigid).?.position) < 0.5) try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
    // Pedestrians may be crossing it, so it closes to new traffic and stands until they are off.
    _ = sb.closeBridge(slot);
    try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 5, 4, 3 }, sb.life.cars[0].?.path.slice());
    steps = 0;
    while (sb.life.cars[0].?.visited & (1 << 3) == 0 and steps < 12000) : (steps += 1) try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
    try std.testing.expect(steps < 12000);
    try std.testing.expectEqual(@as(u8, 1 << 0 | 1 << 1 | 1 << 3 | 1 << 4 | 1 << 5), sb.life.cars[0].?.visited);
    try std.testing.expectEqual(@as(u32, 0), sb.life.resets);
    // Nobody fell: once its last pedestrian is across, the closed bridge is gone.
    steps = 0;
    while (sb.bridges[slot] != null and steps < 20000) : (steps += 1) try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
    try std.testing.expect(sb.bridges[slot] == null);
    try std.testing.expectEqual(@as(u32, 0), sb.life.resets);
}

test "markets buy salvaged parts, sell kits that place and refund, sell out, persist, and restock at dawn" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();

    // Salvaging a relic yields one part.
    sb.player.mode = .fly;
    var objects: [Scatter.capacity]Scatter.Object = undefined;
    const key = Key.fromPosition(spawn[0], spawn[2]);
    const relic = for (objects[0..Scatter.generate(sb.seed, key, &objects)]) |o| {
        if (o.kind == .relic) break o;
    } else return error.SkipZigTest;
    const rp = relic.transform.position;
    camera.position = math.vec3(rp[0], rp[1] + relic.transform.scale, rp[2] - 2 - relic.transform.scale);
    camera.yaw = 0;
    camera.pitch = 0;
    try run(&sb, &camera, .{}, .{}, 1);
    try run(&sb, &camera, .{}, .{ .secondary = true }, 1);
    try std.testing.expectEqual(@as(u32, 1), sb.wallet.parts);

    // Walk up to the stall at plaza 1, aim under its canopy, and open it.
    sb.player.mode = .walk;
    const stall = sb.stallPosition(0);
    const plaza = catalog.district.nodes[Market.stall_plazas[0]].position;
    const out = R.normalize(.{ plaza[0] - stall[0], 0, plaza[2] - stall[2] });
    try standAt(&sb, &camera, R.add(stall, R.add(R.scale(out, 4.5), .{ 0, 0.05, 0 })));
    aimAt(&camera, R.add(stall, .{ 0, 1, 0 }));
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expect(sb.target == .stall and sb.target.stall == 0);
    // Clicking the stall greets its keeper; "show me your stall" opens the trade panel.
    try run(&sb, &camera, .{}, .{ .interact = true }, 1);
    try std.testing.expect(sb.talk != null and sb.talk.?.partner.keeper == 0);
    try std.testing.expect(sb.progress.hasFlag("met_maro") and sb.progress.hasFlag("salvaged"));
    sb.talkKey(.confirm);
    sb.talkKey(.down);
    sb.talkKey(.down);
    sb.talkKey(.confirm);
    try std.testing.expect(sb.talk == null);
    try std.testing.expectEqual(@as(?u8, 0), sb.trading);
    var lines: [trade_rows + 2]TradeLine = undefined;
    try std.testing.expectEqual(@as(usize, trade_rows + 2), sb.tradeLines(&lines));

    // Sell six parts (five more from the field), then buy one ware until it sells out.
    sb.wallet.parts += 5;
    sb.tradeKey(.confirm);
    try std.testing.expectEqual(Market.Wallet{ .scrap = 6 * sb.market.partPrice(0) }, sb.wallet);
    sb.wallet.scrap += 200;
    const w: usize = for (0..Market.ware_count) |i| {
        if (sb.market.stalls[0].stock[i] > 0) break i;
    } else unreachable;
    const ware: Market.Ware = @enumFromInt(w);
    for (0..w + 1) |_| sb.tradeKey(.down);
    const stocked = sb.market.stalls[0].stock[w];
    const scrap = sb.wallet.scrap;
    for (0..stocked + 1) |_| sb.tradeKey(.confirm);
    try std.testing.expectEqual(stocked, sb.wallet.kits[w]);
    try std.testing.expectEqual(@as(u8, 0), sb.market.stalls[0].stock[w]);
    try std.testing.expectEqual(scrap - stocked * sb.market.price(0, ware), sb.wallet.scrap);

    // Walking away closes the stall.
    try standAt(&sb, &camera, .{ spawn[0], Terrain.surface(sb.seed, spawn[0], spawn[2]).height, spawn[2] });
    try std.testing.expectEqual(@as(?u8, null), sb.trading);

    // A kit places one machine of its design and is used up; that machine cannot be captured,
    // and removing it returns the kit. With no kits left, nothing is placed.
    const bp = catalog.content.wares[w];
    const x = spawn[0] + 20;
    const z = spawn[2] - 12;
    const preview: Build.Preview = .{ .entry = .{ .kit = ware }, .origin = sb.groundOrigin(bp, x, z, 0), .center = undefined, .half = undefined, .yaw = 0, .valid = true };
    const machines = sb.machineCount();
    try Build.place(&sb, preview);
    try std.testing.expectEqual(machines + 1, sb.machineCount());
    try std.testing.expectEqual(stocked - 1, sb.wallet.kits[w]);
    const m: u8 = for (sb.machines, 0..) |placed, i| {
        if (placed.kit == ware) break @intCast(i);
    } else unreachable;
    sb.target = .{ .structure = m };
    const prefabs = sb.prefab_count;
    Build.capture(&sb);
    try std.testing.expectEqual(prefabs, sb.prefab_count);
    Build.remove(&sb, .{ .structure = m });
    try std.testing.expectEqual(stocked, sb.wallet.kits[w]);
    const held = sb.wallet.kits[w];
    sb.wallet.kits[w] = 0;
    try Build.place(&sb, preview);
    try std.testing.expectEqual(machines, sb.machineCount());
    sb.wallet.kits[w] = held;
    try Build.place(&sb, preview);

    // Wallet, stock, market day, and the kit machine survive a save round trip.
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    const saved_wallet = sb.wallet;
    const saved_stalls = sb.market.stalls;
    sb.wallet = .{};
    sb.market = Market.init(sb.seed, 0);
    try sb.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expectEqual(saved_wallet, sb.wallet);
    try std.testing.expectEqual(saved_stalls, sb.market.stalls);
    try std.testing.expectEqual(ware, sb.machines[m].kit.?);

    // The next dawn restocks every stall with that day's seeded stock.
    const dawn = @import("../engine/Sky.zig").day_ticks * 9 / 10;
    sb.tick = dawn - 2;
    try run(&sb, &camera, .{}, .{}, 3);
    try std.testing.expectEqual(@as(u64, 1), sb.market.day);
    try std.testing.expectEqual(Market.init(sb.seed, dawn).stalls, sb.market.stalls);
    try std.testing.expect(std.mem.indexOf(u8, sb.noticeText(), "restocked") != null);
}

test "Rootsong carries a channel only between Arbors that share roots, and only from rooted devices" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    // The test Arbor and the narrow Arbor overlap roots; the spreading Arbor stands alone.
    try std.testing.expectEqual([sap_tree_count]u8{ 0, 0, 2 }, sb.root_groups);

    // Sender at the test Arbor: button → latch → root sender, all loose workshop devices.
    const o0 = sb.treeOrigin(0);
    const r0 = sb.tree(0).genome.base_radius;
    var refs: [3]DeviceRef = undefined;
    for ([_]Build.Item{ .button, .latch, .root_sender }, &refs, 0..) |item, *ref, i| {
        const x = o0[0] + r0 + 2;
        const z = o0[2] - 3 + @as(f32, @floatFromInt(i)) * 1.5;
        ref.* = try sb.addWorkshopDevice(Build.kitDevice(item, @tagName(item)), .{ x, Terrain.surface(sb.seed, x, z).height + 0.6, z });
    }
    const bp = &sb.machines[refs[0].machine].blueprint;
    for ([_][2]usize{ .{ 0, 1 }, .{ 1, 2 } }) |pair| {
        var buffer: [Build.max_candidates]Blueprint.Wire = undefined;
        try std.testing.expect(Build.candidates(&sb, refs[pair[0]], refs[pair[1]], &buffer) > 0);
        try bp.connect(buffer[0].from, buffer[0].to);
    }
    sb.machines[refs[0].machine].machine.reconfigure();

    // Identical listener lamps: rooted at tree 1, rooted at tree 2, and far from any wood.
    const listener = try Blueprint.parse(std.testing.allocator,
        \\{"format":1,"name":"hearth","devices":[
        \\ {"id":"cell","kind":"generator","offset":[0,0.5,0],"size":[0.5,1,0.5],"watts":100},
        \\ {"id":"hear","kind":"root_listener","offset":[0,0.5,1],"size":[0.6,0.4,0.6],"channel":1},
        \\ {"id":"lamp","kind":"lamp","offset":[0,0.8,2],"size":[0.4,1.2,0.4],"watts":20}],
        \\ "wires":[["cell.power","lamp.power"],["hear.out","lamp.on"]]}
    );
    var lamps: [3]u8 = undefined;
    for ([_]?usize{ 1, 2, null }, &lamps) |tree_id, *slot| {
        const base: Physics.Vec3 = if (tree_id) |t| R.add(sb.treeOrigin(t), .{ sb.tree(t).genome.base_radius + 1.5, 0, -1 }) else .{ spawn[0] - 30, 0, spawn[2] };
        slot.* = try sb.spawnMachine(null, listener, sb.groundOrigin(&listener, base[0], base[2], 0), 0, false);
    }
    const lamp = listener.findDevice("lamp").?;
    const hear = listener.findDevice("hear").?;
    try run(&sb, &camera, .{}, .{}, 2);
    try std.testing.expectEqual(@as(?u8, 0), sb.machines[lamps[0]].machine.root_group[hear]);
    try std.testing.expectEqual(@as(?u8, 2), sb.machines[lamps[1]].machine.root_group[hear]);
    try std.testing.expectEqual(@as(?u8, null), sb.machines[lamps[2]].machine.root_group[hear]);
    for (lamps) |m| try std.testing.expectEqual(@as(f32, 0), sb.machines[m].machine.outputs[lamp][2]);

    // Press: only the lamp rooted in the sender's root group lights.
    sb.press = refs[0];
    try run(&sb, &camera, .{}, .{}, 10);
    const lit = [3]bool{ true, false, false };
    for (lamps, lit) |m, expected| try std.testing.expectEqual(expected, sb.machines[m].machine.outputs[lamp][2] > 0.99);

    // A different channel is a different song.
    sb.machines[lamps[0]].blueprint.devices[hear].channel = 2;
    try run(&sb, &camera, .{}, .{}, 3);
    try std.testing.expectEqual(@as(f32, 0), sb.machines[lamps[0]].machine.outputs[lamp][2]);
    sb.machines[lamps[0]].blueprint.devices[hear].channel = 1;

    // The song resumes after a save round trip (roots are re-resolved from positions).
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    try sb.restore(std.testing.allocator, bytes, &camera);
    try run(&sb, &camera, .{}, .{}, 4);
    for (lamps, lit) |m, expected| try std.testing.expectEqual(expected, sb.machines[m].machine.outputs[lamp][2] > 0.99);
}

test "cars wait at the edge of a plaza another car is inside, then go when it leaves" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.enableLife();
    sb.life.park(2);
    var graph = sb.routes();
    // Car 1 stands in plaza 2; car 0 drives 1 → 2 → 3 toward it.
    try sb.life.sendCar(&sb.physics, &graph, 1, 2, 5);
    sb.life.park(1);
    try sb.life.sendCar(&sb.physics, &graph, 0, 1, 3);
    const node2 = catalog.district.nodes[2].position;
    var waited: usize = 0;
    for (0..2400) |_| {
        try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
        if (sb.life.cars[0].?.waiting) waited += 1;
        if (waited >= 120) break;
    }
    // Stopped at the edge for two seconds, outside the plaza.
    try std.testing.expect(waited >= 120);
    const p = sb.physics.rigidPose(sb.life.cars[0].?.vehicle.rigid).?.position;
    const d = @sqrt((p[0] - node2[0]) * (p[0] - node2[0]) + (p[2] - node2[2]) * (p[2] - node2[2]));
    try std.testing.expect(d > District.plaza_radius - 2 and d < District.plaza_radius + 8);
    try std.testing.expect(sb.life.plaza_waits >= 1);
    // Car 1 leaves toward plaza 5; car 0 proceeds and reaches plaza 3 with no deadlock broken.
    sb.life.cars[1].?.parked = false;
    var steps: usize = 0;
    while (sb.life.cars[0].?.visited & (1 << 3) == 0 and steps < 6000) : (steps += 1) try sb.step(&camera, .{}, .{}, 1.0 / 60.0);
    try std.testing.expect(steps < 6000);
    try std.testing.expectEqual(@as(u32, 0), sb.life.deadlocks);
    try std.testing.expectEqual(@as(u32, 0), sb.life.resets);
}

test "a guest trades at a stall with the party wallet while standing still, and B closes it" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.joinGuest(0);
    const g = &sb.guests[0];
    const stall = sb.stallPosition(1);
    const plaza = catalog.district.nodes[Market.stall_plazas[1]].position;
    const out = R.normalize(.{ plaza[0] - stall[0], 0, plaza[2] - stall[2] });
    g.player = .{ .feet = R.add(stall, R.add(R.scale(out, 4.5), .{ 0, 0.05, 0 })) };
    g.view = .first;
    try run(&sb, &camera, .{}, .{}, 30);
    g.camera.position = g.player.eye();
    aimAt(&g.camera, R.add(stall, .{ 0, 1, 0 }));
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expect(g.target == .stall and g.target.stall == 1);
    g.interact = true;
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expectEqual(@as(?u8, 1), g.trading);
    try std.testing.expectEqual(@as(?u8, null), sb.trading);

    // Stick input does not move a trading guest; the D-pad walks the rows.
    const feet = g.player.feet;
    g.input = .{ .forward = 1 };
    try run(&sb, &camera, .{}, .{}, 30);
    try std.testing.expect(R.length(R.sub(g.player.feet, feet)) < 0.05);
    g.input = .{};
    sb.wallet = .{ .parts = 3, .scrap = 200 };
    g.interact = true; // Row 0: sell the party's parts.
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expectEqual(@as(u32, 0), sb.wallet.parts);
    const w: u8 = for (0..Market.ware_count) |i| {
        if (sb.market.stalls[1].stock[i] > 0) break @intCast(i);
    } else unreachable;
    for (0..w + 1) |_| {
        g.trade_down = true;
        try run(&sb, &camera, .{}, .{}, 1);
    }
    try std.testing.expectEqual(w + 1, g.trade_row);
    g.interact = true;
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expectEqual(@as(u8, 1), sb.wallet.kits[w]);
    // B closes the stall; the guest can walk again.
    g.input = .{ .dodge = true };
    try run(&sb, &camera, .{}, .{}, 1);
    try std.testing.expectEqual(@as(?u8, null), g.trading);
    g.input = .{ .forward = 1 };
    try run(&sb, &camera, .{}, .{}, 30);
    try std.testing.expect(R.length(R.sub(g.player.feet, feet)) > 1);
}

/// Walks P1 along the shrine walkway (x = 0) and then across to `local` in shrine `k`. While
/// carrying, it looks up so the crate rides overhead (0.8 m ahead, 3.7 m up): clear of walls,
/// doorways, and other crates, and above the height plates sense.
fn shrineWalk(sb: *Sandbox, camera: *Camera, k: usize, local: [3]f32) !void {
    const here = R.sub(sb.player.feet, sb.shrines[k].origin);
    for ([_][2]f32{ .{ 0, here[2] }, .{ 0, local[2] }, .{ local[0], local[2] } }) |xz| {
        const goal = sb.shrinePoint(k, .{ xz[0], 0, xz[1] });
        var steps: usize = 0;
        while (steps < 900) : (steps += 1) {
            const dx = goal[0] - sb.player.feet[0];
            const dz = goal[2] - sb.player.feet[2];
            const d = @sqrt(dx * dx + dz * dz);
            if (d < 0.2) break;
            camera.yaw = std.math.atan2(dx, dz);
            camera.pitch = if (sb.held != null) 1.2 else -0.3;
            try sb.step(camera, .{ .forward = if (d < 1.2) 0.3 else 1 }, .{}, 1.0 / 60.0);
        }
        if (steps == 900) return error.ShrineWalkBlocked;
    }
}

fn shrineDoor(sb: *const Sandbox, k: usize, door: usize) f32 {
    const placed = &sb.machines[sb.shrines[k].machine.?];
    var name: [4]u8 = undefined;
    return placed.machine.state[placed.blueprint.findDevice(std.fmt.bufPrint(&name, "d{d}", .{door}) catch unreachable).?];
}

/// Faces `yaw` with the carrying pitch, lets a held crate settle, and releases it.
fn shrineDrop(sb: *Sandbox, camera: *Camera, yaw: f32) !void {
    camera.yaw = yaw;
    camera.pitch = -0.3;
    try run(sb, camera, .{}, .{}, 40);
    try run(sb, camera, .{}, .{ .interact = true }, 90);
    try std.testing.expectEqual(@as(?u32, null), sb.held);
}

/// Plays shrine `k`'s verified plan in the world from its entrance room: walking, aiming,
/// pressing, carrying, and waiting on real doors, and checks after every action that each
/// door is open exactly when the puzzle model says so.
fn playShrine(sb: *Sandbox, camera: *Camera, k: usize) !void {
    const shrine = &sb.shrines[k];
    const p = shrine.generated.puzzle;
    const m = shrine.machine.?;
    // Crates by puzzle index: the live crate at each start position.
    var crates: [Shrine.max_plates]u32 = undefined;
    for (0..p.plates) |c| {
        const start = sb.shrinePoint(k, Shrine.crateStart(p, c));
        crates[c] = for (0..max_crates) |i| {
            if (sb.crateLive(i) and @abs(sb.cratePosition(@intCast(i))[0] - start[0]) < 0.1 and @abs(sb.cratePosition(@intCast(i))[2] - start[2]) < 0.1) break @intCast(i);
        } else return error.ShrineCrateMissing;
    }

    // Enter room 0 and play the verifier's plan with real walking, aiming, and carrying.
    try standAt(sb, camera, sb.shrinePoint(k, .{ 0, 0.05, 2 }));
    var state = Shrine.initial(p);
    for (shrine.generated.plan.slice()) |action| {
        const room = state.room;
        switch (action) {
            .press => |l| {
                const b = Shrine.buttonPosition(p, l);
                try shrineWalk(sb, camera, k, .{ -Shrine.width / 2 + 1.65, 0, b[2] });
                aimAt(camera, sb.shrinePoint(k, b));
                try run(sb, camera, .{}, .{}, 1);
                try std.testing.expect(sb.target == .device and sb.target.device.machine == m);
                try run(sb, camera, .{}, .{ .interact = true }, 1);
            },
            .pick => |c| {
                const at = R.sub(sb.cratePosition(crates[c]), shrine.origin);
                // Crates on the left are reached from the walkway; crates on plates from x = 0.4.
                try shrineWalk(sb, camera, k, .{ if (at[0] < 0) 0 else 0.4, 0, at[2] });
                aimAt(camera, sb.cratePosition(crates[c]));
                try run(sb, camera, .{}, .{}, 1);
                try std.testing.expect(sb.target == .prop and sb.target.prop == crates[c]);
                try run(sb, camera, .{}, .{ .interact = true }, 1);
                try std.testing.expectEqual(@as(?u32, crates[c]), sb.held);
                camera.pitch = 1.2;
                try run(sb, camera, .{}, .{}, 30);
            },
            .drop_plate => |plate| {
                const pp = Shrine.platePosition(p, plate);
                try shrineWalk(sb, camera, k, .{ pp[0] - 2.1, 0, pp[2] });
                try shrineDrop(sb, camera, std.math.pi / 2.0);
            },
            .drop_floor => {
                const c = Shrine.roomCenter(room);
                try shrineWalk(sb, camera, k, .{ 0, 0, c[2] + 1.5 });
                try shrineDrop(sb, camera, -std.math.pi / 2.0);
            },
            .move => |to| {
                const door = @min(room, to);
                var waited: usize = 0;
                while (shrineDoor(sb, k, door) < 0.999 and waited < 240) : (waited += 1) try run(sb, camera, .{}, .{}, 1);
                try std.testing.expect(waited < 240);
                try shrineWalk(sb, camera, k, Shrine.roomCenter(to));
            },
            .vault => {
                const v = Shrine.vaultPosition(p);
                try shrineWalk(sb, camera, k, .{ 0, 0, v[2] - 2.5 });
                aimAt(camera, sb.shrinePoint(k, v));
                try run(sb, camera, .{}, .{}, 1);
                try run(sb, camera, .{}, .{ .interact = true }, 10);
            },
        }
        state = Shrine.apply(p, state, action).?;
        try run(sb, camera, .{}, .{}, 90);
        // The world agrees with the model: every door is open exactly when the model says so.
        for (0..p.rooms - 1) |d| try std.testing.expectEqual(Shrine.doorOpen(p, state, d), shrineDoor(sb, k, d) > 0.5);
        if (action != .vault) try std.testing.expect(sb.insideShrine(k, sb.player.feet));
    }
}

test "Rootdeep shrines are verified before they appear, and the verifier's plan completes one in the world" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    // Both shrines stand in the Rootdeep with verified plans and their own machine slots.
    for (sb.shrines) |shrine| {
        try std.testing.expect(shrine.machine != null and !shrine.completed);
        var s = Shrine.initial(shrine.generated.puzzle);
        for (shrine.generated.plan.slice()) |a| s = Shrine.apply(shrine.generated.puzzle, s, a).?;
        try std.testing.expect(R.length(R.sub(shrine.origin, .{ spawn[0], shrine.origin[1], spawn[2] })) > 100);
    }
    const k: usize = 0;
    const shrine = &sb.shrines[k];
    const m = shrine.machine.?;

    // Protected: no removal, capture, or rewiring of the shrine machine.
    const before = sb.machineCount();
    Build.remove(&sb, .{ .structure = m });
    sb.target = .{ .structure = m };
    Build.capture(&sb);
    try std.testing.expectEqual(before, sb.machineCount());
    try std.testing.expectEqual(@as(usize, 0), sb.prefab_count);

    try playShrine(&sb, &camera, k);
    try std.testing.expect(shrine.completed);
    try std.testing.expectEqual(@as(usize, 1), sb.prefab_count);
    try std.testing.expectEqualStrings("rootsong_hearth", sb.prefabs[0].name());
    const seed_lamp = sb.machines[m].blueprint.findDevice("seed").?;
    try std.testing.expect(sb.machines[m].machine.outputs[seed_lamp][2] > 0.99);

    // Completion and the reward survive a save round trip; shrine 1 is still sealed.
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    try sb.restore(std.testing.allocator, bytes, &camera);
    try std.testing.expect(sb.shrines[0].completed and !sb.shrines[1].completed);
    try std.testing.expectEqualStrings("rootsong_hearth", sb.prefabs[0].name());

    // Shrine 1's reset button returns its crates and latches to the start.
    const s1 = &sb.shrines[1];
    const p1 = s1.generated.puzzle;
    if (p1.plates > 0) {
        const start = sb.shrinePoint(1, Shrine.crateStart(p1, 0));
        const crate = for (0..max_crates) |i| {
            if (sb.crateLive(i) and sb.insideShrine(1, sb.cratePosition(@intCast(i)))) break i;
        } else unreachable;
        sb.physics.setTransform(sb.crates[crate], sb.shrinePoint(1, .{ 3, 1, 4 }), .{ 0, 0, 0 });
        try std.testing.expect(@abs(sb.cratePosition(@intCast(crate))[2] - start[2]) > 0.5 or @abs(sb.cratePosition(@intCast(crate))[0] - start[0]) > 0.5);
    }
    try sb.resetShrine(1);
    try run(&sb, &camera, .{}, .{}, 30);
    for (0..p1.plates) |c| {
        const start = sb.shrinePoint(1, Shrine.crateStart(p1, c));
        const found = for (0..max_crates) |i| {
            if (!sb.crateLive(i)) continue;
            const q = sb.cratePosition(@intCast(i));
            if (@abs(q[0] - start[0]) < 0.2 and @abs(q[2] - start[2]) < 0.2) break true;
        } else false;
        try std.testing.expect(found);
    }
    for (0..p1.rooms - 1) |d| try std.testing.expectEqual(Shrine.doorOpen(p1, Shrine.initial(p1), d), shrineDoor(&sb, 1, d) > 0.5);
    // After the reset, shrine 1's own verified plan completes it too.
    try playShrine(&sb, &camera, 1);
    try std.testing.expect(sb.shrines[1].completed);
    try std.testing.expectEqualStrings("rootsong_call", sb.prefabs[1].name());
}

test "a mod's blueprint and WebAssembly script run a machine, saves record the mod, and missing mods degrade" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    var pkg = try Mod.load(std.testing.allocator, "glowworks", Mod.glowworksFiles(@embedFile("glowworks.mod")));
    defer pkg.deinit();
    try sb.installMod(&pkg);
    try std.testing.expectError(error.DuplicateMod, sb.installMod(&pkg));
    try std.testing.expectEqual(@as(usize, 1), sb.prefab_count);
    try std.testing.expectEqualStrings("breathing_lamp", sb.prefabs[0].name());

    // Place it from the palette's blueprint and switch it on.
    const x = spawn[0] - 14;
    const z = spawn[2] + 4;
    const m = try sb.spawnMachine(null, sb.prefabs[0], sb.groundOrigin(&sb.prefabs[0], x, z, 0), 0, false);
    const bp = &sb.machines[m].blueprint;
    const glow = bp.findDevice("glow").?;
    const breath = bp.findDevice("breath").?;
    try run(&sb, &camera, .{}, .{}, 5);
    try std.testing.expectEqual(@as(f32, 0), sb.machines[m].machine.outputs[glow][2]);
    sb.press = sb.findDevice(m, "switch").?;
    try run(&sb, &camera, .{}, .{}, 5);
    // For four seconds the lamp follows the script, one step behind it, breathing 0.1..1.
    var lo: f32 = 1;
    var hi: f32 = 0;
    for (0..240) |_| {
        const script_before = sb.machines[m].machine.outputs[breath][4];
        try run(&sb, &camera, .{}, .{}, 1);
        const lit = sb.machines[m].machine.outputs[glow][2];
        try std.testing.expectApproxEqAbs(script_before, lit, 1e-5);
        lo = @min(lo, lit);
        hi = @max(hi, lit);
    }
    try std.testing.expect(lo < 0.15 and hi > 0.95);
    try std.testing.expectEqual(@as(u64, 0), sb.scripts.stats.traps);

    // Saves record the mod. A world without it loads the machine but reports the missing mod,
    // and the script reads 0 (dark lamp) until the mod is installed.
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"glowworks\"") != null);
    var bare_camera: Camera = .{};
    var bare: Sandbox = undefined;
    try bare.init(std.testing.allocator, sb.seed, &catalog, &bare_camera);
    defer bare.deinit();
    try bare.restore(std.testing.allocator, bytes, &bare_camera);
    try std.testing.expectEqual(@as(usize, 1), bare.mod_warnings);
    try run(&bare, &bare_camera, .{}, .{}, 5);
    try std.testing.expectEqual(@as(f32, 0), bare.machines[m].machine.outputs[glow][2]);
    try std.testing.expect(bare.scripts.stats.missing > 0);
    // A different design under the mod's blueprint name is a conflict; the identical one is not.
    bare.prefabs[0].devices[bare.prefabs[0].findDevice("glow").?].watts = 41;
    try std.testing.expectError(error.NameConflict, bare.installMod(&pkg));
    bare.prefabs[0].devices[bare.prefabs[0].findDevice("glow").?].watts = 40;
    try bare.installMod(&pkg);
    try std.testing.expectEqual(@as(usize, 1), bare.prefab_count);
    try run(&bare, &bare_camera, .{}, .{}, 5);
    try std.testing.expect(bare.machines[m].machine.outputs[glow][2] > 0.05);
}

test "every bridge style is built, stood on along lanes and walkways, and keeps its style through a save" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    // The district's own roads show every buildable style.
    for (@import("BridgeTool.zig").buildable) |style| {
        const present = for (catalog.district.edges) |e| {
            if (e.style == style) break true;
        } else false;
        try std.testing.expect(present);
    }
    try std.testing.expect(catalog.district.building_count >= 12);
    for (@import("BridgeTool.zig").buildable) |style| {
        const edge: District.Edge = .{ .a = 0, .b = 3, .style = style };
        const slot = try sb.addBridge(edge);
        const s = District.span(&catalog.district, edge);
        const d = R.sub(s.b, s.a);
        const right = R.normalize(.{ d[2], 0, -d[0] });
        for ([_]f32{ 0.2, 0.5, 0.8 }) |t| for ([_]f32{ -5, -1.75, 1.75, 5 }) |x| {
            const deck = R.add(s.point(t), R.scale(right, x));
            sb.player = .{ .feet = R.add(deck, .{ 0, 0.3, 0 }) };
            camera.position = sb.player.eye();
            try run(&sb, &camera, .{}, .{}, 20);
            try std.testing.expect(sb.player.grounded);
            try std.testing.expectApproxEqAbs(deck[1], sb.player.feet[1], 0.1);
            try std.testing.expect(R.length(R.sub(.{ sb.player.feet[0], 0, sb.player.feet[2] }, .{ deck[0], 0, deck[2] })) < 0.1);
        };
        const bytes = try sb.save(std.testing.allocator, camera);
        defer std.testing.allocator.free(bytes);
        sb.removeBridge(slot);
        try sb.restore(std.testing.allocator, bytes, &camera);
        try std.testing.expectEqual(style, sb.bridges[slot].?.edge.style);
        sb.removeBridge(slot);
    }
}

test "blueprint reload preserves open door state and local edits, rejects layout changes atomically" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const guid = catalog.guidOf(.blueprint, "powered_door").?;
    const door = sb.findDevice(0, "door").?.device;
    const toggle = sb.findDevice(0, "toggle").?.device;
    const body = sb.machines[0].devices[door];
    sb.machines[0].machine.state[door] = 1;
    sb.machines[0].machine.state[toggle] = 1;
    var local = catalog.content.powered_door.*;
    local.devices[0].watts = 321;
    const custom = try sb.spawnMachine(null, local, .{ 900, 40, 900 }, 0, true);
    var replacement = catalog.content.powered_door.*;
    replacement.devices[0].watts = 400;
    replacement.devices[door].speed = 2;
    try std.testing.expectEqual(@as(usize, 1), try sb.reloadBlueprint(&catalog, guid, &replacement));
    try std.testing.expectEqual(@as(f32, 400), catalog.content.powered_door.devices[0].watts);
    try std.testing.expectEqual(@as(f32, 400), sb.machines[0].blueprint.devices[0].watts);
    try std.testing.expectEqual(@as(f32, 321), sb.machines[custom].blueprint.devices[0].watts);
    try std.testing.expectEqual(body, sb.machines[0].devices[door]);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[0].machine.state[door]);
    try run(&sb, &camera, .{}, .{}, 10);
    try std.testing.expectEqual(@as(f32, 1), sb.machines[0].machine.state[door]);
    replacement.devices[door].travel[0] += 1;
    try std.testing.expectError(error.PhysicalLayoutChanged, sb.reloadBlueprint(&catalog, guid, &replacement));
    try std.testing.expectApproxEqAbs(@as(f32, 2.9), catalog.content.powered_door.devices[door].travel[0], 0.001);
    try std.testing.expectEqual(body, sb.machines[0].devices[door]);
    // An unchanged vehicle from the watcher's first scan is a no-op.
    try std.testing.expectEqual(@as(usize, 0), try sb.reloadBlueprint(&catalog, catalog.guidOf(.blueprint, "rover").?, catalog.content.rover));
    // Model size changes also update existing crate collision without moving the body.
    const pos = sb.physics.position(sb.crates[0]).?;
    const half = sb.crateHalf();
    var model = try @import("../asset/Model.zig").decode(std.testing.allocator, @embedFile("crate.hwmesh"));
    for (model.mesh.vertices) |*v| for (&v.position) |*c| {
        c.* *= 2;
    };
    model.computeBounds();
    _ = try catalog.replaceModel(std.testing.allocator, catalog.guidOf(.model, "crate").?, model);
    sb.refreshCrateGeometry();
    try std.testing.expectEqual(pos, sb.physics.position(sb.crates[0]).?);
    for (half, sb.physics.halfExtents(sb.crates[0]).?) |x, y| try std.testing.expectApproxEqAbs(x * 2, y, 0.001);
}

test "hover cars stay where they were left across a save, and pickups stay collected" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.progress.vehicles = 1 << @intFromEnum(@import("../vehicle/Designs.zig").Design.skimmer);
    Frontier.refresh(&sb);
    try std.testing.expect(sb.garage.cars[0] != null and sb.garage.cars[1] == null);
    // Move it far from its pad and turn it.
    const moved: Physics.Vec3 = .{ 30, 40, 60 };
    sb.garage.place(sb.seed, spawn, sb.catalog, .skimmer, moved, 1.2);
    // Collect the first pickup.
    sb.progress.picked.set(0);
    const bytes = try sb.save(std.testing.allocator, camera);
    defer std.testing.allocator.free(bytes);
    sb.garage = .{};
    sb.progress.picked = .initEmpty();
    try sb.restore(std.testing.allocator, bytes, &camera);
    const car = sb.garage.cars[0].?.flyer;
    try std.testing.expectApproxEqAbs(moved[0], car.body.pos.x, 1e-3);
    try std.testing.expectApproxEqAbs(moved[2], car.body.pos.z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), car.heading(), 1e-3);
    try std.testing.expect(sb.progress.picked.isSet(0));
    try std.testing.expect(sb.garage.cars[1] == null);
}

test "a guest fires the party's blaster with the trigger and downs a drone" {
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    sb.joinGuest(0);
    sb.progress.weapons = 1 << @intFromEnum(@import("../combat/Weapon.zig").WeaponKind.blaster);
    try run(&sb, &camera, .{}, .{}, 30);
    const g = &sb.guests[0];
    // Aim level so the drone stands in open air, not under the slope ahead.
    g.camera.pitch = 0;
    const eye = g.player.eye();
    const f = g.camera.forward();
    // A weak drone 4 m along the guest's aim (clear of the crate row beside the spawn).
    sb.enemies.units[0] = .{ .kind = .drone, .nest = 0, .position = .{ eye.x() + f.x() * 4, eye.y() + f.y() * 4, eye.z() + f.z() * 4 }, .health = 10, .orbit = 0 };
    g.fire = true;
    try run(&sb, &camera, .{}, .{}, 1);
    g.fire = false;
    var downed = false;
    for (0..30) |_| {
        // Hold the drone still in front of the guest; only the shot matters here.
        if (sb.enemies.units[0]) |*u| {
            u.position = .{ eye.x() + f.x() * 4, eye.y() + f.y() * 4, eye.z() + f.z() * 4 };
            u.velocity = @splat(0);
        } else downed = true;
        try run(&sb, &camera, .{}, .{}, 1);
    }
    try std.testing.expect(downed or sb.enemies.units[0] == null);
    try std.testing.expectEqual(@as(?@import("../combat/Weapon.zig").WeaponKind, .blaster), sb.combat.arsenals[1].active);
}
