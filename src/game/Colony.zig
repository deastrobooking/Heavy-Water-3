//! The team's colony: the shared stockpile, settlers and science research. A light, Civilization-
//! style layer over the placed structures (`Outpost`): drills fill the stockpile with ore, fields
//! feed settlers, habitats house them, labs turn settlers' work into research, and research unlocks
//! tools and structures up to an orbital mining station. It advances in whole settlement hours
//! (`hour_seconds` of play) with integer arithmetic, so a reload agrees with the run that saved it.
//! This file is pure: `Inputs` is what the structures add up to this hour (gathered by
//! `Mining.colonyInputs`), so the rules test without a world. Personal ore stays in each `Kit`
//! until its player deposits it. See docs/plans/colony-mining-research.md.
const std = @import("std");
const enum_compat = @import("enum_compat");

/// Seconds of play per settlement hour.
pub const hour_seconds: f32 = 60;
/// Hours made up at most in one step (a long hitch must not stall a frame).
pub const max_catch_up = 4;

pub const Ore = enum { iron, copper, crystal };
pub const ore_count = enum_compat.fields(Ore).len;

pub fn oreName(o: Ore) []const u8 {
    return switch (o) {
        .iron => "IRON",
        .copper => "COPPER",
        .crystal => "LUMEN CRYSTAL",
    };
}

pub const Tech = enum { plasma_cutter, deep_drill, hydroponics, habitats, fusion_cells, rocketry, orbital_mining };
pub const tech_count = enum_compat.fields(Tech).len;

pub const TechInfo = struct {
    name: []const u8,
    /// What it unlocks, for the research panel.
    gives: []const u8,
    points: u32,
    ore: [ore_count]u32,
    requires: ?Tech = null,
};

pub fn info(t: Tech) TechInfo {
    return switch (t) {
        .plasma_cutter => .{ .name = "PLASMA CUTTING", .gives = "the plasma cutter (key 8): mines ore four times faster, overheats", .points = 20, .ore = .{ 10, 0, 0 } },
        .deep_drill => .{ .name = "DEEP DRILLING", .gives = "drill stations mine half again as much", .points = 40, .ore = .{ 20, 10, 0 } },
        .hydroponics => .{ .name = "HYDROPONICS", .gives = "farm fields grow half again as much food", .points = 40, .ore = .{ 0, 15, 0 } },
        .habitats => .{ .name = "HABITAT MODULES", .gives = "habitats house half again as many settlers", .points = 60, .ore = .{ 30, 10, 0 } },
        .fusion_cells => .{ .name = "FUSION CELLS", .gives = "power structures give half again as much", .points = 80, .ore = .{ 0, 20, 10 }, .requires = .deep_drill },
        .rocketry => .{ .name = "ROCKETRY", .gives = "the launch pad structure", .points = 120, .ore = .{ 40, 0, 20 }, .requires = .fusion_cells },
        .orbital_mining => .{ .name = "ORBITAL MINING", .gives = "launch pads run a mining station in orbit", .points = 200, .ore = .{ 0, 0, 30 }, .requires = .rocketry },
    };
}

/// What the colony's structures add up to this hour. Rates are per settlement hour, already scaled
/// by power; `Mining.colonyInputs` gathers them.
pub const Inputs = struct {
    /// Ore the drills raise this hour, before the settler and research bonuses.
    drilled: [ore_count]f32 = @splat(0),
    /// Food the fields grow this hour, before hydroponics.
    food: f32 = 0,
    /// Beds in habitats, before habitat modules.
    beds: u32 = 0,
    /// Research points the labs make this hour, before the settler bonus.
    research: f32 = 0,
    /// Launch pads in the colony (an orbital station each, once researched).
    pads: u32 = 0,
};

/// What an orbital station sends down per hour, per launch pad.
pub const station_yield = [ore_count]u32{ 6, 2, 3 };

