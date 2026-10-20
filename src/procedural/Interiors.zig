//! Seeded indoor plans composed from reusable room modules. City districts, mountain vaults,
//! Scalari mechworks, Hive broodworks, drake roosts and dungeons share the same connected graph.
//! TerrainSites selects a facility grammar per location; rendering and live combat population
//! still need to consume these stable room/link ids.
const std = @import("std");
const Seed = @import("Seed.zig");

pub const Archetype = enum { residence, commerce, industry, enemy_base, dungeon, scalari_mechworks, hive_broodworks, mountain_vault, drake_roost, sky_city };
pub const Role = enum { entry, corridor, common, living, sleeping, utility, atrium, shop, storage, office, security, command, barracks, armory, reactor, hangar, assembly, control, trial, cache, heart, lift, relay, mech_bay, resin_vat, brood, roost, sky_lobby, garden, shelter, escape };
/// Reusable room content modules. The room graph stays procedural data; gameplay systems attach
/// the matching fixture and interaction behavior without branching on every building archetype.
pub const Module = enum { plain, entry, home, market, evidence, power, security, command, armory, hangar, trial, cache, heart, lift, relay, mech_bay, resin_vat, brood, roost, sky_lobby, garden, shelter, escape };
pub const Interaction = enum { exit, trade, evidence, power, alarm, loot, unlock, nest_heart, lift, disable_relay, service_mech, purge_resin, brood_heart, dragon_roost, open_skyway, restore_garden, rescue_civilians };
pub const Side = enum { north, east, south, west };
pub const Connector = enum { corridor, ramp, lift, vertical_shaft, resin_tube, flight_tunnel, sky_lift };
pub const max_rooms = 10;
pub const max_doors = max_rooms - 1;
pub const module_pitch: f32 = 12;
pub const wall_height: f32 = 4;

pub const Room = struct {
    role: Role,
    grid: [2]i8,
    half_extent: [2]f32,
    floor_y: f32 = 0,
    ceiling: f32 = wall_height,
    module: Module = .plain,
};
/// A local fixture anchor for the room's module. Coordinates are centered on the room, in meters.
pub const Fixture = struct { interaction: Interaction, position: [3]f32 };
pub const Door = struct { a: u8, b: u8, side_a: Side, side_b: Side, connector: Connector = .corridor, width: f32 = 2.4, height: f32 = 2.8 };
pub const Layout = struct {
    seed: u64,
    archetype: Archetype,
    rotation: u2,
    rooms: [max_rooms]Room = undefined,
    room_count: u8 = 0,
    doors: [max_doors]Door = undefined,
    door_count: u8 = 0,
    entry: u8 = 0,
    objective: u8 = 0,

    pub fn roomPosition(self: Layout, index: usize, origin: [3]f32) [3]f32 {
        const room = self.rooms[index];
        const p = rotateGrid(room.grid, self.rotation);
        return .{ origin[0] + @as(f32, @floatFromInt(p[0])) * module_pitch, origin[1] + room.floor_y, origin[2] + @as(f32, @floatFromInt(p[1])) * module_pitch };
    }

    pub fn connected(self: Layout) bool {
        if (self.room_count == 0 or self.entry >= self.room_count) return false;
        var seen: [max_rooms]bool = @splat(false);
        var queue: [max_rooms]u8 = undefined;
        var head: usize = 0;
        var tail: usize = 1;
        queue[0] = self.entry;
        seen[self.entry] = true;
        while (head < tail) : (head += 1) {
            const current = queue[head];
            for (self.doors[0..self.door_count]) |door| {
                const next = if (door.a == current) door.b else if (door.b == current) door.a else continue;
                if (next >= self.room_count or seen[next]) continue;
                seen[next] = true;
                queue[tail] = next;
                tail += 1;
            }
        }
        for (seen[0..self.room_count]) |visited| if (!visited) return false;
        return self.objective < self.room_count;
    }
};

