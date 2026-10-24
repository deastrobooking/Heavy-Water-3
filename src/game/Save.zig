const std = @import("std");
const Seed = @import("../procedural/Seed.zig");
const Catalog = @import("../asset/Catalog.zig");
const Modifications = @import("../world/Modifications.zig");
const Player = @import("Player.zig");
const Blueprint = @import("../machine/Blueprint.zig");
const Profile = @import("Profile.zig");
const Market = @import("../city/Market.zig");
const Kit = @import("Kit.zig");
const District = @import("../procedural/District.zig");

/// JSON save document. Any change to its meaning bumps `format_version`. A save is only loaded
/// into a world with the same seed, generator version, and content version, unless an explicit
/// migration preserves its stable references; old worlds must not silently regenerate.
/// v2 added machine state; v3 vehicle bodies; v4 made the save describe the whole world:
/// every placed machine as a full blueprint document (so rewiring persists) with its origin
/// and quarter-turn yaw, and every crate; v5 added the captured prefab library; v6 the player's
/// name and appearance; v7 constructed bridge edges and the district generator version; v8 adds
/// the market wallet (scrap, salvaged parts) and each stall's stock with the day it was stocked;
/// v9 tags Rootdeep shrine machines (their doors, latches, and sealed vault persist as machine
/// state; the solver-verified layout is regenerated from the seed); v10 records installed mods;
/// v11 records each player bridge's structural style; v12 records the sprint course's best lap;
/// v13 saves every player on the team on their own (`members`: their character and their kit of
/// upgrades, gear, pickups, pets and wallet), leaving only what the team shares in `progress`;
/// v14 adds per-ranger combat experience to each kit; v15 adds mod character ids to profiles;
/// v16 adds each kit's fabricated field droid and its independent upgrade experience; v17
/// migrates generator-5 saves to giant flora; v18 migrates generator-6 saves to new tree forms;
/// v19 migrates generator-7 saves to harvestable young trees; v20 adds metro district geometry;
/// v21 adds steampunk root galleries without changing plaza or bridge identities; v22 adds small
/// pine scatter and Detroit's Gothic/industrial skyline; v23 widens Detroit River, adds Belle
/// Isle and Windsor bridges, and preserves plaza, player bridge, and collected-object identities;
/// v24 corrects Rootway gallery geometry while retaining district and bridge identities;
/// v25 adds the selectable Captain test-mesh body style to saved player profiles; v26 stores
/// each ranger's Detroit discoveries independently in their kit;
/// v27 adds the sculpted-terrain tiles (absent means untouched ground); v28 adds player-built
/// block sections (absent means none); v29 adds each ranger's block stock to their kit (absent
/// means the starter stock); v30 adds crops growing on tilled soil (absent means none); v31 adds
/// owned/equipped space fighter frames (older saves keep the Kestrel); v32 adds each profile's
/// face mark and eye colour (absent means none and the default eyes); v33 adds the team's
/// structure designs and the structures built (absent means only the starters and none built);
/// v34 adds player-placed living-sap decorations; v35 adds the team's colony (stockpile, settlers,
/// research; absent means an empty colony) and each ranger's held ore (absent means none).
/// Format 13 is the oldest supported save; its four-player kits default combat XP to zero.
/// Older saves are rejected deliberately. Bumping the current format does not move this floor.
pub const format_version: u32 = 35;
pub const min_supported_format: u32 = 13;
pub const default_path = "saves/quicksave.json";
pub const max_bytes = 4 << 20;

