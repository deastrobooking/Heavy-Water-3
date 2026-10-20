//! Content recipes joining imported terrain to biome, faction, encounter and base plans.
//! These catalogs are authoring data; only named destinations with runtime bindings are playable.
//! K2, Antarctica, Detroit, NYC and Chicago are active; the rest are planning markers and recipes.
const Seed = @import("Seed.zig");
const Interiors = @import("Interiors.zig");

pub const Biome = enum {
    alpine_glacier,
    alpine_icefall,
    high_basalt,
    jungle_mesa,
    karst_sinkhole,
    desert_ring,
    volcanic_salt_rift,
    abyssal_trench,
    lakefront_canopy,
    harbor_canopy,
    coastal_mountain,
    humid_river_canopy,
    civic_garden,
    subtropical_wetland,
    desert_basin,
    forested_estuary,
    alpine_front_range,
    piedmont_forest,
    limestone_river,
    continental_city,
};

pub const Faction = enum { hive, scalari, contested };
pub const EnemyRole = enum { hive_robot, insectoid_drone, burrower, spore_spitter, mechanoid_guard, mechanoid_titan, organic_drake, brood_queen, abyssal_swimmer, patrol_wasp };
pub const Hazard = enum { avalanche, thin_ice, altitude, falling_rock, spore_bloom, resin_surge, vertical_waterfall, sinkhole_drop, shifting_sand, basalt_vent, lava_flow, toxic_brine, pressure, current, flood, storm, wildfire };
pub const Traversal = enum { ridge_climb, snow_sprint, ice_anchor, lift_shaft, cave_crawl, waterfall_swing, sinkhole_descent, magma_bridge, pressure_swim, skyway_parkour, suspension_bridge, rooftop_lift };
pub const CityStyle = enum { canopy_garden, lakefront_terrace, harbor_vertical, coastal_cliff, desert_oasis, alpine_greenhouse, civic_stone_garden, wetland_skyway, river_bluff, forest_tower, rainforest_tower };

pub const TerrainSite = struct {
    name: []const u8,
    asset: []const u8,
    latitude: f32,
    longitude: f32,
    footprint_m: f32,
    relief_m: f32,
    biome: Biome,
    faction: Faction,
    enemies: []const EnemyRole,
    hazards: []const Hazard,
    traversal: []const Traversal,
    base: Interiors.Archetype,
    boss: []const u8,
    dungeon_layers: u8,
};

const mountain_enemies = [_]EnemyRole{ .mechanoid_guard, .mechanoid_titan, .insectoid_drone, .organic_drake };
const hive_enemies = [_]EnemyRole{ .hive_robot, .insectoid_drone, .burrower, .spore_spitter, .organic_drake };
const scalari_enemies = [_]EnemyRole{ .mechanoid_guard, .mechanoid_titan, .patrol_wasp, .hive_robot };

