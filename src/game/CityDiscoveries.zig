//! Stable pickup locations for Detroit's ten planned city discoveries.
const CityContent = @import("CityContent.zig");
const BileCase = @import("BileCase.zig");
const District = @import("../procedural/District.zig");
const Hydrology = @import("../procedural/Hydrology.zig");
const Terrain = @import("../procedural/Terrain.zig");
const WindsorCase = @import("WindsorCase.zig");
const R = @import("../physics/Rotation.zig");
const V = R.Vec3;

pub const count = CityContent.discovery_count;

comptime {
    if (CityContent.discovery_count != @import("Kit.zig").city_discovery_count)
        @compileError("Detroit discovery locations and per-kit save mask must have the same length");
}

/// Rebuilds the same ten anchors from the seeded skyline and city geometry.
pub fn positions(layout: *const District.Layout, seed: u64, out: *[CityContent.discovery_count]V) void {
    var bell_tower: ?District.Building = null;
    var tallest_gothic: f32 = -1;
    var sky_lobby: ?District.Building = null;
    var highest_lobby: f32 = -1;
    for (layout.buildings[0..layout.building_count]) |building| {
        if (building.architecture == .gothic and building.spire > tallest_gothic) {
            tallest_gothic = building.spire;
            bell_tower = building;
        }
        if (building.plaza != null and building.roof > highest_lobby) {
            highest_lobby = building.roof;
            sky_lobby = building;
        }
    }

    out[0] = if (bell_tower) |building| building.beacon() else layout.nodes[4].position;

    const undercroft = District.marketPosition(layout, 1);
    out[1] = .{ undercroft[0], undercroft[1] + 1.35, undercroft[2] };

    const node3 = layout.nodes[3].position;
    const market = District.marketPosition(layout, 3);
    const deck_direction = R.normalize(.{ market[0] - node3[0], 0, market[2] - node3[2] });
    out[2] = .{ node3[0] + deck_direction[0] * 25, market[1] + 1.3, node3[2] + deck_direction[2] * 25 };

    const rootmap = layout.nodes[5].position;
    out[3] = .{ rootmap[0] + 9, rootmap[1] + 1.25, rootmap[2] - 6 };

    // Belle Isle park path, clear of the archive facade and its three case traces.
    const isle_x: f32 = -86;
    const isle_z = Hydrology.centerZ(seed, 0, 0) + 34;
    out[4] = .{ isle_x, Terrain.surface(seed, isle_x, isle_z).height + 1.25, isle_z };

    out[5] = WindsorCase.gatePosition(seed, 1) orelse layout.nodes[3].position;

    const promenade_x: f32 = -175;
    const promenade_z = Hydrology.centerZ(seed, 0, promenade_x) - Hydrology.surfaceHalfWidth(0, 0) - 30;
    out[6] = .{ promenade_x, Terrain.surface(seed, promenade_x, promenade_z).height + 1.25, promenade_z };

    const station = layout.nodes[1].position;
    out[7] = .{ station[0], station[1] + 1.25, station[2] };

    const gallery = District.trunkSpur(layout, 4).point(0.56);
    out[8] = .{ gallery[0], gallery[1] + 1.25, gallery[2] };

    out[9] = if (sky_lobby) |building|
        .{ building.base[0], building.roof + 2.2, building.base[2] }
    else
        .{ layout.nodes[3].position[0], layout.nodes[3].position[1] + 2.2, layout.nodes[3].position[2] };
}

