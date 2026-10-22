//! Structure definitions: a block footprint plus behaviour modules (turret, launcher, shield, drill,
//! drone bay, store, field, power, workshop), with a stable id, a validated JSON form and a cost.
//! This is the one format for starter turrets and shields, a player's captured creations
//! (`saves/structures/<id>.json`) and mod-supplied structures. The modules are a closed set of Zig
//! behaviours configured by numbers, so a data file can never run code. See
//! docs/plans/automation-and-defense.md. The behaviours themselves arrive in later steps; this file
//! is only data, checked limits and cost.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Blocks = @import("Blocks.zig");
const Materials = @import("Materials.zig");
const Prefabs = @import("Prefabs.zig");

pub const max_modules = 4;
pub const max_id = 32;
pub const max_name = 24;
pub const library_capacity = 24;

pub const Kind = enum { turret, launcher, shield, drill, bay, store, field, power, workshop };
pub const kind_count = enum_compat.fields(Kind).len;

/// One behaviour and its numbers. Which fields a kind uses, and their limits, are in `limits`;
/// every unused field must be zero.
///
/// | kind | range | damage | rate | amount | power |
/// | turret | reach m | per shot | shots per s | - | draw W |
/// | launcher | reach m | per missile | missiles per s | missiles held | draw W |
/// | shield | dome radius m | - | recharge hp per s | hit points | draw W |
/// | drill | node search m | - | ore per hour | - | draw W |
/// | bay | work radius m | - | - | drones | draw W |
/// | store | - | - | - | capacity | - |
/// | field | radius m | - | growth multiplier | - | draw W |
/// | power | - | - | - | - | output W |
/// | workshop | - | - | conversions per hour | - | draw W |
pub const Module = struct {
    kind: Kind,
    range: f32 = 0,
    damage: f32 = 0,
    rate: f32 = 0,
    amount: f32 = 0,
    power: f32 = 0,
};

const Range = [2]f32;
const none: Range = .{ 0, 0 };
const Limits = struct { range: Range, damage: Range, rate: Range, amount: Range, power: Range };

fn limits(kind: Kind) Limits {
    return switch (kind) {
        .turret => .{ .range = .{ 8, 60 }, .damage = .{ 2, 80 }, .rate = .{ 0.5, 10 }, .amount = none, .power = .{ 0, 400 } },
        .launcher => .{ .range = .{ 20, 120 }, .damage = .{ 20, 400 }, .rate = .{ 0.1, 2 }, .amount = .{ 2, 24 }, .power = .{ 0, 400 } },
        .shield => .{ .range = .{ 6, 40 }, .damage = none, .rate = .{ 1, 100 }, .amount = .{ 100, 5000 }, .power = .{ 0, 1000 } },
        .drill => .{ .range = .{ 1, 8 }, .damage = none, .rate = .{ 1, 120 }, .amount = none, .power = .{ 0, 600 } },
        .bay => .{ .range = .{ 20, 200 }, .damage = none, .rate = none, .amount = .{ 1, 8 }, .power = .{ 0, 200 } },
        .store => .{ .range = none, .damage = none, .rate = none, .amount = .{ 100, 10000 }, .power = none },
        .field => .{ .range = .{ 3, 24 }, .damage = none, .rate = .{ 0.5, 3 }, .amount = none, .power = .{ 0, 100 } },
        .power => .{ .range = none, .damage = none, .rate = none, .amount = none, .power = .{ 50, 2000 } },
        .workshop => .{ .range = none, .damage = none, .rate = .{ 1, 60 }, .amount = none, .power = .{ 0, 400 } },
    };
}

fn within(value: f32, r: Range) bool {
    if (!std.math.isFinite(value)) return false;
    if (r[0] == 0 and r[1] == 0) return value == 0;
    return value >= r[0] and value <= r[1];
}

/// Whether every number is inside its kind's limits (and unused ones are zero).
pub fn moduleOk(m: Module) bool {
    const l = limits(m.kind);
    return within(m.range, l.range) and within(m.damage, l.damage) and within(m.rate, l.rate) and within(m.amount, l.amount) and within(m.power, l.power);
}

/// What a structure costs besides its blocks: scrap and parts, from its modules' strength.
pub const Price = struct { scrap: u32 = 0, parts: u32 = 0 };