pub const State = struct {
    stockpile: [ore_count]u32 = @splat(0),
    food: u32 = 0,
    settlers: u32 = 0,
    research_points: u32 = 0,
    researched: [tech_count]bool = @splat(false),
    /// What the labs are working toward; null picks the first available.
    target: ?Tech = null,
    hours: u64 = 0,
    /// Seconds into the current hour.
    clock: f32 = 0,
    /// Fractions carried between hours, so slow producers still pay out.
    carry_ore: [ore_count]f32 = @splat(0),
    carry_food: f32 = 0,
    carry_research: f32 = 0,
    /// The last hour's report, for the HUD.
    last: Report = .{},

    pub fn has(self: *const State, t: Tech) bool {
        return self.researched[@intFromEnum(t)];
    }

    /// Whether `t` can be researched now (not done, and what it needs is done).
    pub fn available(self: *const State, t: Tech) bool {
        if (self.has(t)) return false;
        const need = info(t).requires orelse return true;
        return self.has(need);
    }

    /// The tech the labs work on: the chosen one, else the first available.
    pub fn current(self: *const State) ?Tech {
        if (self.target) |t| if (self.available(t)) return t;
        for (0..tech_count) |i| {
            const t: Tech = @enumFromInt(i);
            if (self.available(t)) return t;
        }
        return null;
    }

    /// Cycle the research target through what is available.
    pub fn nextTarget(self: *State) void {
        const start: usize = if (self.current()) |t| @intFromEnum(t) + 1 else 0;
        for (0..tech_count) |k| {
            const t: Tech = @enumFromInt((start + k) % tech_count);
            if (self.available(t)) {
                self.target = t;
                return;
            }
        }
        self.target = null;
    }

    /// Housing after habitat modules.
    pub fn beds(self: *const State, in: Inputs) u32 {
        return if (self.has(.habitats)) in.beds * 3 / 2 else in.beds;
    }
};

/// What one hour did.
pub const Report = struct {
    mined: [ore_count]u32 = @splat(0),
    grown: u32 = 0,
    eaten: u32 = 0,
    research: u32 = 0,
    arrived: u32 = 0,
    left: u32 = 0,
    finished: ?Tech = null,
};

/// The share settlers add to drills and labs, in percent: two per settler, up to half again.
pub fn workBonus(settlers: u32) u32 {
    return @min(50, settlers * 2);
}

/// Food each settler eats per hour, as settlers per unit: four settlers share one hay.
pub const settlers_per_food = 4;

fn payout(rate: f32, carry: *f32) u32 {
    const total = @max(0, rate) + carry.*;
    const whole = @floor(total);
    carry.* = total - whole;
    return @intFromFloat(whole);
}

/// Run one settlement hour.
pub fn hour(s: *State, in: Inputs) Report {
    var r: Report = .{};
    const bonus: f32 = @as(f32, @floatFromInt(100 + workBonus(s.settlers))) / 100;
    const drill: f32 = if (s.has(.deep_drill)) 1.5 else 1;
    for (0..ore_count) |o| {
        var mined = payout(in.drilled[o] * drill * bonus, &s.carry_ore[o]);
        if (s.has(.orbital_mining)) mined += station_yield[o] * in.pads;
        s.stockpile[o] += mined;
        r.mined[o] = mined;
    }
    r.grown = payout(in.food * (if (s.has(.hydroponics)) @as(f32, 1.5) else 1), &s.carry_food);
    s.food += r.grown;

    // Settlers eat first; a short larder sends a tenth of them away (at least one).
    const hunger = (s.settlers + settlers_per_food - 1) / settlers_per_food;
    if (s.food >= hunger) {
        s.food -= hunger;
        r.eaten = hunger;
        // One newcomer an hour while there is a spare bed and food for them.
        if (s.settlers < s.beds(in) and s.food > 0) {
            s.settlers += 1;
            r.arrived = 1;
        }
    } else {
        r.eaten = s.food;
        s.food = 0;
        r.left = @max(1, s.settlers / 10);
        s.settlers -= r.left;
    }
    // More settlers than beds (a habitat was lost): the extra ones leave.
    if (s.settlers > s.beds(in)) {
        r.left += s.settlers - s.beds(in);
        s.settlers = s.beds(in);
    }

    r.research = payout(in.research * bonus, &s.carry_research);
    s.research_points += r.research;
    if (s.current()) |t| {
        const need = info(t);
        var afford = s.research_points >= need.points;
        for (0..ore_count) |o| afford = afford and s.stockpile[o] >= need.ore[o];
        if (afford) {
            s.research_points -= need.points;
            for (0..ore_count) |o| s.stockpile[o] -= need.ore[o];
            s.researched[@intFromEnum(t)] = true;
            if (s.target == t) s.target = null;
            r.finished = t;
        }
    }
    s.hours += 1;
    s.last = r;
    return r;
}

