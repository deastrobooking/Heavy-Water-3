//! Shared, data-driven visual kit for Scalari villain frames. Gameplay roles remain in Enemies;
//! this module supplies swappable silhouette modules and the Hive's restrained color language.
const Seed = @import("../procedural/Seed.zig");
const enum_compat = @import("enum_compat");

pub const Part = enum { frame, head, shoulders, arms, legs, back_unit, weapon };
pub const Palette = enum { obsidian, amethyst, rose, war_red, silver };
pub const part_count = enum_compat.fields(Part).len;

pub const Design = struct {
    frame: u8 = 0,
    head: u8 = 0,
    shoulders: u8 = 0,
    arms: u8 = 0,
    legs: u8 = 0,
    back_unit: u8 = 0,
    weapon: u8 = 0,
    palette: Palette = .obsidian,

    pub fn value(self: Design, part: Part) u8 {
        return switch (part) {
            .frame => self.frame,
            .head => self.head,
            .shoulders => self.shoulders,
            .arms => self.arms,
            .legs => self.legs,
            .back_unit => self.back_unit,
            .weapon => self.weapon,
        };
    }

    pub fn cycle(self: *Design, part: Part, direction: i32) void {
        const slot = switch (part) {
            .frame => &self.frame,
            .head => &self.head,
            .shoulders => &self.shoulders,
            .arms => &self.arms,
            .legs => &self.legs,
            .back_unit => &self.back_unit,
            .weapon => &self.weapon,
        };
        slot.* = @intCast(cycleIndex(@intCast(slot.*), moduleCount(part), direction));
    }

    pub fn cyclePalette(self: *Design, direction: i32) void {
        self.palette = @enumFromInt(cycleIndex(@intFromEnum(self.palette), enum_compat.fields(Palette).len, direction));
    }
};

pub const ModuleInfo = struct { name: []const u8, scale: f32, description: []const u8 };
pub const palette_names = [_][]const u8{ "OBSIDIAN", "AMETHYST", "ROSE", "WAR RED", "SILVER" };
pub const colors = [_]struct { armor: [4]f32, accent: [4]f32, glow: [4]f32 }{
    .{ .armor = .{ 0.10, 0.085, 0.14, 1 }, .accent = .{ 0.34, 0.13, 0.52, 1 }, .glow = .{ 1.0, 0.08, 0.54, 1 } },
    .{ .armor = .{ 0.17, 0.12, 0.24, 1 }, .accent = .{ 0.50, 0.24, 0.78, 1 }, .glow = .{ 0.90, 0.10, 0.70, 1 } },
    .{ .armor = .{ 0.24, 0.10, 0.18, 1 }, .accent = .{ 0.76, 0.22, 0.49, 1 }, .glow = .{ 1.0, 0.31, 0.71, 1 } },
    .{ .armor = .{ 0.22, 0.045, 0.075, 1 }, .accent = .{ 0.62, 0.12, 0.18, 1 }, .glow = .{ 1.0, 0.16, 0.12, 1 } },
    .{ .armor = .{ 0.34, 0.36, 0.41, 1 }, .accent = .{ 0.64, 0.68, 0.74, 1 }, .glow = .{ 1.0, 0.12, 0.56, 1 } },
};

const frames = [_]ModuleInfo{
    .{ .name = "BULWARK FRAME", .scale = 1, .description = "wide chest, reinforced legs" },
    .{ .name = "SIEGE FRAME", .scale = 1.12, .description = "heavy industrial torso" },
    .{ .name = "HUNTER FRAME", .scale = 0.86, .description = "lean forward armor" },
};
const heads = [_]ModuleInfo{
    .{ .name = "CROWN SENSOR", .scale = 1, .description = "angular command visor" },
    .{ .name = "HORNED SENSOR", .scale = 1.12, .description = "split antenna crest" },
    .{ .name = "SEALED HELM", .scale = 0.92, .description = "faceted armored mask" },
};
const shoulders = [_]ModuleInfo{
    .{ .name = "HEAVY PAULDRONS", .scale = 1, .description = "broad squared plates" },
    .{ .name = "TWIN PODS", .scale = 1.18, .description = "missile pod shoulders" },
    .{ .name = "SPIKE MANTLE", .scale = 1.1, .description = "outward blade armor" },
};
const arms = [_]ModuleInfo{
    .{ .name = "PISTON ARMS", .scale = 1, .description = "hydraulic gauntlets" },
    .{ .name = "BREACHER ARMS", .scale = 1.15, .description = "oversized impact fists" },
    .{ .name = "TALON ARMS", .scale = 0.85, .description = "segmented claw hands" },
};
const legs = [_]ModuleInfo{
    .{ .name = "WALKER LEGS", .scale = 1, .description = "stability-first heavy stride" },
    .{ .name = "REACTOR LEGS", .scale = 0.92, .description = "thrust-assisted stance" },
    .{ .name = "TREAD GUARDS", .scale = 1.12, .description = "oversized armored shins" },
};
const backs = [_]ModuleInfo{
    .{ .name = "REACTOR PACK", .scale = 1, .description = "twin vent power unit" },
    .{ .name = "WING ARRAY", .scale = 1.2, .description = "folded transforming wings" },
    .{ .name = "SIEGE RIG", .scale = 1.1, .description = "industrial weapon hardpoint" },
};
const weapons = [_]ModuleInfo{
    .{ .name = "ARC CANNON", .scale = 1, .description = "charged ranged weapon" },
    .{ .name = "BREACHER", .scale = 1.1, .description = "close-range heavy tool" },
    .{ .name = "ENERGY LANCE", .scale = 0.9, .description = "long reach melee weapon" },
};

pub fn module(part: Part, index: u8) ModuleInfo {
    const i: usize = index;
    return switch (part) {
        .frame => frames[@min(i, frames.len - 1)],
        .head => heads[@min(i, heads.len - 1)],
        .shoulders => shoulders[@min(i, shoulders.len - 1)],
        .arms => arms[@min(i, arms.len - 1)],
        .legs => legs[@min(i, legs.len - 1)],
        .back_unit => backs[@min(i, backs.len - 1)],
        .weapon => weapons[@min(i, weapons.len - 1)],
    };
}

fn moduleCount(part: Part) usize {
    return switch (part) {
        .frame => frames.len,
        .head => heads.len,
        .shoulders => shoulders.len,
        .arms => arms.len,
        .legs => legs.len,
        .back_unit => backs.len,
        .weapon => weapons.len,
    };
}

/// Stable frame variations for encounters. An editor choice can be supplied as an override.
pub fn encounter(seed: u64, slot: usize, override_design: ?Design) Design {
    if (override_design) |design| return design;
    const hash = Seed.mix(seed ^ (@as(u64, @intCast(slot)) *% 0x9e3779b97f4a7c15));
    return .{
        .frame = @intCast(hash % frames.len),
        .head = @intCast((hash >> 8) % heads.len),
        .shoulders = @intCast((hash >> 16) % shoulders.len),
        .arms = @intCast((hash >> 24) % arms.len),
        .legs = @intCast((hash >> 32) % legs.len),
        .back_unit = @intCast((hash >> 40) % backs.len),
        .weapon = @intCast((hash >> 48) % weapons.len),
        .palette = @enumFromInt((hash >> 56) % palette_names.len),
    };
}

fn cycleIndex(value: usize, count: usize, direction: i32) usize {
    return if (direction < 0) (value + count - 1) % count else (value + 1) % count;
}

