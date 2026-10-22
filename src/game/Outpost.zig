//! Placed structures: the library of structure definitions (`build/Structures.zig`) and every
//! instance a player has built from it. Placing stamps the footprint into the block grid (the
//! same rules as a prefab), charges blocks from the builder's stock and scrap and parts from their
//! wallet for the modules, and records the instance. Demolishing takes the whole structure back,
//! returning every block and half the scrap and parts. Behaviours (turret, shield, drill...) read
//! these instances in later steps. See docs/plans/automation-and-defense.md.
const std = @import("std");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");
const Prefabs = @import("../build/Prefabs.zig");
const Structures = @import("../build/Structures.zig");
const BlockTool = @import("BlockTool.zig");
const Sandbox = @import("Sandbox.zig");

pub const max_placed = 64;
/// Seconds of a player's company at an outpost before the first raid, and between raids.
pub const raid_first: f32 = 150;
pub const raid_every: f32 = 240;

pub const Instance = struct {
    id_buf: [Structures.max_id]u8 = @splat(0),
    id_len: u8 = 0,
    /// Lowest corner cell of the turned footprint.
    origin: [3]i32 = .{ 0, 0, 0 },
    rot: u2 = 0,
    /// The player slot that built it.
    owner: u8 = 0,
    // Runtime state, not part of the design: hit points, the gun's cooldown, the shield's hit
    // points and quiet time since its last hit, missiles held, and the hit flash.
    health: f32 = 0,
    cooldown: f32 = 0,
    shield: f32 = 0,
    shield_quiet: f32 = 0,
    ammo: f32 = 0,
    flash: f32 = 0,

    pub fn id(self: *const Instance) []const u8 {
        return self.id_buf[0..self.id_len];
    }
};

/// `health` is a fraction of the design's maximum; negative (absent in older saves) means whole.
pub const PlacedDoc = struct { id: []const u8, x: i32, y: i32, z: i32, rot: u8 = 0, owner: u8 = 0, health: f32 = -1 };

pub const State = struct {
    library: *Structures.Library,
    placed: [max_placed]Instance = undefined,
    len: usize = 0,
    /// A capture waiting for App to write it to `saves/structures/` (App owns the file access).
    export_index: ?usize = null,
    /// The structures the Hive can see this step (near a player): their index among `placed`.
    target_map: [max_placed]u8 = undefined,
    target_len: usize = 0,
    /// Seconds until the next raid on a defended outpost, and whether it was announced.
    raid_timer: f32 = raid_first,
    raid_warned: bool = false,

    pub fn create(allocator: std.mem.Allocator) !State {
        const library = try allocator.create(Structures.Library);
        library.initStarters();
        return .{ .library = library };
    }

    pub fn destroy(self: *State, allocator: std.mem.Allocator) void {
        allocator.destroy(self.library);
    }

    /// Back to the starters and no instances (a new world or a load).
    pub fn reset(self: *State) void {
        self.library.initStarters();
        self.len = 0;
        self.export_index = null;
    }

    pub fn slice(self: *const State) []const Instance {
        return self.placed[0..self.len];
    }
};

/// The refund fraction of a demolished structure's scrap and parts.
pub const refund_scrap_percent = 50;

/// Build structure `index` of the library centred on `at`, turned `rot` quarter turns. Checked in
/// full first: a refusal changes nothing.
pub fn place(sb: *Sandbox, slot: usize, index: usize, rot: u2, at: [3]i32) !void {
    const out = &sb.outpost;
    if (index >= out.library.len) return;
    const def = out.library.get(index);
    if (out.len == max_placed) return sb.sayTo(slot, "at most {d} structures", .{max_placed});
    const cost = def.cost();
    const wallet = &sb.kits[slot].wallet;
    if (wallet.scrap < cost.scrap or wallet.parts < cost.parts) {
        return sb.sayTo(slot, "{s} needs {d} scrap and {d} parts, you hold {d} and {d}", .{ def.name(), cost.scrap, cost.parts, wallet.scrap, wallet.parts });
    }
    const origin = BlockTool.stampOrigin(def.prefab(), rot, at);
    if (!try BlockTool.stampPlaced(sb, slot, def.prefab(), rot, at)) return;
    wallet.scrap -= cost.scrap;
    wallet.parts -= cost.parts;
    var inst: Instance = .{ .origin = origin, .rot = rot, .owner = @intCast(slot), .id_len = def.id_len };
    inst.id_buf = def.id_buf;
    initRuntime(&inst, def, 1);
    out.placed[out.len] = inst;
    out.len += 1;
}

/// Whole hit points (or `fraction` of them), a full shield and a full rack of missiles.
pub fn initRuntime(inst: *Instance, def: *const Structures.Def, fraction: f32) void {
    inst.health = def.maxHealth() * std.math.clamp(fraction, 0.01, 1);
    inst.shield = if (def.find(.shield)) |m| m.amount else 0;
    inst.ammo = if (def.find(.launcher)) |m| m.amount else 0;
    inst.cooldown = 0;
    inst.shield_quiet = 0;
    inst.flash = 0;
}