/// Advance the clock by `dt`; runs each hour that completes (at most `max_catch_up`) with `in`.
/// Returns how many hours ran, and the last one's report in `out`.
pub fn advance(s: *State, dt: f32, in: Inputs, out: *Report) u32 {
    s.clock += @max(0, dt);
    var ran: u32 = 0;
    while (s.clock >= hour_seconds and ran < max_catch_up) : (ran += 1) {
        s.clock -= hour_seconds;
        out.* = hour(s, in);
    }
    if (s.clock >= hour_seconds) s.clock = @mod(s.clock, hour_seconds);
    return ran;
}

/// Move a player's ore into the stockpile (their explicit contribution).
pub fn deposit(s: *State, held: *[ore_count]u32) u32 {
    var moved: u32 = 0;
    for (0..ore_count) |o| {
        s.stockpile[o] += held[o];
        moved += held[o];
        held[o] = 0;
    }
    return moved;
}

/// Saved form. Absent in older saves: an empty colony.
pub const Doc = struct {
    stockpile: [ore_count]u32 = @splat(0),
    food: u32 = 0,
    settlers: u32 = 0,
    research_points: u32 = 0,
    /// Tech names.
    researched: []const []const u8 = &.{},
    target: ?[]const u8 = null,
    hours: u64 = 0,
    clock: f32 = 0,
};

pub fn toDoc(s: *const State, names: *[tech_count][]const u8) Doc {
    var n: usize = 0;
    for (0..tech_count) |i| if (s.researched[i]) {
        names[n] = @tagName(@as(Tech, @enumFromInt(i)));
        n += 1;
    };
    return .{ .stockpile = s.stockpile, .food = s.food, .settlers = s.settlers, .research_points = s.research_points, .researched = names[0..n], .target = if (s.target) |t| @tagName(t) else null, .hours = s.hours, .clock = s.clock };
}

/// A colony from its document, checked in full first: unknown techs or a bad clock refuse it.
pub fn fromDoc(doc: Doc) error{InvalidSave}!State {
    if (!std.math.isFinite(doc.clock) or doc.clock < 0 or doc.clock >= hour_seconds) return error.InvalidSave;
    var s: State = .{ .stockpile = doc.stockpile, .food = doc.food, .settlers = doc.settlers, .research_points = doc.research_points, .hours = doc.hours, .clock = doc.clock };
    for (doc.researched) |name| {
        const t = std.meta.stringToEnum(Tech, name) orelse return error.InvalidSave;
        s.researched[@intFromEnum(t)] = true;
    }
    if (doc.target) |name| s.target = std.meta.stringToEnum(Tech, name) orelse return error.InvalidSave;
    return s;
}

test "drills fill the stockpile, settlers speed them, and fractions carry between hours" {
    var s: State = .{};
    const in: Inputs = .{ .drilled = .{ 2.5, 0, 0 } };
    _ = hour(&s, in);
    _ = hour(&s, in);
    try std.testing.expectEqual(@as(u32, 5), s.stockpile[0]);
    s.settlers = 25;
    s.food = 1000;
    _ = hour(&s, .{ .drilled = .{ 10, 0, 0 }, .beds = 25 });
    // 10 an hour at the full half-again settler bonus.
    try std.testing.expectEqual(@as(u32, 20), s.stockpile[0]);
}