pub fn modulePrice(m: Module) Price {
    const f = struct {
        fn n(x: f32) u32 {
            return @intFromFloat(@max(0, @round(x)));
        }
    }.n;
    return switch (m.kind) {
        .turret => .{ .scrap = 20 + f(m.damage * m.rate * 1.5 + m.range * 0.5), .parts = 1 + f(m.damage * m.rate / 12) },
        .launcher => .{ .scrap = 60 + f(m.damage * m.rate * 1.2 + m.range * 0.4 + m.amount * 4), .parts = 4 + f(m.damage * m.rate / 8 + m.amount / 4) },
        .shield => .{ .scrap = 40 + f(m.amount / 8 + m.range * 2 + m.rate), .parts = 3 + f(m.amount / 200 + m.range / 6) },
        .drill => .{ .scrap = 30 + f(m.rate * 1.5), .parts = 2 + f(m.rate / 10) },
        .bay => .{ .scrap = 25 + f(m.amount * 12), .parts = 2 + f(m.amount * 2) },
        .store => .{ .scrap = 10 + f(m.amount / 100) },
        .field => .{ .scrap = 15 + f(m.range * 3 * m.rate), .parts = 1 },
        .power => .{ .scrap = 20 + f(m.power / 25), .parts = 1 + f(m.power / 400) },
        .workshop => .{ .scrap = 40 + f(m.rate * 2), .parts = 3 + f(m.rate / 8) },
    };
}

/// A sensible starting module of each kind, used when a capture is saved as that kind. Always
/// inside the limits (a test checks), and a good base to edit in a data file.
pub fn defaultModule(kind: Kind) Module {
    return switch (kind) {
        .turret => .{ .kind = .turret, .range = 24, .damage = 8, .rate = 4 },
        .launcher => .{ .kind = .launcher, .range = 90, .damage = 120, .rate = 0.4, .amount = 8, .power = 80 },
        .shield => .{ .kind = .shield, .range = 16, .rate = 20, .amount = 800, .power = 200 },
        .drill => .{ .kind = .drill, .range = 4, .rate = 30, .power = 100 },
        .bay => .{ .kind = .bay, .range = 80, .amount = 4, .power = 60 },
        .store => .{ .kind = .store, .amount = 1000 },
        .field => .{ .kind = .field, .range = 10, .rate = 1, .power = 20 },
        .power => .{ .kind = .power, .power = 400 },
        .workshop => .{ .kind = .workshop, .rate = 12, .power = 100 },
    };
}

pub const Cost = struct {
    blocks: [Materials.count]u32 = @splat(0),
    scrap: u32 = 0,
    parts: u32 = 0,
};

pub const Def = struct {
    id_buf: [max_id]u8 = @splat(0),
    id_len: u8 = 0,
    name_buf: [max_name]u8 = @splat(0),
    name_len: u8 = 0,
    size: [3]u8 = .{ 0, 0, 0 },
    cell_len: u16 = 0,
    cells: [Prefabs.max_cells]Prefabs.Placed = undefined,
    module_len: u8 = 0,
    modules: [max_modules]Module = undefined,

    pub fn id(self: *const Def) []const u8 {
        return self.id_buf[0..self.id_len];
    }
    pub fn name(self: *const Def) []const u8 {
        return self.name_buf[0..self.name_len];
    }
    pub fn moduleSlice(self: *const Def) []const Module {
        return self.modules[0..self.module_len];
    }
    pub fn cellSlice(self: *const Def) []const Prefabs.Placed {
        return self.cells[0..self.cell_len];
    }
    /// The footprint as a block prefab, for the placement code that stamps prefabs. Borrows `self`.
    pub fn prefab(self: *const Def) Prefabs.Prefab {
        return .{ .name = self.name(), .size = self.size, .cells = self.cellSlice() };
    }
    pub fn find(self: *const Def, kind: Kind) ?Module {
        for (self.moduleSlice()) |m| if (m.kind == kind) return m;
        return null;
    }

    /// Blocks of the footprint plus the modules' scrap and parts.
    pub fn cost(self: *const Def) Cost {
        var c: Cost = .{ .blocks = Prefabs.cost(self.prefab()) };
        for (self.moduleSlice()) |m| {
            const p = modulePrice(m);
            c.scrap += p.scrap;
            c.parts += p.parts;
        }
        return c;
    }
};