fn cellOf(inst: *const Instance, def: *const Structures.Def, p: Prefabs.Placed) Prefabs.Placed {
    const t = Prefabs.turned(p, def.size, inst.rot);
    return .{ .x = t.x, .y = t.y, .z = t.z, .cell = t.cell };
}

/// The index of the placed structure whose footprint holds block cell `c`, if any.
pub fn structureAt(sb: *const Sandbox, c: [3]i32) ?usize {
    const out = &sb.outpost;
    for (out.slice(), 0..) |*inst, i| {
        const found = out.library.find(inst.id()) orelse continue;
        const def = out.library.get(found);
        for (def.cellSlice()) |p| {
            const t = cellOf(inst, def, p);
            if (inst.origin[0] + t.x == c[0] and inst.origin[1] + t.y == c[1] and inst.origin[2] + t.z == c[2]) return i;
        }
    }
    return null;
}

/// Clear structure `i`'s blocks and forget it, with no refund (a wreck: `Defense` pays that).
pub fn removeCells(sb: *Sandbox, i: usize) !void {
    const out = &sb.outpost;
    const inst = out.placed[i];
    if (out.library.find(inst.id())) |found| {
        const def = out.library.get(found);
        for (def.cellSlice()) |p| {
            const t = cellOf(&inst, def, p);
            const x = inst.origin[0] + t.x;
            const y = inst.origin[1] + t.y;
            const z = inst.origin[2] + t.z;
            const old = sb.block_world.blocks.get(x, y, z);
            if (!old.isEmpty() and !old.isAuthored()) try sb.block_world.blocks.set(x, y, z, .empty);
        }
    }
    var k = i;
    while (k + 1 < out.len) : (k += 1) out.placed[k] = out.placed[k + 1];
    out.len -= 1;
    try sb.syncBlocks();
}

/// Take structure `i` apart: its blocks go back to the remover, and half its scrap and parts.
pub fn demolish(sb: *Sandbox, slot: usize, i: usize) !void {
    const out = &sb.outpost;
    const inst = out.placed[i];
    const found = out.library.find(inst.id()) orelse return sb.sayTo(slot, "that structure's design is missing", .{});
    const def = out.library.get(found);
    const kit = &sb.kits[slot];
    for (def.cellSlice()) |p| {
        const t = cellOf(&inst, def, p);
        const x = inst.origin[0] + t.x;
        const y = inst.origin[1] + t.y;
        const z = inst.origin[2] + t.z;
        const old = sb.block_world.blocks.get(x, y, z);
        if (old.isEmpty() or old.isAuthored()) continue;
        try sb.block_world.blocks.set(x, y, z, .empty);
        kit.blocks[old.material] +|= 1;
    }
    const cost = def.cost();
    kit.wallet.scrap +|= cost.scrap * refund_scrap_percent / 100;
    kit.wallet.parts +|= cost.parts * refund_scrap_percent / 100;
    var k = i;
    while (k + 1 < out.len) : (k += 1) out.placed[k] = out.placed[k + 1];
    out.len -= 1;
    try sb.syncBlocks();
    sb.sayTo(slot, "took apart {s}: blocks returned, half the scrap and parts refunded", .{def.name()});
}

/// Save the player's clipboard as a new structure with `kind` as its module (null: none), named
/// "<KIND> n", add it to the library and queue its data file. Returns the library index.
pub fn capture(sb: *Sandbox, slot: usize, kind: ?Structures.Kind) !?usize {
    const clip = &sb.block_clips[slot];
    if (clip.len == 0) {
        sb.sayTo(slot, "copy some blocks first (SHIFT+P twice)", .{});
        return null;
    }
    const out = &sb.outpost;
    var name_buf: [Structures.max_name]u8 = undefined;
    var id_buf: [Structures.max_id]u8 = undefined;
    var upper: [12]u8 = undefined;
    const base: []const u8 = if (kind) |k| @tagName(k) else "build";
    const word = std.ascii.upperString(&upper, base[0..@min(base.len, upper.len)]);
    // The first "<KIND> n" whose id the library does not hold yet.
    var n: usize = 1;
    var name: []const u8 = "";
    var id: []const u8 = "";
    while (n < 1000) : (n += 1) {
        name = std.fmt.bufPrint(&name_buf, "{s} {d}", .{ word, n }) catch unreachable;
        id = Structures.slugFor(&id_buf, name);
        if (out.library.find(id) == null) break;
    }
    var def: Structures.Def = .{ .size = clip.size, .id_len = @intCast(id.len), .name_len = @intCast(name.len), .cell_len = @intCast(clip.len) };
    @memcpy(def.id_buf[0..id.len], id);
    @memcpy(def.name_buf[0..name.len], name);
    @memcpy(def.cells[0..clip.len], clip.cells[0..clip.len]);
    if (kind) |k| {
        def.modules[0] = Structures.defaultModule(k);
        def.module_len = 1;
    }
    const index = out.library.put(def) catch |err| {
        sb.sayTo(slot, "could not save the structure: {s}", .{switch (err) {
            error.Full => "the library is full",
            error.ReservedId => "that id is reserved",
            error.Invalid => "the design is not valid",
        }});
        return null;
    };
    out.export_index = index;
    const cost = def.cost();
    sb.sayTo(slot, "saved {s}: costs {d} scrap and {d} parts", .{ def.name(), cost.scrap, cost.parts });
    return index;
}