test "settlers arrive one an hour while fed and housed, and leave when the food runs out" {
    var s: State = .{ .food = 2 };
    const in: Inputs = .{ .beds = 2 };
    _ = hour(&s, in);
    try std.testing.expectEqual(@as(u32, 1), s.settlers);
    _ = hour(&s, in);
    try std.testing.expectEqual(@as(u32, 2), s.settlers);
    // Beds full: nobody else comes.
    _ = hour(&s, in);
    try std.testing.expectEqual(@as(u32, 2), s.settlers);
    // The larder is empty now; a settler leaves.
    const r = hour(&s, in);
    try std.testing.expectEqual(@as(u32, 1), r.left);
    try std.testing.expectEqual(@as(u32, 1), s.settlers);
    // A lost habitat sends the extra settlers away.
    s.food = 100;
    _ = hour(&s, .{});
    try std.testing.expectEqual(@as(u32, 0), s.settlers);
}

test "research waits for its points and ore, follows prerequisites, and unlocks in order" {
    var s: State = .{};
    try std.testing.expect(!s.available(.rocketry));
    try std.testing.expectEqual(Tech.plasma_cutter, s.current().?);
    // Points but no iron: it waits, nothing is spent.
    _ = hour(&s, .{ .research = 30 });
    try std.testing.expect(!s.has(.plasma_cutter));
    try std.testing.expectEqual(@as(u32, 30), s.research_points);
    s.stockpile[0] = 10;
    const r = hour(&s, .{});
    try std.testing.expectEqual(Tech.plasma_cutter, r.finished.?);
    try std.testing.expectEqual(@as(u32, 10), s.research_points);
    try std.testing.expectEqual(@as(u32, 0), s.stockpile[0]);
    // A chosen target is kept; cycling skips what is locked or done.
    s.nextTarget();
    try std.testing.expectEqual(Tech.hydroponics, s.current().?);
    for (0..tech_count) |_| {
        s.nextTarget();
        try std.testing.expect(s.current().? != .rocketry and s.current().? != .plasma_cutter);
    }
}

test "orbital mining sends ore down for each launch pad" {
    var s: State = .{};
    s.researched[@intFromEnum(Tech.orbital_mining)] = true;
    _ = hour(&s, .{ .pads = 2 });
    try std.testing.expectEqual(station_yield[0] * 2, s.stockpile[0]);
    try std.testing.expectEqual(station_yield[2] * 2, s.stockpile[2]);
}

test "the clock runs whole hours, bounded per step, and the document round-trips" {
    var s: State = .{};
    var r: Report = .{};
    try std.testing.expectEqual(@as(u32, 0), advance(&s, hour_seconds - 1, .{}, &r));
    try std.testing.expectEqual(@as(u32, 1), advance(&s, 2, .{}, &r));
    try std.testing.expectEqual(@as(u32, max_catch_up), advance(&s, hour_seconds * 10, .{}, &r));
    try std.testing.expect(s.clock < hour_seconds);
    s.researched[@intFromEnum(Tech.deep_drill)] = true;
    s.target = .hydroponics;
    s.stockpile = .{ 4, 5, 6 };
    var names: [tech_count][]const u8 = undefined;
    const back = try fromDoc(toDoc(&s, &names));
    try std.testing.expectEqual(s.stockpile, back.stockpile);
    try std.testing.expectEqual(s.researched, back.researched);
    try std.testing.expectEqual(s.target, back.target);
    try std.testing.expectEqual(s.hours, back.hours);
    try std.testing.expectError(error.InvalidSave, fromDoc(.{ .researched = &.{"warp_drive"} }));
    try std.testing.expectError(error.InvalidSave, fromDoc(.{ .clock = std.math.nan(f32) }));
}

test "a deposit moves every ore into the stockpile" {
    var s: State = .{};
    var held: [ore_count]u32 = .{ 3, 1, 2 };
    try std.testing.expectEqual(@as(u32, 6), deposit(&s, &held));
    try std.testing.expectEqual([ore_count]u32{ 3, 1, 2 }, s.stockpile);
    try std.testing.expectEqual([ore_count]u32{ 0, 0, 0 }, held);
}