/// One tile of sculpted terrain: its tile coordinates and run-length text (`TerrainEdit.encodeTile`).
pub const TerrainTile = struct { x: i32, z: i32, data: []const u8 };
/// One 16 m section of player-built blocks: section coordinates and run-length text (`Blocks.encodeSection`).
pub const BlockSection = struct { x: i32, y: i32, z: i32, data: []const u8 };

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
    /// Market ware this machine was placed from (removing it returns the kit).
    kit: ?u8 = null,
    /// Rootdeep shrine index, for the generated shrine machines.
    shrine: ?u8 = null,
};
/// A vehicle chassis: pose and velocities.
pub const BodyState = struct { position: [3]f32, orientation: [4]f32, linear: [3]f32, angular: [3]f32 };
pub const ModState = struct { name: []const u8, version: []const u8 };
pub const FighterState = struct { position: [3]f32, yaw: f32 };
pub const CarState = struct { design: @import("../vehicle/Designs.zig").Design, position: [3]f32, yaw: f32 };
pub const PlayerState = struct { feet: [3]f32, yaw: f32, pitch: f32, mode: Player.Mode };
/// One player on the team, by screen slot: the character they play (`profile`; for P1 the same
/// as the document's `profile`), their own ranger while they play a Wildkin hero (`own`), and
/// their kit.
pub const MemberState = struct { slot: u8, profile: Profile.Doc, own: ?Profile.Doc = null, kit: Kit.Doc };
pub const Document = struct {
    format: u32 = format_version,
    seed: u64,
    generator: u32 = Seed.generator_version,
    content: u32 = Catalog.content_version,
    arbor_generator: u32 = @import("../procedural/Arbor.zig").generator_version,
    district_generator: u32 = @import("../procedural/District.zig").generator_version,
    bridges: []const @import("../procedural/District.zig").Edge = &.{},
    tick: u64,
    player: PlayerState,
    profile: Profile.Doc,
    props: []const PropState,
    collected: []const Modifications.ObjectRef,
    machines: []const MachineState,
    prefabs: []const Blueprint.Doc,
    /// Legacy format 12's shared wallet; format 13 and newer keep wallets in `members`.
    wallet: Market.Wallet = .{},
    /// Every player on the team (format 13).
    members: []const MemberState = &.{},
    /// Where each hover car was left (its centre of mass) and its heading.
    cars: []const CarState = &.{},
    /// Where the Kestrel was left, if fabricated.
    fighter: ?FighterState = null,
    /// Suit upgrades, owned armor and story flags; absent in older saves (a fresh start).
    progress: @import("Progress.zig").Doc = .{},
    /// Best completed time on the seeded sprint circuit; zero means no lap has been recorded.
    race_best: f32 = 0,
    market_day: u64,
    market_stock: []const [Market.ware_count]u8,
    /// Mods installed when saved (name and "major.minor.patch").
    mods: []const ModState = &.{},
    /// Sculpted terrain (format 27).
    terrain: []const TerrainTile = &.{},
    /// Player-built blocks (format 28).
    blocks: []const BlockSection = &.{},
    /// Crops in the fields (format 30).
    crops: []const @import("Farm.zig").Doc = &.{},
    /// Structure designs made by the team, and the structures built (format 33).
    structures: []const @import("../build/Structures.zig").Doc = &.{},
    placed: []const @import("Outpost.zig").PlacedDoc = &.{},
    /// Player-placed living-sap plants (format 34).
    decorations: []const @import("Decor.zig").Doc = &.{},
    /// The team's colony: stockpile, settlers and research (format 35). Each player's unbanked
    /// ore is in their kit.
    colony: @import("Colony.zig").Doc = .{},
};

pub fn encode(allocator: std.mem.Allocator, doc: Document) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, doc, .{ .whitespace = .indent_2 });
}

pub const LoadError = error{ UnsupportedSaveFormat, SeedMismatch, GeneratorMismatch, ContentMismatch, InvalidSave };