pub const Error = error{ Malformed, BadId, BadName, BadSize, BadCell, DuplicateCell, UnknownMaterial, BadModule, DuplicateModule, TooMany };

pub fn validId(text: []const u8) bool {
    if (text.len < 3 or text.len > max_id) return false;
    for (text) |ch| if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '_' or ch == '.' or ch == '-')) return false;
    return std.ascii.isLower(text[0]);
}

fn validName(text: []const u8) bool {
    if (text.len == 0 or text.len > max_name) return false;
    for (text) |ch| if (ch < 0x20 or ch >= 0x7f) return false;
    return true;
}

/// Checks a finished definition: id, name, size, cells inside it (no repeats), modules in limits
/// (no kind twice). Everything that loads or creates a `Def` goes through here.
pub fn check(def: *const Def) Error!void {
    if (!validId(def.id())) return error.BadId;
    if (!validName(def.name())) return error.BadName;
    for (def.size) |s| if (s == 0 or s > Prefabs.max_side) return error.BadSize;
    if (def.cell_len > Prefabs.max_cells) return error.TooMany;
    for (def.cellSlice(), 0..) |p, i| {
        if (p.x >= def.size[0] or p.y >= def.size[1] or p.z >= def.size[2]) return error.BadCell;
        const shape = @intFromEnum(p.cell.shape);
        if (shape == 0 or shape > Blocks.placeable_shapes.len) return error.BadCell;
        if (p.cell.material >= Materials.count) return error.UnknownMaterial;
        if (p.cell.flags != 0) return error.BadCell;
        for (def.cellSlice()[0..i]) |q| if (q.x == p.x and q.y == p.y and q.z == p.z) return error.DuplicateCell;
    }
    if (def.module_len > max_modules) return error.TooMany;
    for (def.moduleSlice(), 0..) |m, i| {
        if (!moduleOk(m)) return error.BadModule;
        for (def.moduleSlice()[0..i]) |q| if (q.kind == m.kind) return error.DuplicateModule;
    }
}

// ---------------------------------------------------------------- JSON

pub const CellDoc = struct { x: u8, y: u8, z: u8, shape: u8, rot: u8 = 0, material: []const u8 };
pub const Doc = struct {
    id: []const u8,
    name: []const u8,
    size: [3]u8,
    cells: []const CellDoc,
    modules: []const Module = &.{},
};

pub fn toDoc(def: *const Def, arena: std.mem.Allocator) !Doc {
    const cells = try arena.alloc(CellDoc, def.cell_len);
    for (cells, def.cellSlice()) |*d, p| d.* = .{ .x = p.x, .y = p.y, .z = p.z, .shape = @intFromEnum(p.cell.shape), .rot = p.cell.rot, .material = Materials.all[p.cell.material].id };
    return .{ .id = def.id(), .name = def.name(), .size = def.size, .cells = cells, .modules = def.moduleSlice() };
}

pub fn fromDoc(doc: Doc) Error!Def {
    if (doc.id.len > max_id) return error.BadId;
    if (doc.name.len > max_name) return error.BadName;
    if (doc.cells.len > Prefabs.max_cells) return error.TooMany;
    if (doc.modules.len > max_modules) return error.TooMany;
    var def: Def = .{ .size = doc.size, .id_len = @intCast(doc.id.len), .name_len = @intCast(doc.name.len), .cell_len = @intCast(doc.cells.len), .module_len = @intCast(doc.modules.len) };
    @memcpy(def.id_buf[0..doc.id.len], doc.id);
    @memcpy(def.name_buf[0..doc.name.len], doc.name);
    for (doc.cells, def.cells[0..doc.cells.len]) |c, *out| {
        const material = materialIndex(c.material) orelse return error.UnknownMaterial;
        if (c.rot > 3) return error.BadCell;
        if (c.shape == 0 or c.shape > Blocks.placeable_shapes.len) return error.BadCell;
        out.* = .{ .x = c.x, .y = c.y, .z = c.z, .cell = .{ .shape = @enumFromInt(c.shape), .rot = @intCast(c.rot), .material = material } };
    }
    @memcpy(def.modules[0..doc.modules.len], doc.modules);
    try check(&def);
    return def;
}