const Template = struct { roles: []const Role, grid: []const [2]i8, levels: []const i8, parents: []const u8 };
const residence_roles = [_]Role{ .entry, .corridor, .common, .living, .sleeping, .utility };
const residence_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 0, 3 } };
const residence_parents = [_]u8{ 0, 0, 1, 2, 2, 2 };
const commerce_roles = [_]Role{ .entry, .corridor, .atrium, .shop, .shop, .storage, .office };
const commerce_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ -1, 3 }, .{ 1, 3 } };
const commerce_parents = [_]u8{ 0, 0, 1, 2, 2, 3, 4 };
const industry_roles = [_]Role{ .entry, .corridor, .assembly, .storage, .reactor, .control, .utility };
const industry_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 1, 3 }, .{ 0, 3 } };
const industry_parents = [_]u8{ 0, 0, 1, 2, 2, 4, 2 };
const base_roles = [_]Role{ .entry, .security, .command, .barracks, .armory, .reactor, .hangar, .storage };
const base_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 0, 3 }, .{ 1, 3 }, .{ -1, 3 } };
const base_parents = [_]u8{ 0, 0, 1, 2, 2, 2, 5, 3 };
const dungeon_roles = [_]Role{ .entry, .corridor, .common, .trial, .cache, .heart };
const dungeon_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 0, 3 } };
const dungeon_parents = [_]u8{ 0, 0, 1, 2, 2, 2 };
const mechworks_roles = [_]Role{ .entry, .security, .assembly, .mech_bay, .reactor, .armory, .command, .lift, .hangar };
const mechworks_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ -1, 3 }, .{ 0, 3 }, .{ 1, 3 }, .{ 1, 3 } };
const mechworks_levels = [_]i8{ 0, 0, -1, -2, -2, -3, -4, -2, -6 };
const mechworks_parents = [_]u8{ 0, 0, 1, 2, 2, 3, 2, 1, 7 };
const broodworks_roles = [_]Role{ .entry, .security, .barracks, .resin_vat, .brood, .roost, .heart, .escape, .lift };
const broodworks_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 1, 3 }, .{ 0, 3 }, .{ -1, 3 }, .{ 0, 1 } };
const broodworks_levels = [_]i8{ 0, 0, -1, -2, -3, -5, -8, -5, -2 };
const broodworks_parents = [_]u8{ 0, 0, 1, 2, 2, 4, 4, 1, 1 };
const vault_roles = [_]Role{ .entry, .corridor, .trial, .cache, .cache, .relay, .mech_bay, .heart, .lift };
const vault_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 0, 3 }, .{ -1, 3 }, .{ 0, 4 }, .{ 0, 1 } };
const vault_levels = [_]i8{ 0, -1, -2, -2, -2, -3, -5, -8, -3 };
const vault_parents = [_]u8{ 0, 0, 1, 2, 2, 1, 5, 5, 1 };
const roost_roles = [_]Role{ .entry, .corridor, .trial, .brood, .roost, .cache, .heart, .lift };
const roost_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ -1, 3 }, .{ 1, 3 }, .{ 0, 1 } };
const roost_levels = [_]i8{ 0, -1, -2, -3, -5, -4, -8, -3 };
const roost_parents = [_]u8{ 0, 0, 1, 2, 2, 3, 4, 1 };
const sky_roles = [_]Role{ .entry, .sky_lobby, .shop, .garden, .shelter, .lift, .command, .hangar };
const sky_grid = [_][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ -1, 2 }, .{ 1, 2 }, .{ 0, 1 }, .{ 0, 2 }, .{ 1, 2 } };
const sky_levels = [_]i8{ 0, 0, 0, 0, 0, 1, 1, 2 };
const sky_parents = [_]u8{ 0, 0, 1, 2, 2, 1, 5, 4 };