/// Ten source rasters describe the Himalayan cluster; connect them as one expedition
/// network with distinct summit routes and underground factions, not ten isolated worlds.
pub const mountains = [_]TerrainSite{
    .{ .name = "Mount Everest", .asset = "assets/Mountains/01_mount_everest_16bit.png", .latitude = 27.9881, .longitude = 86.9250, .footprint_m = 30000, .relief_m = 4875.39, .biome = .alpine_glacier, .faction = .contested, .enemies = &mountain_enemies, .hazards = &.{ .avalanche, .thin_ice, .altitude }, .traversal = &.{ .ridge_climb, .ice_anchor, .lift_shaft }, .base = .mountain_vault, .boss = "The Summit Engine", .dungeon_layers = 7 },
    .{ .name = "K2", .asset = "assets/Mountains/02_k2_16bit.png", .latitude = 35.8800, .longitude = 76.5151, .footprint_m = 30000, .relief_m = 4763.06, .biome = .alpine_glacier, .faction = .scalari, .enemies = &scalari_enemies, .hazards = &.{ .avalanche, .falling_rock, .altitude }, .traversal = &.{ .ridge_climb, .ice_anchor, .cave_crawl }, .base = .scalari_mechworks, .boss = "Black-Summit Titan", .dungeon_layers = 6 },
    .{ .name = "Kangchenjunga", .asset = "assets/Mountains/03_kangchenjunga_16bit.png", .latitude = 27.7025, .longitude = 88.1475, .footprint_m = 30000, .relief_m = 5497.51, .biome = .alpine_icefall, .faction = .hive, .enemies = &hive_enemies, .hazards = &.{ .avalanche, .thin_ice, .vertical_waterfall }, .traversal = &.{ .ridge_climb, .ice_anchor, .waterfall_swing }, .base = .hive_broodworks, .boss = "Fivefold Brood Matriarch", .dungeon_layers = 8 },
    .{ .name = "Lhotse", .asset = "assets/Mountains/04_lhotse_16bit.png", .latitude = 27.9617, .longitude = 86.9336, .footprint_m = 30000, .relief_m = 4980.96, .biome = .alpine_glacier, .faction = .contested, .enemies = &mountain_enemies, .hazards = &.{ .avalanche, .falling_rock, .altitude }, .traversal = &.{ .ridge_climb, .lift_shaft, .cave_crawl }, .base = .mountain_vault, .boss = "Lhotse Bore-Dragon", .dungeon_layers = 7 },
    .{ .name = "Makalu", .asset = "assets/Mountains/05_makalu_16bit.png", .latitude = 27.8897, .longitude = 87.0889, .footprint_m = 30000, .relief_m = 5100.28, .biome = .high_basalt, .faction = .scalari, .enemies = &scalari_enemies, .hazards = &.{ .falling_rock, .altitude, .basalt_vent }, .traversal = &.{ .ridge_climb, .lift_shaft, .magma_bridge }, .base = .scalari_mechworks, .boss = "Makalu Siege Colossus", .dungeon_layers = 6 },
    .{ .name = "Cho Oyu", .asset = "assets/Mountains/06_cho_oyu_16bit.png", .latitude = 28.0942, .longitude = 86.6608, .footprint_m = 30000, .relief_m = 3598.46, .biome = .alpine_glacier, .faction = .hive, .enemies = &hive_enemies, .hazards = &.{ .thin_ice, .altitude, .spore_bloom }, .traversal = &.{ .snow_sprint, .cave_crawl, .lift_shaft }, .base = .hive_broodworks, .boss = "Cho Oyu Brood Warden", .dungeon_layers = 5 },
    .{ .name = "Dhaulagiri I", .asset = "assets/Mountains/07_dhaulagiri_i_16bit.png", .latitude = 28.6983, .longitude = 83.4875, .footprint_m = 30000, .relief_m = 6532.93, .biome = .alpine_icefall, .faction = .contested, .enemies = &mountain_enemies, .hazards = &.{ .avalanche, .vertical_waterfall, .falling_rock }, .traversal = &.{ .ridge_climb, .waterfall_swing, .cave_crawl }, .base = .drake_roost, .boss = "Dhaulagiri Stormwyrm", .dungeon_layers = 9 },
    .{ .name = "Manaslu", .asset = "assets/Mountains/08_manaslu_16bit.png", .latitude = 28.5497, .longitude = 84.5597, .footprint_m = 30000, .relief_m = 6854.55, .biome = .alpine_glacier, .faction = .hive, .enemies = &hive_enemies, .hazards = &.{ .avalanche, .spore_bloom, .thin_ice }, .traversal = &.{ .ridge_climb, .ice_anchor, .lift_shaft }, .base = .hive_broodworks, .boss = "Manaslu Hive-Heart", .dungeon_layers = 8 },
    .{ .name = "Nanga Parbat", .asset = "assets/Mountains/09_nanga_parbat_16bit.png", .latitude = 35.2375, .longitude = 74.5892, .footprint_m = 30000, .relief_m = 6098.0, .biome = .alpine_icefall, .faction = .scalari, .enemies = &mountain_enemies, .hazards = &.{ .avalanche, .falling_rock, .altitude }, .traversal = &.{ .ridge_climb, .ice_anchor, .lift_shaft }, .base = .scalari_mechworks, .boss = "Rupal Mech-Dragon", .dungeon_layers = 8 },
    .{ .name = "Annapurna I", .asset = "assets/Mountains/10_annapurna_i_16bit.png", .latitude = 28.5961, .longitude = 83.8203, .footprint_m = 30000, .relief_m = 7961.86, .biome = .alpine_icefall, .faction = .contested, .enemies = &mountain_enemies, .hazards = &.{ .avalanche, .vertical_waterfall, .spore_bloom }, .traversal = &.{ .ridge_climb, .waterfall_swing, .cave_crawl }, .base = .drake_roost, .boss = "Annapurna Crown Drake", .dungeon_layers = 10 },
};