fn materialIndex(id: []const u8) ?u6 {
    for (Materials.all, 0..) |m, i| if (std.mem.eql(u8, m.id, id)) return @intCast(i);
    return null;
}

pub fn encode(allocator: std.mem.Allocator, def: *const Def) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return std.json.Stringify.valueAlloc(allocator, try toDoc(def, arena.allocator()), .{ .whitespace = .indent_2 });
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!Def {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const doc = std.json.parseFromSliceLeaky(Doc, arena.allocator(), bytes, .{}) catch return error.Malformed;
    return fromDoc(doc);
}

// ---------------------------------------------------------------- starters

fn blockAt(def: *Def, x: u8, y: u8, z: u8, shape: Blocks.Shape, rot: u2, material: []const u8) void {
    def.cells[def.cell_len] = .{ .x = x, .y = y, .z = z, .cell = .{ .shape = shape, .rot = rot, .material = materialIndex(material).? } };
    def.cell_len += 1;
}

fn begin(id: []const u8, label: []const u8, size: [3]u8) Def {
    var def: Def = .{ .size = size, .id_len = @intCast(id.len), .name_len = @intCast(label.len) };
    @memcpy(def.id_buf[0..id.len], id);
    @memcpy(def.name_buf[0..label.len], label);
    return def;
}

fn module(def: *Def, m: Module) void {
    def.modules[def.module_len] = m;
    def.module_len += 1;
}

pub const starter_count = 4;

/// The built-in defensive structures. Exact materials, so they look the same in any style.
pub fn starter(index: usize) Def {
    switch (index) {
        0 => {
            var d = begin("hw.sentry_turret", "SENTRY TURRET", .{ 1, 3, 1 });
            blockAt(&d, 0, 0, 0, .cube, 0, "castle.iron");
            blockAt(&d, 0, 1, 0, .cube, 0, "castle.dark_stone");
            blockAt(&d, 0, 2, 0, .slab, 0, "castle.iron");
            module(&d, .{ .kind = .turret, .range = 24, .damage = 8, .rate = 4 });
            return d;
        },
        1 => {
            var d = begin("hw.heavy_turret", "HEAVY TURRET", .{ 3, 4, 3 });
            for (0..3) |x| for (0..3) |z| blockAt(&d, @intCast(x), 0, @intCast(z), .cube, 0, "castle.stone");
            blockAt(&d, 1, 1, 1, .cube, 0, "castle.dark_stone");
            blockAt(&d, 1, 2, 1, .cube, 0, "castle.iron");
            blockAt(&d, 1, 3, 1, .slab, 0, "castle.iron");
            blockAt(&d, 0, 1, 1, .ramp, 3, "castle.dark_stone");
            blockAt(&d, 2, 1, 1, .ramp, 1, "castle.dark_stone");
            module(&d, .{ .kind = .turret, .range = 45, .damage = 30, .rate = 1.5, .power = 120 });
            return d;
        },
        2 => {
            var d = begin("hw.shield_generator", "SHIELD GENERATOR", .{ 3, 5, 3 });
            for (0..3) |x| for (0..3) |z| blockAt(&d, @intCast(x), 0, @intCast(z), .cube, 0, "castle.dark_stone");
            blockAt(&d, 1, 1, 1, .cube, 0, "castle.iron");
            blockAt(&d, 1, 2, 1, .cube, 0, "eco.solar");
            blockAt(&d, 1, 3, 1, .cube, 0, "castle.iron");
            blockAt(&d, 1, 4, 1, .cube, 0, "eco.glass");
            module(&d, .{ .kind = .shield, .range = 16, .amount = 800, .rate = 20, .power = 200 });
            return d;
        },
        3 => {
            var d = begin("hw.missile_launcher", "MISSILE LAUNCHER", .{ 2, 3, 3 });
            for (0..2) |x| for (0..3) |z| blockAt(&d, @intCast(x), 0, @intCast(z), .cube, 0, "castle.iron");
            for (0..2) |x| blockAt(&d, @intCast(x), 1, 0, .cube, 0, "castle.dark_stone");
            for (0..2) |x| blockAt(&d, @intCast(x), 1, 1, .ramp, 0, "castle.dark_stone");
            for (0..2) |x| blockAt(&d, @intCast(x), 2, 0, .cube, 0, "castle.banner");
            module(&d, .{ .kind = .launcher, .range = 90, .damage = 120, .rate = 0.4, .amount = 8, .power = 80 });
            return d;
        },
        else => unreachable,
    }
}