/// Parses and validates the document's own structure (versions, ranges, finite values).
/// Blueprints and machine state are validated by the caller before anything is applied.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, seed: u64, prop_count: usize, machine_slots: usize) !std.json.Parsed(Document) {
    var parsed = std.json.parseFromSlice(Document, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidSave;
    errdefer parsed.deinit();
    const doc = parsed.value;
    if (doc.format > format_version or doc.format < min_supported_format) return error.UnsupportedSaveFormat;
    if (doc.seed != seed) return error.SeedMismatch;
    if (doc.generator != Seed.generator_version) {
        if ((doc.generator == 5 or doc.generator == 6 or doc.generator == 7 or doc.generator == 8) and doc.format < format_version) {
            // Candidate IDs did not move, so saved removals stay attached to their new visuals.
            parsed.value.generator = Seed.generator_version;
            parsed.value.format = format_version;
        } else return error.GeneratorMismatch;
    }
    if (doc.district_generator != District.generator_version) {
        if ((doc.district_generator == 3 or doc.district_generator == 4 or doc.district_generator == 5 or doc.district_generator == 6 or doc.district_generator == 7) and doc.format < format_version) {
            // Plaza and player-built bridge identities stay stable; Detroit terrain and structures regenerate.
            parsed.value.district_generator = District.generator_version;
            parsed.value.format = format_version;
        } else return error.GeneratorMismatch;
    }
    if (doc.content != Catalog.content_version) return error.ContentMismatch;
    if (doc.arbor_generator != @import("../procedural/Arbor.zig").generator_version) {
        if (doc.arbor_generator == 1 or doc.arbor_generator == 2) {
            // Arbor node identities are regenerated from the world seed; saves contain no node
            // references, so the denser crown can safely replace earlier skeletons.
            parsed.value.arbor_generator = @import("../procedural/Arbor.zig").generator_version;
            parsed.value.format = format_version;
        } else return error.GeneratorMismatch;
    }
    if (doc.bridges.len > @import("../procedural/District.zig").max_bridges) return error.InvalidSave;
    if (doc.collected.len > Modifications.capacity or doc.props.len > prop_count) return error.InvalidSave;
    for (doc.player.feet) |v| if (!finite(v)) return error.InvalidSave;
    if (!finite(doc.player.yaw) or !finite(doc.player.pitch)) return error.InvalidSave;
    if (doc.machines.len > machine_slots) return error.InvalidSave;
    if (doc.mods.len > 16) return error.InvalidSave;
    if (doc.terrain.len > @import("../world/TerrainEdit.zig").tile_capacity) return error.InvalidSave;
    if (doc.blocks.len > @import("../build/Blocks.zig").section_capacity) return error.InvalidSave;
    if (doc.members.len > 4) return error.InvalidSave;
    for (doc.members, 0..) |m, i| {
        if (m.slot >= 4) return error.InvalidSave;
        for (doc.members[0..i]) |other| if (other.slot == m.slot) return error.InvalidSave;
    }
    if (!finite(doc.race_best) or doc.race_best < 0) return error.InvalidSave;
    if (doc.cars.len > @import("../vehicle/Designs.zig").count) return error.InvalidSave;
    if (doc.fighter) |f| {
        for (f.position) |v| if (!finite(v)) return error.InvalidSave;
        if (!finite(f.yaw)) return error.InvalidSave;
    }
    for (doc.cars) |c| {
        for (c.position) |v| if (!finite(v)) return error.InvalidSave;
        if (!finite(c.yaw)) return error.InvalidSave;
    }
    for (doc.machines, 0..) |m, i| {
        if (m.slot >= machine_slots or m.yaw > 3) return error.InvalidSave;
        for (doc.machines[0..i]) |other| if (other.slot == m.slot) return error.InvalidSave;
        for (m.origin) |v| if (!finite(v)) return error.InvalidSave;
        if (m.kit) |k| if (k >= Market.ware_count) return error.InvalidSave;
        if (m.shrine) |k| {
            if (k >= 2) return error.InvalidSave;
            for (doc.machines[0..i]) |other| if (other.shrine == k) return error.InvalidSave;
        }
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

/// A player's own character file, `saves/rangers/<NAME>.json`: their ranger and their kit,
/// written with every team save. Any player can load one into their seat, so a character can be
/// played by a teammate, or carried into another team's world.
pub const ranger_dir = "saves/rangers";
pub const ranger_format: u32 = 1;
pub const RangerFile = struct { format: u32 = ranger_format, profile: Profile.Doc, kit: Kit.Doc };
pub const Ranger = struct { profile: Profile, kit: Kit };

/// `saves/rangers/<NAME>.json`, with spaces in the name as underscores.
pub fn rangerPath(buffer: []u8, name: []const u8) ![]const u8 {
    const path = try std.fmt.bufPrint(buffer, "{s}/{s}.json", .{ ranger_dir, name });
    for (path[ranger_dir.len + 1 ..]) |*c| if (c.* == ' ') {
        c.* = '_';
    };
    return path;
}

pub fn decodeRanger(allocator: std.mem.Allocator, bytes: []const u8) !Ranger {
    const parsed = std.json.parseFromSlice(RangerFile, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.InvalidSave;
    defer parsed.deinit();
    if (parsed.value.format != ranger_format) return error.UnsupportedSaveFormat;
    return .{ .profile = Profile.fromDoc(parsed.value.profile) catch return error.InvalidSave, .kit = Kit.fromDoc(parsed.value.kit) catch return error.InvalidSave };
}

test "ranger files round-trip a character and their kit, and name their path" {
    const allocator = std.testing.allocator;
    var profile: Profile = .{};
    try profile.setName("Sora Vale");
    var kit: Kit = .{ .wallet = .{ .scrap = 321 } };
    _ = kit.freePet(.moth);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), RangerFile{ .profile = profile.toDoc(), .kit = try kit.toDoc(arena.allocator()) }, .{});
    const back = try decodeRanger(allocator, bytes);
    try std.testing.expectEqualStrings("SORA VALE", back.profile.name());
    try std.testing.expectEqual(@as(u32, 321), back.kit.wallet.scrap);
    try std.testing.expect(back.kit.hasPet(.moth));
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("saves/rangers/SORA_VALE.json", try rangerPath(&buffer, back.profile.name()));
    try std.testing.expectError(error.InvalidSave, decodeRanger(allocator, "{\"format\":1}"));
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
    const doc: Document = .{ .seed = 0xFFFF_FFFF_FFFF_FFF1, .tick = 9, .player = .{ .feet = .{ 0, 1, 0 }, .yaw = 0.5, .pitch = -0.1, .mode = .walk }, .profile = (Profile{}).toDoc(), .props = &props, .collected = &collected, .machines = &machines, .prefabs = &.{}, .members = &.{.{ .slot = 2, .profile = (Profile{}).toDoc(), .kit = .{ .wallet = .{ .scrap = 40, .parts = 2 } } }}, .race_best = 93.25, .market_day = 3, .market_stock = &.{ .{ 1, 0, 2 }, .{ 0, 0, 1 }, .{ 3, 3, 3 } } };
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
    try std.testing.expectEqual(Market.Wallet{ .scrap = 40, .parts = 2 }, back.value.members[0].kit.wallet);
    try std.testing.expectEqual(@as(u8, 2), back.value.members[0].slot);
    try std.testing.expectEqualSlices([Market.ware_count]u8, doc.market_stock, back.value.market_stock);
    try std.testing.expectEqual(doc.race_best, back.value.race_best);
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes, doc.seed, 4, 2));

    var invalid_best_doc = doc;
    invalid_best_doc.race_best = -1;
    const invalid_best = try encode(allocator, invalid_best_doc);
    defer allocator.free(invalid_best);
    try std.testing.expectError(error.InvalidSave, decode(allocator, invalid_best, doc.seed, 4, 8));

    // Format 12 predates per-player kits and is deliberately outside the supported floor.
    var v12_doc = doc;
    v12_doc.format = min_supported_format - 1;
    const v12 = try encode(allocator, v12_doc);
    defer allocator.free(v12);
    try std.testing.expectError(error.UnsupportedSaveFormat, decode(allocator, v12, doc.seed, 4, 8));
    // Format 16 adds droid progression; format 15 modded profiles still load unchanged.
    var modded = doc;
    var modded_profile = Profile{};
    modded_profile.mod.set(.hair_style, @import("CharacterContent.zig").Id.parse("emberwear.flame_crest").?);
    modded.profile = modded_profile.toDoc();
    const modded_bytes = try encode(allocator, modded);
    defer allocator.free(modded_bytes);
    const modded_back = try decode(allocator, modded_bytes, doc.seed, 4, 8);
    defer modded_back.deinit();
    try std.testing.expectEqualDeep(modded_profile, try Profile.fromDoc(modded_back.value.profile));
    var v14_doc = doc;
    v14_doc.format = 14;
    const v14 = try encode(allocator, v14_doc);
    defer allocator.free(v14);
    const v14_back = try decode(allocator, v14, doc.seed, 4, 8);
    defer v14_back.deinit();
    try std.testing.expect((try Profile.fromDoc(v14_back.value.profile)).mod.get(.hair_style) == null);
    var future_doc = doc;
    future_doc.format = format_version + 1;
    const future = try encode(allocator, future_doc);
    defer allocator.free(future);
    try std.testing.expectError(error.UnsupportedSaveFormat, decode(allocator, future, doc.seed, 4, 8));
    var twice = doc;
    twice.members = &.{ .{ .slot = 1, .profile = (Profile{}).toDoc(), .kit = .{} }, .{ .slot = 1, .profile = (Profile{}).toDoc(), .kit = .{} } };
    const dup = try encode(allocator, twice);
    defer allocator.free(dup);
    try std.testing.expectError(error.InvalidSave, decode(allocator, dup, doc.seed, 4, 8));

    try std.testing.expectError(error.SeedMismatch, decode(allocator, bytes, 1, 4, 8));
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes, doc.seed, 1, 8));
    try std.testing.expectError(error.InvalidSave, decode(allocator, bytes[0 .. bytes.len / 2], doc.seed, 4, 8));
    const old = try std.mem.replaceOwned(u8, allocator, bytes, std.fmt.comptimePrint("\"generator\": {d}", .{Seed.generator_version}), "\"generator\": 2");
    defer allocator.free(old);
    try std.testing.expectError(error.GeneratorMismatch, decode(allocator, old, doc.seed, 4, 8));
    const old_format = try std.mem.replaceOwned(u8, allocator, bytes, std.fmt.comptimePrint("\"format\": {d}", .{format_version}), "\"format\": 11");
    defer allocator.free(old_format);
    try std.testing.expectError(error.UnsupportedSaveFormat, decode(allocator, old_format, doc.seed, 4, 8));
}

test "every supported save format has a checked-in round-trip fixture" {
    const allocator = std.testing.allocator;
    inline for (min_supported_format..format_version + 1) |version| {
        const fixture = @embedFile(std.fmt.comptimePrint("fixtures/save-v{d}.json", .{version}));
        {
            const parsed = try decode(allocator, fixture, 42, 4, 8);
            defer parsed.deinit();
            try std.testing.expectEqual(version, parsed.value.format);
            try std.testing.expectEqual(@as(usize, 1), parsed.value.members.len);
            const bytes = try encode(allocator, parsed.value);
            defer allocator.free(bytes);
            const round_trip = try decode(allocator, bytes, 42, 4, 8);
            defer round_trip.deinit();
            try std.testing.expectEqualDeep(parsed.value, round_trip.value);
        }
    }
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