const stronghold_enemies = [_]EnemyRole{ .hive_robot, .insectoid_drone, .mechanoid_guard, .mechanoid_titan, .organic_drake };

/// Six alien strongholds pair each source landform with a clear biome and base identity.
pub const strongholds = [_]TerrainSite{
    .{ .name = "Richat Annular Citadel", .asset = "assets/Terrainpack2/01_eye_of_the_sahara_16bit.png", .latitude = 21.124, .longitude = -11.402, .footprint_m = 52000, .relief_m = 283.71, .biome = .desert_ring, .faction = .scalari, .enemies = &stronghold_enemies, .hazards = &.{ .shifting_sand, .storm, .basalt_vent }, .traversal = &.{ .ridge_climb, .sinkhole_descent, .lift_shaft }, .base = .scalari_mechworks, .boss = "The Annular Colossus", .dungeon_layers = 6 },
    .{ .name = "Auyan Tepui Brood Crown", .asset = "assets/Terrainpack2/02_auyan_tepui_angel_falls_16bit.png", .latitude = 5.918, .longitude = -62.535, .footprint_m = 38000, .relief_m = 1978.36, .biome = .jungle_mesa, .faction = .hive, .enemies = &hive_enemies, .hazards = &.{ .spore_bloom, .resin_surge, .vertical_waterfall }, .traversal = &.{ .waterfall_swing, .cave_crawl, .lift_shaft }, .base = .drake_roost, .boss = "Auyan Canopy Drake-Queen", .dungeon_layers = 9 },
    .{ .name = "Putorana Basalt Hive", .asset = "assets/Terrainpack2/03_putorana_plateau_16bit.png", .latitude = 69.38, .longitude = 90.65, .footprint_m = 48000, .relief_m = 1418.56, .biome = .high_basalt, .faction = .contested, .enemies = &stronghold_enemies, .hazards = &.{ .thin_ice, .basalt_vent, .avalanche }, .traversal = &.{ .ridge_climb, .ice_anchor, .cave_crawl }, .base = .mountain_vault, .boss = "The Permafrost Engine", .dungeon_layers = 8 },
    .{ .name = "Xiaozhai Tiankeng Broodwell", .asset = "assets/Terrainpack2/04_chongqing_tiankeng_karst_16bit.png", .latitude = 30.7505, .longitude = 109.47, .footprint_m = 30000, .relief_m = 1893.33, .biome = .karst_sinkhole, .faction = .hive, .enemies = &hive_enemies, .hazards = &.{ .sinkhole_drop, .spore_bloom, .flood }, .traversal = &.{ .sinkhole_descent, .cave_crawl, .lift_shaft }, .base = .hive_broodworks, .boss = "The Tiankeng Broodmother", .dungeon_layers = 11 },
    .{ .name = "Danakil Crucible", .asset = "assets/Terrainpack2/05_danakil_erta_ale_16bit.png", .latitude = 13.6, .longitude = 40.66, .footprint_m = 45000, .relief_m = 1116.82, .biome = .volcanic_salt_rift, .faction = .scalari, .enemies = &scalari_enemies, .hazards = &.{ .lava_flow, .toxic_brine, .basalt_vent }, .traversal = &.{ .magma_bridge, .lift_shaft, .cave_crawl }, .base = .scalari_mechworks, .boss = "Erta Ale Furnace Drake", .dungeon_layers = 7 },
    .{ .name = "Mariana Trench Hive Engine", .asset = "assets/Terrainpack2/06_mariana_trench_abyss_16bit.png", .latitude = 11.35, .longitude = 142.2, .footprint_m = 160000, .relief_m = 11998.0, .biome = .abyssal_trench, .faction = .hive, .enemies = &.{ .hive_robot, .insectoid_drone, .abyssal_swimmer, .organic_drake }, .hazards = &.{ .pressure, .current, .resin_surge }, .traversal = &.{ .pressure_swim, .cave_crawl, .lift_shaft }, .base = .hive_broodworks, .boss = "The Challenger Deep Leviathan", .dungeon_layers = 12 },
};

