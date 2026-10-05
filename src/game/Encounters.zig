//! Where the Wildkin wait to be met. Every hero who is not a starter or an arena champion has a
//! seeded spot: city heroes on the district's plazas, wild heroes out on the meadow ring, and
//! cave heroes in a cache chamber of their own cave system. Walk up and click to meet one; they
//! join the roster. Arena heroes join when the party clears their arena wave (`arenaWave`).
const std = @import("std");
const Heroes = @import("Heroes.zig");
const Seed = @import("../procedural/Seed.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Caves = @import("../procedural/Caves.zig");
const V = [3]f32;

pub const Spot = struct { hero: u8, position: V, yaw: f32 };
pub const Plaza = struct { position: V, arbor: bool };

pub const Sites = struct {
    seed: u64,
    spawn: V,
    plazas: []const Plaza,
    caves: *const Caves.Layout,
};

/// Every hero's spot (null for starters and arena champions, or a cave hero without a cave).
pub fn place(sites: Sites) [Heroes.count]?Spot {
    var out: [Heroes.count]?Spot = @splat(null);
    var city: usize = 0;
    var wild: usize = 0;
    var cave: usize = 0;
    for (Heroes.roster, 0..) |h, i| {
        const salt = Seed.mix(sites.seed ^ 0x57494c444b494e ^ @as(u64, i));
        const turn = Seed.unit(salt) * 2 * std.math.pi;
        switch (h.home) {
            .starter, .arena => {},
            .city => {
                if (sites.plazas.len == 0) continue;
                const plaza = sites.plazas[(city * 2 + 1) % sites.plazas.len];
                city += 1;
                const r: f32 = if (plaza.arbor) 17 else 8;
                out[i] = .{ .hero = @intCast(i), .position = .{ plaza.position[0] + @sin(turn) * r, plaza.position[1], plaza.position[2] + @cos(turn) * r }, .yaw = turn + std.math.pi };
            },
            .wilds => {
                const angle = (@as(f32, @floatFromInt(wild)) + Seed.unit(Seed.mix(salt +% 1)) * 0.5) * 2 * std.math.pi / 6 + 0.3;
                wild += 1;
                const r = 260 + Seed.unit(Seed.mix(salt +% 2)) * 260;
                const x = sites.spawn[0] + @sin(angle) * r;
                const z = sites.spawn[2] + @cos(angle) * r;
                out[i] = .{ .hero = @intCast(i), .position = .{ x, Terrain.surface(sites.seed, x, z).height, z }, .yaw = angle + std.math.pi };
            },
            .cave => {
                // One per cave system, in a cache chamber; with more cave heroes than systems,
                // the next system round takes the next chamber.
                if (sites.caves.count == 0) continue;
                const sys = &sites.caves.systems[cave % sites.caves.count];
                const round = cave / sites.caves.count;
                cave += 1;
                var room: u8 = @intCast(1 + round % (sys.room_count - 1));
                var caches: usize = 0;
                for (sys.rooms[1..sys.room_count], 1..) |r, k| if (r.role == .cache) {
                    if (caches == round) {
                        room = @intCast(k);
                        break;
                    }
                    caches += 1;
                };
                const p = Caves.floorSpot(sys, room, 0, 2, 0.3);
                out[i] = .{ .hero = @intCast(i), .position = p, .yaw = turn };
            },
        }
    }
    return out;
}

/// The arena wave whose clearing brings arena hero `hero` to the roster (every third wave, in
/// roster order), or null for heroes met elsewhere.
pub fn arenaWave(hero: u8) ?u16 {
    var k: u16 = 0;
    for (Heroes.roster, 0..) |h, i| {
        if (h.home != .arena) continue;
        k += 1;
        if (i == hero) return k * 3;
    }
    return null;
}

test "every hero not on the roster at the start can be met somewhere" {
    const caves = Caves.layout(0x4845415659);
    const plazas = [_]Plaza{ .{ .position = .{ 0, 12, 40 }, .arbor = true }, .{ .position = .{ 60, 14, 0 }, .arbor = false }, .{ .position = .{ -50, 10, -10 }, .arbor = false } };
    const spots = place(.{ .seed = 0x4845415659, .spawn = .{ 0, 0, -58 }, .plazas = &plazas, .caves = &caves });
    for (Heroes.roster, 0..) |h, i| switch (h.home) {
        .starter => try std.testing.expect(spots[i] == null),
        .arena => try std.testing.expect(spots[i] == null and arenaWave(@intCast(i)) != null),
        .city, .wilds => try std.testing.expect(spots[i] != null),
        // Cave heroes need a cave each; the default seed has enough.
        .cave => {
            const s = spots[i] orelse return error.NoCave;
            try std.testing.expect(Caves.hollow(&caves, .{ s.position[0], s.position[1] + 1, s.position[2] }));
        },
    };
    // Arena champions arrive at waves 3, 6, 9 …
    var waves: [Heroes.count]u16 = undefined;
    var n: usize = 0;
    for (0..Heroes.count) |i| if (arenaWave(@intCast(i))) |w| {
        waves[n] = w;
        n += 1;
    };
    try std.testing.expect(n >= 3 and waves[0] == 3 and waves[1] == 6);
}