pub fn generate(seed: u64, archetype: Archetype) Layout {
    const template: Template = switch (archetype) {
        .residence => .{ .roles = &residence_roles, .grid = &residence_grid, .levels = &.{ 0, 0, 0, 0, 0, 0 }, .parents = &residence_parents },
        .commerce => .{ .roles = &commerce_roles, .grid = &commerce_grid, .levels = &.{ 0, 0, 0, 0, 0, 0, 0 }, .parents = &commerce_parents },
        .industry => .{ .roles = &industry_roles, .grid = &industry_grid, .levels = &.{ 0, 0, 0, 0, 0, 0, 0 }, .parents = &industry_parents },
        .enemy_base => .{ .roles = &base_roles, .grid = &base_grid, .levels = &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, .parents = &base_parents },
        .dungeon => .{ .roles = &dungeon_roles, .grid = &dungeon_grid, .levels = &.{ 0, 0, 0, 0, 0, 0 }, .parents = &dungeon_parents },
        .scalari_mechworks => .{ .roles = &mechworks_roles, .grid = &mechworks_grid, .levels = &mechworks_levels, .parents = &mechworks_parents },
        .hive_broodworks => .{ .roles = &broodworks_roles, .grid = &broodworks_grid, .levels = &broodworks_levels, .parents = &broodworks_parents },
        .mountain_vault => .{ .roles = &vault_roles, .grid = &vault_grid, .levels = &vault_levels, .parents = &vault_parents },
        .drake_roost => .{ .roles = &roost_roles, .grid = &roost_grid, .levels = &roost_levels, .parents = &roost_parents },
        .sky_city => .{ .roles = &sky_roles, .grid = &sky_grid, .levels = &sky_levels, .parents = &sky_parents },
    };
    const rotation: u2 = @truncate(Seed.mix(seed ^ (@as(u64, @intFromEnum(archetype)) *% 0x9e3779b97f4a7c15)));
    var result: Layout = .{ .seed = seed, .archetype = archetype, .rotation = rotation, .room_count = @intCast(template.roles.len), .objective = @intCast(template.roles.len - 1) };
    const floor_spacing: f32 = if (archetype == .sky_city) 45 else 24;
    for (template.roles, template.grid, template.levels, 0..) |role, cell, level, index| {
        result.rooms[index] = .{ .role = role, .grid = cell, .half_extent = extents(role), .floor_y = @as(f32, @floatFromInt(level)) * floor_spacing, .ceiling = if (role == .reactor or role == .atrium or role == .hangar or role == .brood or role == .roost) 7 else wall_height, .module = moduleFor(role) };
    }
    for (1..template.roles.len) |index| {
        const parent: usize = template.parents[index];
        const from = result.rooms[parent].grid;
        const to = result.rooms[index].grid;
        const dx: i16 = @as(i16, to[0]) - from[0];
        const dz: i16 = @as(i16, to[1]) - from[1];
        const side: Side = if (dx > 0) .east else if (dx < 0) .west else if (dz > 0) .north else .south;
        const connector: Connector = if (result.rooms[parent].floor_y == result.rooms[index].floor_y) .corridor else switch (archetype) {
            .scalari_mechworks => .lift,
            .hive_broodworks => .resin_tube,
            .mountain_vault => .vertical_shaft,
            .drake_roost => .flight_tunnel,
            .sky_city => .sky_lift,
            else => .ramp,
        };
        result.doors[result.door_count] = .{ .a = @intCast(parent), .b = @intCast(index), .side_a = rotateSide(side, rotation), .side_b = rotateSide(opposite(side), rotation), .connector = connector };
        result.door_count += 1;
    }
    return result;
}

/// The common interaction anchor for each room module. Renderers place the matching prop here,
/// and the interior runtime binds it to the same interaction kind.
pub fn fixture(room: Room) ?Fixture {
    const x = room.half_extent[0] * 0.58;
    const z = room.half_extent[1] * 0.58;
    return switch (room.module) {
        .plain => null,
        .entry => .{ .interaction = .exit, .position = .{ 0, 0, -z } },
        .home => .{ .interaction = .loot, .position = .{ x, 0, 0 } },
        .market => .{ .interaction = .trade, .position = .{ 0, 0, z } },
        .evidence => .{ .interaction = .evidence, .position = .{ 0, 0, z } },
        .power => .{ .interaction = .power, .position = .{ x, 0, 0 } },
        .security => .{ .interaction = .alarm, .position = .{ x, 0, 0 } },
        .command => .{ .interaction = .evidence, .position = .{ 0, 0, z } },
        .armory => .{ .interaction = .loot, .position = .{ -x, 0, 0 } },
        .hangar => .{ .interaction = .unlock, .position = .{ 0, 0, z } },
        .trial => .{ .interaction = .unlock, .position = .{ 0, 0, z } },
        .cache => .{ .interaction = .loot, .position = .{ x, 0, 0 } },
        .heart => .{ .interaction = .nest_heart, .position = .{ 0, 0, z } },
        .lift => .{ .interaction = .lift, .position = .{ 0, 0, z } },
        .relay => .{ .interaction = .disable_relay, .position = .{ 0, 0, z } },
        .mech_bay => .{ .interaction = .service_mech, .position = .{ -x, 0, 0 } },
        .resin_vat => .{ .interaction = .purge_resin, .position = .{ x, 0, 0 } },
        .brood => .{ .interaction = .brood_heart, .position = .{ 0, 0, z } },
        .roost => .{ .interaction = .dragon_roost, .position = .{ 0, 0, z } },
        .sky_lobby => .{ .interaction = .open_skyway, .position = .{ 0, 0, -z } },
        .garden => .{ .interaction = .restore_garden, .position = .{ x, 0, 0 } },
        .shelter => .{ .interaction = .rescue_civilians, .position = .{ 0, 0, z } },
        .escape => .{ .interaction = .exit, .position = .{ 0, 0, -z } },
    };
}