pub const CitySite = struct {
    name: []const u8,
    /// Null while a manifest entry has no corresponding raster in the checked-out assets.
    asset: ?[]const u8,
    latitude: f32,
    longitude: f32,
    biome: Biome,
    style: CityStyle,
    base: Interiors.Archetype = .sky_city,
    faction: Faction = .contested,
};

/// Twenty additional US metro rasters plus the four already in the playable catalog.
/// Each city uses the same connected skyway / lift / shelter base grammar with a local style.
pub const us_cities = [_]CitySite{
    .{ .name = "Detroit", .asset = "assets/CitiesUSA/detroit_metro_heightmap_16bit.png", .latitude = 42.3314, .longitude = -83.0458, .biome = .lakefront_canopy, .style = .canopy_garden },
    .{ .name = "New York City", .asset = "assets/CitiesUSA/nyc_metro_heightmap_16bit.png", .latitude = 40.7128, .longitude = -74.0060, .biome = .harbor_canopy, .style = .harbor_vertical },
    .{ .name = "Chicago", .asset = "assets/CitiesUSA/chicago_metro_heightmap_16bit.png", .latitude = 41.8781, .longitude = -87.6298, .biome = .lakefront_canopy, .style = .lakefront_terrace },
    .{ .name = "Los Angeles", .asset = "assets/CitiesUSA/la_metro_heightmap_16bit.png", .latitude = 34.0522, .longitude = -118.2437, .biome = .coastal_mountain, .style = .coastal_cliff },
    .{ .name = "Dallas-Fort Worth", .asset = "assets/CitiesUSA/01_dallas_fort_worth_16bit.png", .latitude = 32.7767, .longitude = -96.92, .biome = .humid_river_canopy, .style = .canopy_garden },
    .{ .name = "Houston", .asset = "assets/CitiesUSA/02_houston_16bit.png", .latitude = 29.7604, .longitude = -95.3698, .biome = .subtropical_wetland, .style = .wetland_skyway },
    .{ .name = "Washington, D.C.", .asset = "assets/CitiesUSA/03_washington_dc_16bit.png", .latitude = 38.9072, .longitude = -77.0369, .biome = .civic_garden, .style = .civic_stone_garden },
    .{ .name = "Philadelphia", .asset = "assets/CitiesUSA/04_philadelphia_16bit.png", .latitude = 39.9526, .longitude = -75.1652, .biome = .forested_estuary, .style = .river_bluff },
    .{ .name = "Atlanta", .asset = "assets/CitiesUSA/05_atlanta_16bit.png", .latitude = 33.7490, .longitude = -84.3880, .biome = .humid_river_canopy, .style = .rainforest_tower },
    .{ .name = "Miami", .asset = "assets/CitiesUSA/06_miami_16bit.png", .latitude = 25.7617, .longitude = -80.1918, .biome = .subtropical_wetland, .style = .wetland_skyway },
    .{ .name = "Phoenix", .asset = null, .latitude = 33.4484, .longitude = -112.0740, .biome = .desert_basin, .style = .desert_oasis },
    .{ .name = "Boston", .asset = "assets/CitiesUSA/08_boston_16bit.png", .latitude = 42.3601, .longitude = -71.0589, .biome = .harbor_canopy, .style = .harbor_vertical },
    .{ .name = "Riverside-San Bernardino", .asset = "assets/CitiesUSA/09_riverside_san_bernardino_16bit.png", .latitude = 34.0522, .longitude = -117.32, .biome = .desert_basin, .style = .desert_oasis },
    .{ .name = "San Francisco Bay Area", .asset = "assets/CitiesUSA/10_san_francisco_bay_area_16bit.png", .latitude = 37.7749, .longitude = -122.35, .biome = .coastal_mountain, .style = .coastal_cliff },
    .{ .name = "Seattle-Tacoma", .asset = null, .latitude = 47.6062, .longitude = -122.3321, .biome = .forested_estuary, .style = .forest_tower },
    .{ .name = "Minneapolis-St. Paul", .asset = "assets/CitiesUSA/12_minneapolis_st_paul_16bit.png", .latitude = 44.96, .longitude = -93.2, .biome = .forested_estuary, .style = .river_bluff },
    .{ .name = "San Diego", .asset = "assets/CitiesUSA/13_san_diego_16bit.png", .latitude = 32.7157, .longitude = -117.1611, .biome = .coastal_mountain, .style = .coastal_cliff },
    .{ .name = "Tampa-St. Petersburg", .asset = "assets/CitiesUSA/14_tampa_st_petersburg_16bit.png", .latitude = 27.88, .longitude = -82.55, .biome = .subtropical_wetland, .style = .wetland_skyway },
    .{ .name = "Denver & Front Range", .asset = "assets/CitiesUSA/15_denver_16bit.png", .latitude = 39.7392, .longitude = -105.08, .biome = .alpine_front_range, .style = .alpine_greenhouse },
    .{ .name = "Baltimore", .asset = "assets/CitiesUSA/16_baltimore_16bit.png", .latitude = 39.2904, .longitude = -76.6122, .biome = .forested_estuary, .style = .harbor_vertical },
    .{ .name = "St. Louis", .asset = null, .latitude = 38.6270, .longitude = -90.1994, .biome = .forested_estuary, .style = .river_bluff },
    .{ .name = "Orlando", .asset = "assets/CitiesUSA/18_orlando_16bit.png", .latitude = 28.5383, .longitude = -81.3792, .biome = .subtropical_wetland, .style = .wetland_skyway },
    .{ .name = "Charlotte", .asset = null, .latitude = 35.2271, .longitude = -80.8431, .biome = .piedmont_forest, .style = .forest_tower },
    .{ .name = "San Antonio", .asset = "assets/CitiesUSA/20_san_antonio_16bit.png", .latitude = 29.4241, .longitude = -98.4936, .biome = .limestone_river, .style = .desert_oasis },
};