// ---------------------------------------------------------------- library

/// Every structure a player can place: the starters, then loaded files and captures. Ids are unique.
pub const Library = struct {
    defs: [library_capacity]Def = undefined,
    len: usize = 0,

    pub fn initStarters(self: *Library) void {
        self.len = 0;
        for (0..starter_count) |i| {
            self.defs[self.len] = starter(i);
            self.len += 1;
        }
    }

    pub fn find(self: *const Library, id: []const u8) ?usize {
        for (self.defs[0..self.len], 0..) |*d, i| if (std.mem.eql(u8, d.id(), id)) return i;
        return null;
    }

    pub fn get(self: *const Library, index: usize) *const Def {
        return &self.defs[index];
    }

    /// Adds a checked definition; an existing user entry with the same id is replaced (saving a
    /// capture again), but a starter id is never overwritten.
    pub fn put(self: *Library, def: Def) error{ Full, ReservedId, Invalid }!usize {
        check(&def) catch return error.Invalid;
        if (self.find(def.id())) |i| {
            if (i < starter_count) return error.ReservedId;
            self.defs[i] = def;
            return i;
        }
        if (self.len == library_capacity) return error.Full;
        self.defs[self.len] = def;
        self.len += 1;
        return self.len - 1;
    }
};

/// A capture's id from its name: lower case, letters and digits, other runs become one underscore.
pub fn slugFor(out: *[max_id]u8, label: []const u8) []const u8 {
    var n: usize = 0;
    var gap = false;
    const prefix = "user.";
    @memcpy(out[0..prefix.len], prefix);
    n = prefix.len;
    for (label) |ch| {
        if (n == max_id - 4) break;
        const c = std.ascii.toLower(ch);
        if (std.ascii.isAlphanumeric(c)) {
            if (gap and n > prefix.len) {
                out[n] = '_';
                n += 1;
            }
            gap = false;
            out[n] = c;
            n += 1;
        } else gap = true;
    }
    if (n == prefix.len) {
        @memcpy(out[n .. n + 4], "item");
        n += 4;
    }
    return out[0..n];
}

// ---------------------------------------------------------------- tests

test "every starter is valid, fits its size, and costs blocks, scrap and parts" {
    for (0..starter_count) |i| {
        const d = starter(i);
        try check(&d);
        try std.testing.expect(d.module_len >= 1);
        const c = d.cost();
        var blocks: u32 = 0;
        for (c.blocks) |b| blocks += b;
        try std.testing.expectEqual(@as(u32, d.cell_len), blocks);
        try std.testing.expect(c.scrap > 0 and c.parts > 0);
    }
    // A bigger gun costs more.
    const sentry = starter(0).cost();
    const heavy = starter(1).cost();
    try std.testing.expect(heavy.scrap > sentry.scrap and heavy.parts > sentry.parts);
    const missile = starter(3).cost();
    try std.testing.expect(missile.scrap > heavy.scrap);
}

test "a structure survives JSON unchanged, and the library finds it by id" {
    const a = std.testing.allocator;
    for (0..starter_count) |i| {
        const d = starter(i);
        const bytes = try encode(a, &d);
        defer a.free(bytes);
        const back = try decode(a, bytes);
        try std.testing.expectEqualStrings(d.id(), back.id());
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&d.size), std.mem.asBytes(&back.size));
        try std.testing.expectEqual(d.cell_len, back.cell_len);
        for (d.cellSlice(), back.cellSlice()) |p, q| try std.testing.expectEqual(p, q);
        try std.testing.expectEqualDeep(d.moduleSlice(), back.moduleSlice());
    }
    var lib: Library = .{};
    lib.initStarters();
    try std.testing.expectEqual(@as(?usize, 2), lib.find("hw.shield_generator"));
    try std.testing.expect(lib.find("hw.nothing") == null);
}