fn moduleFor(role: Role) Module {
    return switch (role) {
        .entry => .entry,
        .living, .sleeping => .home,
        .shop => .market,
        .office, .control => .evidence,
        .utility, .reactor => .power,
        .security => .security,
        .command => .command,
        .armory => .armory,
        .hangar => .hangar,
        .trial => .trial,
        .cache, .storage => .cache,
        .heart => .heart,
        .lift => .lift,
        .relay => .relay,
        .mech_bay => .mech_bay,
        .resin_vat => .resin_vat,
        .brood => .brood,
        .roost => .roost,
        .sky_lobby => .sky_lobby,
        .garden => .garden,
        .shelter => .shelter,
        .escape => .escape,
        .corridor, .common, .atrium, .barracks, .assembly => .plain,
    };
}

fn extents(role: Role) [2]f32 {
    return switch (role) {
        .common, .atrium, .assembly, .command, .heart, .brood, .roost, .garden, .shelter => .{ 6, 6 },
        .reactor, .hangar => .{ 6, 6 },
        .corridor, .entry, .security, .lift, .escape => .{ 4.5, 4.5 },
        else => .{ 5, 5 },
    };
}

fn rotateGrid(grid: [2]i8, rotation: u2) [2]i8 {
    return switch (rotation) {
        0 => grid,
        1 => .{ grid[1], -grid[0] },
        2 => .{ -grid[0], -grid[1] },
        else => .{ -grid[1], grid[0] },
    };
}

fn rotateSide(side: Side, rotation: u2) Side {
    const value = (@as(u8, @intFromEnum(side)) + @as(u8, rotation)) % 4;
    return @enumFromInt(value);
}

fn opposite(side: Side) Side {
    const value = (@as(u8, @intFromEnum(side)) + 2) % 4;
    return @enumFromInt(value);
}

test "all interior archetypes build deterministic connected maps with doors and distinct modules" {
    for ([_]Archetype{ .residence, .commerce, .industry, .enemy_base, .dungeon }) |kind| {
        const layout = generate(0x4845415659, kind);
        const repeat = generate(0x4845415659, kind);
        try std.testing.expect(layout.connected());
        try std.testing.expectEqual(layout.room_count - 1, layout.door_count);
        try std.testing.expectEqual(layout.rooms[0].role, .entry);
        try std.testing.expectEqual(layout.objective, layout.room_count - 1);
        try std.testing.expectEqual(layout.rotation, repeat.rotation);
        try std.testing.expectEqualDeep(layout.rooms[0..layout.room_count], repeat.rooms[0..repeat.room_count]);
        try std.testing.expect(layout.rooms[layout.objective].role != .entry);
        const origin = [_]f32{ 100, 5, -40 };
        const world = layout.roomPosition(layout.objective, origin);
        try std.testing.expect(world[1] >= origin[1]);
    }
    try std.testing.expect(generate(1, .enemy_base).rooms[2].role == .command);
    try std.testing.expect(generate(1, .dungeon).rooms[5].role == .heart);
    try std.testing.expect(generate(1, .residence).rooms[3].role == .living);
}