pub fn siteBase(seed: u64, index: usize) ?Interiors.Layout {
    if (index >= mountains.len + strongholds.len) return null;
    const site = if (index < mountains.len) mountains[index] else strongholds[index - mountains.len];
    return Interiors.generate(Seed.mix(seed ^ @as(u64, @intCast(index)) *% 0x9e3779b97f4a7c15), site.base);
}

pub fn cityBase(seed: u64, index: usize) ?Interiors.Layout {
    if (index >= us_cities.len) return null;
    return Interiors.generate(Seed.mix(seed ^ @as(u64, @intCast(index + 0x100)) *% 0x9e3779b97f4a7c15), us_cities[index].base);
}

comptime {
    @setEvalBranchQuota(20_000);
    if (mountains.len != 10 or strongholds.len != 6 or us_cities.len != 24) @compileError("terrain site catalog is incomplete");
    for (mountains, 0..) |site, i| {
        const base = Interiors.generate(@intCast(i), site.base);
        if (!base.connected()) @compileError("mountain base recipe must connect every room to its objective");
    }
    for (strongholds, 0..) |site, i| {
        const base = Interiors.generate(@intCast(i + mountains.len), site.base);
        if (!base.connected()) @compileError("stronghold base recipe must connect every room to its objective");
    }
    for (us_cities, 0..) |city, i| {
        const base = Interiors.generate(@intCast(i + 0x100), city.base);
        if (!base.connected()) @compileError("city base recipe must connect every room to its objective");
    }
}