test "bad files are refused with a reason, and every refusal leaves the library alone" {
    const a = std.testing.allocator;
    const good = starter(0);
    const bytes = try encode(a, &good);
    defer a.free(bytes);
    const swap = struct {
        fn run(alloc: std.mem.Allocator, src: []const u8, from: []const u8, to: []const u8) ![]u8 {
            return std.mem.replaceOwned(u8, alloc, src, from, to);
        }
    }.run;
    const cases = [_]struct { from: []const u8, to: []const u8, want: Error }{
        .{ .from = "hw.sentry_turret", .to = "Bad Id!", .want = error.BadId },
        .{ .from = "SENTRY TURRET", .to = "", .want = error.BadName },
        .{ .from = "castle.iron", .to = "castle.unobtainium", .want = error.UnknownMaterial },
        .{ .from = "\"range\": 24", .to = "\"range\": 900", .want = error.BadModule },
        .{ .from = "\"power\": 0", .to = "\"power\": -5", .want = error.BadModule },
        .{ .from = "\"shape\": 2", .to = "\"shape\": 9", .want = error.BadCell },
        .{ .from = "\"y\": 2", .to = "\"y\": 7", .want = error.BadCell },
        .{ .from = "\"y\": 1", .to = "\"y\": 0", .want = error.DuplicateCell },
        .{ .from = "\"kind\": \"turret\"", .to = "\"kind\": \"teleporter\"", .want = error.Malformed },
    };
    for (cases) |c| {
        const edited = try swap(a, bytes, c.from, c.to);
        defer a.free(edited);
        try std.testing.expectError(c.want, decode(a, edited));
    }
    try std.testing.expectError(error.Malformed, decode(a, "{ not json"));
    // Two modules of one kind, and a library that will not take a starter's id.
    var twice = good;
    twice.modules[1] = twice.modules[0];
    twice.module_len = 2;
    try std.testing.expectError(error.DuplicateModule, check(&twice));
    var lib: Library = .{};
    lib.initStarters();
    try std.testing.expectError(error.ReservedId, lib.put(good));
    var mine = good;
    mine.id_len = 9;
    @memcpy(mine.id_buf[0..9], "user.mine");
    const at = try lib.put(mine);
    try std.testing.expectEqual(@as(usize, starter_count), at);
    // Putting the same id again replaces it; it never adds a second.
    try std.testing.expectEqual(at, try lib.put(mine));
    try std.testing.expectEqual(@as(usize, starter_count + 1), lib.len);
    var broken = mine;
    broken.size = .{ 0, 1, 1 };
    try std.testing.expectError(error.Invalid, lib.put(broken));
    try std.testing.expectEqual(@as(usize, starter_count + 1), lib.len);
}

test "every module kind has limits that admit its own middle and refuse nonsense" {
    inline for (enum_compat.fields(Kind)) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const l = limits(kind);
        const mid = struct {
            fn of(r: Range) f32 {
                return (r[0] + r[1]) / 2;
            }
        }.of;
        const m: Module = .{ .kind = kind, .range = mid(l.range), .damage = mid(l.damage), .rate = mid(l.rate), .amount = mid(l.amount), .power = mid(l.power) };
        try std.testing.expect(moduleOk(m));
        var bad = m;
        bad.rate = std.math.nan(f32);
        try std.testing.expect(!moduleOk(bad));
        // An unused field must be zero: nothing may smuggle a number into a kind that ignores it.
        var extra = m;
        extra.damage = if (l.damage[1] == 0) 5 else 1e9;
        try std.testing.expect(!moduleOk(extra));
        const price = modulePrice(m);
        try std.testing.expect(price.scrap > 0);
        try std.testing.expect(moduleOk(defaultModule(kind)));
    }
}

test "capture names become ids" {
    var buffer: [max_id]u8 = undefined;
    try std.testing.expectEqualStrings("user.my_big_gun", slugFor(&buffer, "My Big Gun!"));
    try std.testing.expectEqualStrings("user.item", slugFor(&buffer, "???"));
    try std.testing.expect(validId(slugFor(&buffer, "A very very very long structure name indeed")));
}
