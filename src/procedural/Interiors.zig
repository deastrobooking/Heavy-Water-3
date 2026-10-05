//! Seeded indoor plans composed from reusable room modules. Building floors, enemy facilities and
//! dungeons share the same graph/door format while receiving different room roles and dimensions.
//! This is the layout and mapping layer; rendering, streamed interior instances, doors and combat
//! population attach to these stable room/link ids in the next content integration pass.
const std = @import("std");
const Seed = @import("Seed.zig");

pub const Archetype = enum { residence, commerce, industry, enemy_base, dungeon };
pub const Role = enum { entry, corridor, common, living, sleeping, utility, atrium, shop, storage, office, security, command, barracks, armory, reactor, hangar, assembly, control, trial, cache, heart };
pub const Side = enum { north, east, south, west };
pub const max_rooms = 8;
pub const max_doors = max_rooms - 1;
pub const module_pitch: f32 = 12;
pub const wall_height: f32 = 4;

pub const Room = struct {
    role: Role,
    grid: [2]i8,
    half_extent: [2]f32,
    floor_y: f32 = 0,
    ceiling: f32 = wall_height,
};
pub const Door = struct { a: u8, b: u8, side_a: Side, side_b: Side, width: f32 = 2.4, height: f32 = 2.8 };
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

const Template = struct { roles: []const Role, grid: []const [2]i8, parents: []const u8 };
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

pub fn generate(seed: u64, archetype: Archetype) Layout {
    const template: Template = switch (archetype) {
        .residence => .{ .roles = &residence_roles, .grid = &residence_grid, .parents = &residence_parents },
        .commerce => .{ .roles = &commerce_roles, .grid = &commerce_grid, .parents = &commerce_parents },
        .industry => .{ .roles = &industry_roles, .grid = &industry_grid, .parents = &industry_parents },
        .enemy_base => .{ .roles = &base_roles, .grid = &base_grid, .parents = &base_parents },
        .dungeon => .{ .roles = &dungeon_roles, .grid = &dungeon_grid, .parents = &dungeon_parents },
    };
    const rotation: u2 = @truncate(Seed.mix(seed ^ (@as(u64, @intFromEnum(archetype)) *% 0x9e3779b97f4a7c15)));
    var result: Layout = .{ .seed = seed, .archetype = archetype, .rotation = rotation, .room_count = @intCast(template.roles.len), .objective = @intCast(template.roles.len - 1) };
    for (template.roles, template.grid, 0..) |role, cell, index| {
        result.rooms[index] = .{ .role = role, .grid = cell, .half_extent = extents(role), .ceiling = if (role == .reactor or role == .atrium or role == .hangar) 7 else wall_height };
    }
    for (1..template.roles.len) |index| {
        const parent: usize = template.parents[index];
        const from = result.rooms[parent].grid;
        const to = result.rooms[index].grid;
        const dx: i16 = @as(i16, to[0]) - from[0];
        const dz: i16 = @as(i16, to[1]) - from[1];
        const side: Side = if (dx > 0) .east else if (dx < 0) .west else if (dz > 0) .north else .south;
        result.doors[result.door_count] = .{ .a = @intCast(parent), .b = @intCast(index), .side_a = rotateSide(side, rotation), .side_b = rotateSide(opposite(side), rotation) };
        result.door_count += 1;
    }
    return result;
}

fn extents(role: Role) [2]f32 {
    return switch (role) {
        .common, .atrium, .assembly, .command, .heart => .{ 6, 6 },
        .reactor, .hangar => .{ 6, 6 },
        .corridor, .entry, .security => .{ 4.5, 4.5 },
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