// ---------------------------------------------------------------- saving

pub const SaveDocs = struct { defs: []const Structures.Doc, placed: []const PlacedDoc };

/// The user-made definitions (not the starters) and every placed instance, for the save.
pub fn toDocs(self: *const State, arena: std.mem.Allocator) !SaveDocs {
    const lib = self.library;
    const defs = try arena.alloc(Structures.Doc, lib.len - Structures.starter_count);
    for (defs, lib.defs[Structures.starter_count..lib.len]) |*d, *def| d.* = try Structures.toDoc(def, arena);
    const placed = try arena.alloc(PlacedDoc, self.len);
    for (placed, self.slice()) |*d, *inst| {
        const max = if (self.library.find(inst.id())) |f| self.library.get(f).maxHealth() else 0;
        d.* = .{ .id = inst.id(), .x = inst.origin[0], .y = inst.origin[1], .z = inst.origin[2], .rot = inst.rot, .owner = inst.owner, .health = if (max > 0) inst.health / max else -1 };
    }
    return .{ .defs = defs, .placed = placed };
}

/// Whether the documents could be restored: every definition valid and unique, every instance
/// well formed and within the cap. Checked before anything is changed.
pub fn validate(defs: []const Structures.Doc, placed: []const PlacedDoc) bool {
    if (defs.len > Structures.library_capacity - Structures.starter_count or placed.len > max_placed) return false;
    for (defs, 0..) |d, i| {
        const def = Structures.fromDoc(d) catch return false;
        // A starter's id is reserved, and ids are unique.
        for (0..Structures.starter_count) |s| if (std.mem.eql(u8, def.id(), Structures.starter(s).id())) return false;
        for (defs[0..i]) |other| if (std.mem.eql(u8, other.id, d.id)) return false;
    }
    for (placed) |p| {
        if (!Structures.validId(p.id) or p.rot > 3 or p.owner >= Sandbox.max_players) return false;
        if (!std.math.isFinite(p.health) or p.health > 1) return false;
        if (@abs(p.x) > 1 << 20 or @abs(p.y) > 1 << 12 or @abs(p.z) > 1 << 20) return false;
    }
    return true;
}

/// Restore from documents that passed `validate`.
pub fn restore(self: *State, defs: []const Structures.Doc, placed: []const PlacedDoc) void {
    // Designs already in the library (starters, files) stay: they are only data.
    self.len = 0;
    self.export_index = null;
    for (defs) |d| _ = self.library.put(Structures.fromDoc(d) catch continue) catch continue;
    for (placed) |p| {
        var inst: Instance = .{ .origin = .{ p.x, p.y, p.z }, .rot = @intCast(p.rot), .owner = p.owner, .id_len = @intCast(p.id.len) };
        @memcpy(inst.id_buf[0..p.id.len], p.id);
        if (self.library.find(p.id)) |f| initRuntime(&inst, self.library.get(f), if (p.health < 0) 1 else p.health) else inst.health = 100;
        self.placed[self.len] = inst;
        self.len += 1;
    }
}

// ---------------------------------------------------------------- data files

pub const files_dir = "saves/structures";

/// Write the structure's data file (`saves/structures/<id>.json`) so it can be shared.
pub fn writeFile(io: std.Io, allocator: std.mem.Allocator, def: *const Structures.Def) void {
    const Save = @import("Save.zig");
    const bytes = Structures.encode(allocator, def) catch return;
    defer allocator.free(bytes);
    var path: [files_dir.len + Structures.max_id + 8]u8 = undefined;
    const name = std.fmt.bufPrint(&path, "{s}/{s}.json", .{ files_dir, def.id() }) catch return;
    Save.writeFile(io, name, bytes) catch {};
}

/// Add every valid structure file in `saves/structures/` to the library. Bad files are skipped.
pub fn loadFiles(io: std.Io, allocator: std.mem.Allocator, library: *Structures.Library) void {
    const Save = @import("Save.zig");
    var dir = std.Io.Dir.cwd().openDir(io, files_dir, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        var path: [files_dir.len + 80]u8 = undefined;
        const name = std.fmt.bufPrint(&path, "{s}/{s}", .{ files_dir, entry.name }) catch continue;
        const bytes = Save.readFile(io, allocator, name) catch continue;
        defer allocator.free(bytes);
        const def = Structures.decode(allocator, bytes) catch continue;
        _ = library.put(def) catch {};
    }
}
