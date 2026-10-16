# Weather and seasons

**Status:** proposed, 2026-10-15. Planning only; nothing here is built. The [roadmap](../roadmap.md) stays the single plan. This is the detailed design behind the nature plan's Phase 8 ("snowfall and rain with the day cycle", [nature upgrade](nature-upgrade.md)) and the "Grow" pillar of [world](../world.md).

**Owner decisions (2026-10-15):**
- One **global calendar**, with regional effects scaled by biome; one in-game year is about **two hours** of play (432,000 ticks at 60 Hz), so each season is about **thirty minutes** (108,000 ticks, one and a half market days).
- **Winter freezes only the highlands.** The lowlands stay at or above freezing all year; winter there is cool and wet.
- **The Arbors stay lush all year** (a seasonal tint only).
- **Weather does not affect vehicles** (or flight handling).
- **Storms and Hive raids can destroy crops**, and **weather can damage structures** ([settlement](settlement-building.md)).
- **Night glow stays on for every tree, all year** (evergreens and Arbors year-round; the broadleaf forest strongest in autumn, dimmer on bare winter branches).
- **Highland ice is walkable.**
- **Seasons do not change sap flow or machine power.**

**Audience:** engineers and coding agents. The three Zig blocks labelled *compiled* (four tests) passed `zig test` on the default compiler (`0.16.0-dev.3142+5ccfeb926`) and on `HEAVYWATER_ZIG_CHANNEL=0.17` (4 of 4 tests each), and were extracted back out of this document and re-tested. They illustrate the design and are not committed code.

## 1. Goals and rules

1. **Seasons you can feel.** Spring greens up, summer is long and bright, autumn turns the broadleaf trees copper and brings rain, winter snows the land and strips the deciduous crowns. Each change must read at a glance in the cel-shaded style.
2. **Moody, not photoreal.** No bloom and no texture stack ([visual direction](visual-direction.md)). Weather is colour, light, fog, particles and a few readable surface changes.
3. **Everything is a pure function of the saved tick.** The calendar and the weather are derived from `sandbox.tick` and the world seed. **No save field is added**, saves stay compatible, and a reloaded game is in the same season and weather.
4. **Never read the real clock.** Captures, benchmarks and smoke runs must repeat exactly.
5. **One formula for the eye and the feet.** Where weather changes what the player stands on (snow, wet ground), the shader and the footing code use the same function and constants, so the picture never disagrees with the physics.
6. **Combat stays readable.** Fog and precipitation have caps so enemies remain legible within about 40 m ([world](../world.md): hack-and-slash outside the cities).
7. **Bounded and allocation-free,** like the rest of the frame path ([AGENTS.md](../../AGENTS.md)).

## 2. What exists today

| Area | State | Source |
| --- | --- | --- |
| Time | `sandbox.tick` is the only persisted time; a day is `Sky.day_ticks` = 72,000 ticks; `Market.dayOf` turns over at dawn. **No season, year or weather exists.** | `engine/Sky.zig`, `city/Market.zig`, `game/Save.zig` |
| Sky | `Sky.at(time)` is pure and returns the key light, ambient sky and ground, horizon and zenith colours and a night factor; there is no overcast input. The clear colour is the horizon colour; there is no skybox. | `engine/Sky.zig` |
| Frame uniform | 272 bytes with compile-time asserts (`planes` at 160, `params` at 256); `ambient_sky.w` and `ambient_ground.w` are unused; all four `params` lanes are used (clock, wind strength, wind direction). | `render/Renderer.zig:30`, `render/scene.wgsl` |
| Snow and frost | Snow colour is **baked into chunk vertices** by `Biome.terrainColor`; flora frost is baked into instance tints by `Scatter.frosted`. The snowline is a static function of altitude. | `procedural/Biome.zig`, `procedural/Scatter.zig` |
| Haze | `hazed()` is the only fog, with hard-coded constants shared by every pipeline; `lit()` is the shared toon light. | `render/scene.wgsl` |
| Wind | Cosmetic, computed in one place from the clock; not shared with gameplay or audio. | `render/Renderer.zig:~549`, `render/foliage.wgsl` |
| Footing | `Biome.Kind` grass, sand, marsh, rock, snow, from `Biome.cover` at the player's position; speed and traction per kind. | `game/Player.zig`, `game/Sandbox.zig:~936` |
| Water | Blended, drawn last, with ripples scrolled by the clock. | `render/water.wgsl` |
| Audio | Wind and canopy loops with no weather input. | `audio/Director.zig` |

Because snow and frost are baked, **seasonal change has to come from shader uniforms and the vertex stage, not from regenerating chunks.** Regenerating would touch the generator version and the upload budget.

## 3. The calendar

`calendar(tick)` is pure and integer-based. A year is 432,000 ticks and a season 108,000. A new game starts a tenth of the way into spring. The 128-bit shift keeps it exact at the end of the `u64` range, like `Sky.timeOfDay`. The continuous `year_t` drives smooth effects; the discrete `season` selects tables.

The market day stays 72,000 ticks and keeps turning over at dawn: a season is one and a half days, so seasons change at midday or midnight as often as at dawn, which is fine.

| Season | Character | Light | Weather odds (of 100) | Land |
| --- | --- | --- | --- | --- |
| Spring | fresh, wet | softer, rising sun | clear 25, cloudy 20, light 20, rain 20, storm 5, fog 10 | bright greens, blossom accents, low snow melts |
| Summer | long and bright | high sun, longest days | clear 45, cloudy 20, light 10, rain 10, storm 10, fog 5 | deep greens, dry arid ground |
| Autumn | copper and rain | lower, warmer sun | clear 25, cloudy 25, light 15, rain 20, storm 5, fog 10 | broadleaf crowns turn copper, then drop |
| Winter | cool and wet on the plains, snowbound on the heights | low sun, short days | clear 25, cloudy 30, light 15, rain 15, storm 10, fog 5 | rain in the lowlands; snow and frozen shallows on the highlands; the broadleaf forest drops its leaves, the civic Arbors do not |

*Compiled* (calendar, with start, boundaries, progress, periodicity and the end of the `u64` range tested):

```zig
const tau = std.math.tau;

fn clamp01(x: f32) f32 {
    return std.math.clamp(x, 0, 1);
}
fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3 - 2 * t);
}
fn mixf(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub const day_ticks: u64 = 72_000; // the existing 20-minute day (`Sky.day_ticks`)
pub const ticks_per_year: u64 = 432_000; // two hours at 60 Hz
pub const ticks_per_season: u64 = 108_000; // thirty minutes: one and a half days
/// A new game starts a tenth of the way into spring.
pub const start_offset: u64 = ticks_per_season / 10;

pub const Season = enum(u2) { spring, summer, autumn, winter };

pub const Calendar = struct {
    season: Season,
    /// Progress through the season, 0 up to (not including) 1.
    season_t: f32,
    year: u64,
    /// Progress through the year, 0 up to (not including) 1; drives every smooth seasonal effect.
    year_t: f32,
    day_of_year: u32,
};

pub fn calendar(tick: u64) Calendar {
    // 128-bit arithmetic so the offset cannot overflow near the end of the u64 range.
    const shifted: u128 = @as(u128, tick) + start_offset;
    const year: u64 = @intCast(shifted / ticks_per_year);
    const in_year: u64 = @intCast(shifted % ticks_per_year);
    const in_season = in_year % ticks_per_season;
    return .{
        .season = @enumFromInt(@as(u2, @intCast(in_year / ticks_per_season))),
        .season_t = @as(f32, @floatFromInt(in_season)) / @as(f32, @floatFromInt(ticks_per_season)),
        .year = year,
        .year_t = @as(f32, @floatFromInt(in_year)) / @as(f32, @floatFromInt(ticks_per_year)),
        .day_of_year = @intCast(in_year / day_ticks),
    };
}

test "the calendar starts in early spring, turns every 108,000 ticks and repeats yearly" {
    const start = calendar(0);
    try std.testing.expectEqual(Season.spring, start.season);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), start.season_t, 1e-6);
    try std.testing.expectEqual(@as(u64, 0), start.year);
    // The first spring lasts 90% of a season from tick 0.
    try std.testing.expectEqual(Season.spring, calendar(ticks_per_season - start_offset - 1).season);
    try std.testing.expectEqual(Season.summer, calendar(ticks_per_season - start_offset).season);
    try std.testing.expectEqual(Season.autumn, calendar(2 * ticks_per_season - start_offset).season);
    try std.testing.expectEqual(Season.winter, calendar(3 * ticks_per_season - start_offset).season);
    const next = calendar(4 * ticks_per_season - start_offset);
    try std.testing.expectEqual(Season.spring, next.season);
    try std.testing.expectEqual(@as(u64, 1), next.year);
    // Progress through a season and through the year is exact at known moments.
    const mid_spring = calendar(ticks_per_season / 2 - start_offset);
    try std.testing.expectEqual(Season.spring, mid_spring.season);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mid_spring.season_t, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), mid_spring.year_t, 1e-6);
    const quarter_summer = calendar(ticks_per_season + ticks_per_season / 4 - start_offset);
    try std.testing.expectEqual(Season.summer, quarter_summer.season);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), quarter_summer.season_t, 1e-6);
    try std.testing.expectEqual(@as(u32, 2), calendar(2 * day_ticks - start_offset).day_of_year); // the third day begins
    // Periodic: one year later is the same moment of the year.
    for ([_]u64{ 0, 12_345, 200_000, 431_999 }) |t| {
        const a = calendar(t);
        const b = calendar(t + ticks_per_year);
        try std.testing.expectEqual(a.season, b.season);
        try std.testing.expectEqual(a.year + 1, b.year);
        try std.testing.expectEqual(a.year_t, b.year_t);
    }
    // Nothing overflows or leaves its range at the end of time.
    const last = calendar(std.math.maxInt(u64));
    try std.testing.expect(last.year_t >= 0 and last.year_t < 1 and last.season_t >= 0 and last.season_t < 1);
    try std.testing.expect(last.day_of_year < 6);
}
```

## 4. Climate

`temperature` is a pure function of year phase, time of day, altitude and aridity: warmest mid-summer and mid-afternoon, coldest in mid-winter before dawn, cooler with altitude at a game-scale lapse rate (5 degrees per 100 m), with arid ground swinging further between day and night. It decides whether precipitation falls as rain or snow (`snowMix`), where frost forms, how fast crops grow ([settlement](settlement-building.md)) and where the **seasonal snowline** sits (`freezingAltitude`). Permanent peak snow stays baked as it is today; seasonal snow is added on top by the shader.

Tunables (all in one table, expected to be adjusted by playing): mean 14 degrees, seasonal amplitude 8, diurnal swing 3 to 6 by aridity, lapse 0.05 per metre, rain-to-snow band from 2 down to -1 degrees. **By the owner's decision the lowlands never freeze:** the coldest lowland moment of the year, for every ground, is at or just above 0 degrees, and a test scans the whole year to keep it so. The freezing line sits at about 180 m at a midwinter noon and about 500 m in summer, so the plains and low hills get winter rain while the mountain flanks get snow, ice and frost.

**Ice.** Still water freezes from the coldest air of the day (just before dawn): none above -1 degrees, thickening to half a metre as it gets colder. Ice you can walk on (and ride a hover board over) starts at 15 cm. With the tuned numbers the plains (altitude 0) never see ice; low hills of about 40 m can grow at most a thin, unwalkable skin on the coldest dry winter dawn; a mountain lake at 300 m carries thick walkable ice in midwinter and none in midsummer. Open irrigation channels and ponds stop flowing while iced ([settlement](settlement-building.md) section 7); buried pipes keep flowing.

*Compiled* (climate and ice: ice thickness from the coldest hour of the day, absent on the plains, walkable from 15 cm; a whole-year scan proving the lowlands never freeze, the highlands freezing in winter, altitude, aridity, wrap-around, and rain in the lowlands against snow on the heights):

```zig
/// Degrees Celsius. Warmest in mid-summer and mid-afternoon, coolest in mid-winter before dawn.
/// The lowlands stay at or above freezing all year (a mild, wet winter); altitude cools strongly
/// (a game-scale lapse rate of 5 degrees per 100 metres), so only the highlands freeze in winter.
/// Arid ground swings a little more between day and night.
pub fn temperature(year_t: f32, time_of_day: f32, altitude_m: f32, aridity: f32) f32 {
    const seasonal = 14 + 8 * @cos(tau * (year_t - 0.375));
    const swing = 3 + 3 * clamp01(aridity);
    const diurnal = swing * @cos(tau * (time_of_day - 0.6));
    return seasonal + diurnal - 0.05 * @max(altitude_m, 0);
}

/// The altitude above which the air is below freezing right now (0 when even the lowlands freeze).
/// This replaces the static snowline for seasonal snow; permanent peaks keep their baked snow.
pub fn freezingAltitude(year_t: f32, time_of_day: f32, aridity: f32) f32 {
    const warm = temperature(year_t, time_of_day, 0, aridity);
    return if (warm <= 0) 0 else warm / 0.05;
}

/// Ice thickness in metres on still water, from the coldest air of the day (just before dawn).
/// Nothing freezes above -1 degrees; the ice thickens as it gets colder and caps at half a metre.
pub fn iceThickness(year_t: f32, altitude_m: f32, aridity: f32) f32 {
    const coldest = temperature(year_t, 0.1, altitude_m, aridity);
    return 0.5 * clamp01((-coldest - 1) / 8);
}

/// Walkable ice: thick enough to carry a person and a hover board. Thinner ice is slick water.
pub const walkable_ice_m: f32 = 0.15;
pub fn iceWalkable(thickness_m: f32) bool {
    return thickness_m >= walkable_ice_m;
}

/// 0 for rain, 1 for snow, blending through the sleet band between 2 and -1 degrees.
pub fn snowMix(celsius: f32) f32 {
    return smoothstep(2, -1, celsius);
}

test "the lowlands never freeze, the highlands do in winter, and altitude and aridity act as described" {
    // Summer afternoons are warm; midwinter lowland nights are cool but not freezing, for every ground.
    try std.testing.expect(temperature(0.375, 0.6, 0, 0) > 24);
    var coldest: f32 = 100;
    var year: f32 = 0;
    while (year < 1) : (year += 0.01) {
        var tod: f32 = 0;
        while (tod < 1) : (tod += 0.05) {
            for ([_]f32{ 0, 0.5, 1 }) |aridity| coldest = @min(coldest, temperature(year, tod, 0, aridity));
        }
    }
    try std.testing.expect(coldest >= -0.01);
    // Altitude cools: two hundred metres is ten degrees colder, so a midwinter highland freezes.
    try std.testing.expectApproxEqAbs(temperature(0.375, 0.6, 0, 0) - temperature(0.375, 0.6, 200, 0), 10, 1e-4);
    try std.testing.expect(temperature(0.875, 0.6, 300, 0) < 0);
    // The freezing line is a few hundred metres up in midwinter and far higher in summer, so the
    // plains and low hills never freeze but the mountain flanks do.
    const winter_line = freezingAltitude(0.875, 0.6, 0);
    try std.testing.expect(winter_line > 100 and winter_line < 300);
    try std.testing.expect(freezingAltitude(0.375, 0.6, 0) > 400);
    // Arid ground swings further between day and night than meadow does.
    const arid = temperature(0.375, 0.6, 0, 1) - temperature(0.375, 0.1, 0, 1);
    const meadow = temperature(0.375, 0.6, 0, 0) - temperature(0.375, 0.1, 0, 0);
    try std.testing.expect(arid > meadow);
    // The year wraps without a jump.
    try std.testing.expectApproxEqAbs(temperature(0.99999, 0.3, 40, 0.5), temperature(0.0, 0.3, 40, 0.5), 0.01);
    // Rain below, snow above the freezing band.
    try std.testing.expectEqual(@as(f32, 0), snowMix(5));
    try std.testing.expectEqual(@as(f32, 1), snowMix(-4));
    try std.testing.expect(snowMix(0.5) > 0 and snowMix(0.5) < 1);
    // So lowland winter precipitation falls as rain; highland winter precipitation falls as snow.
    try std.testing.expectEqual(@as(f32, 0), snowMix(temperature(0.875, 0.6, 0, 0.3)));
    try std.testing.expectEqual(@as(f32, 1), snowMix(temperature(0.875, 0.6, 400, 0.3)));
}

test "highland water freezes hard enough to walk on in winter, lowland water never freezes" {
    // The plains never see ice, in any season, for any ground.
    var year: f32 = 0;
    while (year < 1) : (year += 0.01) {
        for ([_]f32{ 0, 0.5, 1 }) |aridity| try std.testing.expectEqual(@as(f32, 0), iceThickness(year, 0, aridity));
    }
    // Low hills (40 m) can grow at most a thin, unwalkable skin of ice on the coldest dry winter dawn.
    try std.testing.expect(!iceWalkable(iceThickness(0.875, 40, 1)));
    try std.testing.expectEqual(@as(f32, 0), iceThickness(0.875, 40, 0)); // wet ground stays above freezing there
    // A mountain lake at 300 m carries ice in midwinter and none in midsummer.
    const midwinter = iceThickness(0.875, 300, 0.3);
    try std.testing.expect(iceWalkable(midwinter) and midwinter <= 0.5);
    try std.testing.expectEqual(@as(f32, 0), iceThickness(0.375, 300, 0.3));
    // Ice follows the coldest hour of the day (just before dawn), not the afternoon: at 150 m the
    // midwinter afternoon is above freezing, yet the dawn ice is thick enough to walk on.
    try std.testing.expect(temperature(0.875, 0.6, 150, 0.3) > 0);
    try std.testing.expect(iceWalkable(iceThickness(0.875, 150, 0.3)));
    // Higher is colder: ice is never thinner higher up, and thin ice is not walkable.
    try std.testing.expect(iceThickness(0.875, 800, 0.3) >= iceThickness(0.875, 400, 0.3));
    try std.testing.expect(!iceWalkable(0.1) and iceWalkable(0.15));
    // The ice forms gradually through the autumn rather than appearing in one step.
    var previous = iceThickness(0.6, 300, 0.3);
    var worst_step: f32 = 0;
    year = 0.6;
    while (year <= 0.9) : (year += 0.005) {
        const now = iceThickness(year, 300, 0.3);
        worst_step = @max(worst_step, @abs(now - previous));
        previous = now;
    }
    try std.testing.expect(worst_step < 0.05);
    try std.testing.expectApproxEqAbs(iceThickness(0.99999, 300, 0.3), iceThickness(0.0, 300, 0.3), 0.01);
}
```

## 5. Weather

Weather is a deterministic sequence of three-minute windows. Each window picks one of six kinds from the season's table (clear, cloudy, light precipitation, precipitation, storm, fog) by hashing `(seed, window)`; the last fifteen seconds of a window crossfade into the next. The output is precipitation, cloud cover, fog, wind and thunder, each from 0 to 1. Whether precipitation is rain or snow, and how much lands, is decided **where the player is**: temperature gives the rain-to-snow mix, and local moisture scales the amount (arid ground gets about a third, wetland more).

Rules: the window is chosen from the tick only; storms alone carry thunder; no value leaves 0 to 1; nothing overflows at the end of the `u64` range; the crossfade is continuous across window edges.

*Compiled* (determinism, continuity across 2,000 window edges, each season's odds over 6,000 windows within three percent, bounds, local moisture, and the end of the `u64` range):

```zig
pub const window_ticks: u64 = 10_800; // three minutes
pub const fade_ticks: u64 = 900; // fifteen seconds of crossfade at the end of a window

pub const Kind = enum(u3) { clear, cloudy, light_precip, precip, storm, fog };

pub const State = struct {
    precipitation: f32,
    cloud: f32,
    fog: f32,
    wind: f32,
    thunder: f32,
};

const kind_states = [6]State{
    .{ .precipitation = 0, .cloud = 0.1, .fog = 0, .wind = 0.3, .thunder = 0 }, // clear
    .{ .precipitation = 0, .cloud = 0.6, .fog = 0, .wind = 0.4, .thunder = 0 }, // cloudy
    .{ .precipitation = 0.25, .cloud = 0.8, .fog = 0.1, .wind = 0.5, .thunder = 0 }, // light
    .{ .precipitation = 0.7, .cloud = 0.9, .fog = 0.15, .wind = 0.7, .thunder = 0 }, // precipitation
    .{ .precipitation = 1.0, .cloud = 1.0, .fog = 0.2, .wind = 1.0, .thunder = 1 }, // storm
    .{ .precipitation = 0, .cloud = 0.7, .fog = 0.7, .wind = 0.1, .thunder = 0 }, // fog
};

/// Per-season odds out of 100 for each kind, in `Kind` order. Whether precipitation falls as
/// rain or snow is decided where it lands, by temperature, not here.
const season_weights = [4][6]u8{
    .{ 25, 20, 20, 20, 5, 10 }, // spring
    .{ 45, 20, 10, 10, 10, 5 }, // summer
    .{ 25, 25, 15, 20, 5, 10 }, // autumn
    .{ 25, 30, 15, 15, 10, 5 }, // winter
};

fn mix64(x: u64) u64 {
    var z = x +% 0x9e3779b97f4a7c15;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

pub fn kindFor(seed: u64, window: u64, season: Season) Kind {
    const roll: u8 = @intCast(mix64(seed ^ mix64(window)) % 100);
    var total: u16 = 0;
    for (season_weights[@intFromEnum(season)], 0..) |weight, i| {
        total += weight;
        if (roll < total) return @enumFromInt(@as(u3, @intCast(i)));
    }
    return .clear;
}

fn windowKind(seed: u64, window: u64) Kind {
    return kindFor(seed, window, calendar(window *| window_ticks).season);
}

/// The weather at `tick`: this window's kind, crossfading into the next window's during the last
/// `fade_ticks`. A pure function, so saves, captures and smoke runs repeat exactly.
pub fn weatherAt(seed: u64, tick: u64) State {
    const window = tick / window_ticks;
    const into = tick % window_ticks;
    const current = kind_states[@intFromEnum(windowKind(seed, window))];
    if (into + fade_ticks < window_ticks) return current;
    const next = kind_states[@intFromEnum(windowKind(seed, window +| 1))];
    const t = smoothstep(0, 1, @as(f32, @floatFromInt(into + fade_ticks - window_ticks)) / @as(f32, @floatFromInt(fade_ticks)));
    return .{
        .precipitation = mixf(current.precipitation, next.precipitation, t),
        .cloud = mixf(current.cloud, next.cloud, t),
        .fog = mixf(current.fog, next.fog, t),
        .wind = mixf(current.wind, next.wind, t),
        .thunder = mixf(current.thunder, next.thunder, t),
    };
}

/// Precipitation where it lands: arid ground (moisture 0) gets a third, wetland (1) gets more.
pub fn localPrecipitation(state: State, moisture: f32) f32 {
    return clamp01(state.precipitation * mixf(0.3, 1.3, clamp01(moisture)));
}

test "weather is deterministic, continuous across windows, season-weighted and bounded" {
    const seed: u64 = 0x4845415659;
    try std.testing.expectEqual(weatherAt(seed, 123_456), weatherAt(seed, 123_456));
    // No jump where one window ends and the next begins.
    var worst: f32 = 0;
    for (1..2000) |w| {
        const edge = w * window_ticks;
        const a = weatherAt(seed, edge - 1);
        const b = weatherAt(seed, edge);
        worst = @max(worst, @abs(a.precipitation - b.precipitation));
        worst = @max(worst, @abs(a.cloud - b.cloud));
        worst = @max(worst, @abs(a.wind - b.wind));
    }
    try std.testing.expect(worst < 0.01);
    // Over many windows each season's mix of kinds follows its table.
    for (0..4) |s| {
        var counts: [6]usize = @splat(0);
        const samples: usize = 6000;
        for (0..samples) |w| counts[@intFromEnum(kindFor(seed, @intCast(w), @enumFromInt(@as(u2, @intCast(s)))))] += 1;
        for (counts, season_weights[s]) |got, want| {
            const share = @as(f32, @floatFromInt(got)) / @as(f32, @floatFromInt(samples));
            try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(want)) / 100, share, 0.03);
        }
    }
    // Summer is clearer than winter; thunder belongs to storms; values stay in range everywhere.
    try std.testing.expect(season_weights[1][0] > season_weights[3][0]);
    for (0..4000) |i| {
        const state = weatherAt(seed, @as(u64, @intCast(i)) * 997);
        for ([_]f32{ state.precipitation, state.cloud, state.fog, state.wind, state.thunder }) |v| try std.testing.expect(v >= 0 and v <= 1);
    }
    try std.testing.expectEqual(@as(f32, 0), kind_states[@intFromEnum(Kind.clear)].thunder);
    // Arid ground is drier than wetland under the same sky.
    const storm = kind_states[@intFromEnum(Kind.precip)];
    try std.testing.expect(localPrecipitation(storm, 0) < localPrecipitation(storm, 1));
    // The end of the u64 range does not overflow.
    _ = weatherAt(seed, std.math.maxInt(u64));
}
```

## 6. Rendering

### 6.1 Frame uniform

Append two `vec4`s after `params` so every existing offset keeps its value. The frame grows from 272 to 304 bytes; the compile-time assert, the WGSL mirror in `scene.wgsl`, and every shader that mirrors the struct (including the skinned-character shaders) change together. One frame is written per view, so all four split-screen views get the same global weather.

| Field | Offset | Contents |
| --- | --- | --- |
| `params` (existing) | 256 | clock, wind strength, wind direction (unchanged) |
| `weather` | 272 | precipitation, snow mix, wetness, fog |
| `season` | 288 | year phase, canopy fullness, snowline altitude, temperature |

The two free lanes (`ambient_sky.w`, `ambient_ground.w`) are not enough and would hide meaning; explicit fields are clearer.

### 6.2 Shader changes

| Stage | Change |
| --- | --- |
| Terrain | wet darkening and a faint sheen when wet; **seasonal snow** from world height and normal against the uploaded snowline altitude (the same smoothstep the footing code uses); meltwater darkening near the line; frozen ground tint |
| Foliage | season tint ramp by species group; **leaf drop** for deciduous species by a hashed per-leaf threshold in the vertex stage (bark stays, by the existing UV tag); gust strength from weather wind; evergreens (needleleaf, redwood, pine) and the **civic Arbors** keep their crowns all year, with only a seasonal tint on the Arbors; **night glow stays on for every tree all year** (owner decision): evergreens and Arbors glow year-round, the broadleaf forest glows strongest in autumn and keeps a dimmer glow on bare winter branches |
| Water | rain ripples; ice only where the temperature is below zero, which is the highlands (a frozen tint and still surface; **walkable** once thick enough, section 4) |
| `hazed()` and `lit()` | fog density from `weather.w`, keeping the 0.95 cap and the terrain-edge hiding; overcast lowers the key light and raises the ambient fraction |
| Precipitation | a spliced `weather.wgsl` vertex stage draws rain streaks and snow flakes as a fixed pool of instanced quads whose positions are generated in the vertex stage from the instance id, the clock and the view's eye (a camera-local box that wraps), blended like water; no per-frame CPU instance writes, no atomics, none of the WGSL features Mach lacks (`cross`, `pow`, `reflect`) |
| Sky | `Sky.at` gains season (a small change of sun height and day length) and overcast inputs and stays pure; the `space_review` override still bypasses it |

### 6.3 Budgets and quality

A pool of about 2,000 quads per view (8,000 across four views) scales with precipitation and a quality setting. GPU time cannot be measured through Mach timestamps (an engine gap); judge by CPU p99, presentation intervals and the Metal HUD or an Xcode capture, which are untried here. Keep the benchmark's CPU p99 unchanged.

## 7. Gameplay hooks

| System | Change |
| --- | --- |
| Footing | add wet and dynamic snow to the `Biome.Kind` result through one shared function; wet ground lowers traction a little; seasonal snow slows like the existing snow kind; **walkable ice** on frozen highland water as a new `ice` footing kind (low traction, safe to walk on, hover boards ride it) from the same thickness function as the shader |
| Movement and vehicles | **none for vehicles and flight (owner decision).** Weather stays visual and audible; ground footing on foot is the only handling change |
| Audio | `Director.snapshot` gains weather and season: a rain loop, a wind loop scaled by weather wind, thunder with distance delay, a quieter winter ambience |
| Market | seasonal stock weights; `Market.dayOf` and `restore` stay untouched |
| Sap and machines | **none (owner decision):** seasons do not change sap flow or machine power |
| Hive and enemies | none at first; storm fog is capped for readability |
| Structures | storms and heavy highland snowfall can damage buildings (and storms can flatten crops), deterministically; settlers repair from the shared stockpile; designed in [settlement](settlement-building.md) section 5 |
| Farming | the season, temperature and rain drive crop growth ([settlement](settlement-building.md)) |
| HUD | a small season and weather indicator next to the day count |

## 8. Phases

Sizes: S under a day, M a few days, L about a week. Part of the nature track, time-boxed against the MVP gate ([next steps](next-steps.md)).

**W0. Calendar and climate core (S).** Add `procedural/Climate.zig` (or `engine/Calendar.zig`) with the three blocks above and their tests; add `-Dseason=N` and `-Dweather=name` options to pin a capture. *Tests:* the block tests; every `Sky` test still passes. *Acceptance:* gate green; no save change.

**W1. Frame lanes and surface shaders (M).** Extend the `Frame` struct, assert and every shader mirror; implement the terrain, foliage and water changes with the same snow formula in the footing code. *Tests:* a layout assert; a test that splices every changed stage onto the shared prelude and compiles it through Mach's WGSL compiler; snow cover agrees between the CPU function and a table of expected values. *Acceptance:* captures of one scene in the four seasons.

**W2. Weather state, precipitation, fog and sky (M).** Add `weatherAt` to the sim publish path, the `weather.wgsl` pool, `hazed()` and `lit()` inputs, and `Sky.at` season and overcast. *Acceptance:* rain, snow, fog and a storm captured at a daylight and a dusk showcase; Metal validation clean.

**W3. Gameplay hooks and audio (M).** Footing, optional wind, the audio snapshot and the market weights; HUD indicator. *Tests:* footing for each ground and weather; audio snapshot values; the market restore path unchanged.

**W4. Seasonal content (S).** Leaf drop for the broadleaf forest species (the civic Arbors stay lush), the night-glow rule for every tree (evergreens and Arbors all year; broadleaf strongest in autumn and dimmer on bare branches), blossom accents. *Acceptance:* a species lineup capture per season.

**W5. Captures, smoke and benchmark (S).** A capture matrix, a smoke stage that sweeps one whole year (like the existing sky sweep) under `MTL_DEBUG_LAYER=1`, and `tools/benchmark.py --nature` before and after. Record what ran in [validation](../validation.md).

### Capture matrix

Pin `sandbox.tick` (existing showcases already do) and add the season and weather pins from W0.

| | Clear | Rain | Snow or storm |
| --- | --- | --- | --- |
| Spring | 71, 72, 73 | 72 | |
| Summer | 71, 72, 73 | 72 | storm over 72 |
| Autumn | 72, 62 | 72 | |
| Winter | 71, 72, 73 | | snow over 71 and 72, on the high ground only |

Showcase 62 and the close tree views (74, 75) also get an autumn and a winter frame to check leaf drop.

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| Baked snow and frost disagree with shader snow | seasonal snow is shader-only; permanent snow stays baked; one footing function; a capture check |
| Pinned captures drift when the season depends on the tick | explicit season and weather pins; document them in the showcase table |
| `space_review` bypasses `Sky.at` | weather inputs are applied after the override or the review stays weather-free by rule |
| Fog and rain hurt combat readability | cap fog and precipitation; test enemy visibility distance in a capture |
| Frame layout drift across shaders | a compile-time assert and a test that every mirror is updated together |
| GPU cost of precipitation is unmeasured | bounded pool, a quality setting, Metal HUD or Xcode capture before widening |
| Four split-screen views each draw the pool | keep the pool per view small; measure at four players |

## 10. Decisions

**Recorded (owner, 2026-10-15):**

| Topic | Decision | Effect |
| --- | --- | --- |
| Winter | only the highlands freeze | climate retuned; a test keeps the lowlands at or above freezing all year |
| Arbors | stay lush all year | civic Arbors keep their crowns with a seasonal tint; deciduous drop applies to the wild broadleaf forest only |
| Vehicles | weather does not affect them | no wind or traction hooks for vehicles or flight |
| Crop losses | storms and raids can destroy crops | the storm rule in [settlement](settlement-building.md) section 7 |

**Also recorded (owner, 2026-10-15, second round):**

| Topic | Decision | Effect |
| --- | --- | --- |
| Night glow | yes for every tree, all year | evergreens and Arbors glow year-round; the broadleaf forest peaks in autumn and keeps a dimmer glow on bare branches |
| Ice | walkable on the highlands | an `ice` footing kind from the thickness function (section 4); hover boards ride it |
| Sap and machines | no seasonal change | no sap or power hooks |
| Structures | weather can damage them | storms and heavy snow damage buildings; repair from the stockpile ([settlement](settlement-building.md) section 5) |

**Still open (tuning, not decisions):** the exact glow strength of bare winter branches; the thickness at which a hover board rides ice; how often storms strike.

## 11. Reference

Sources read: [Sky.zig](../../src/engine/Sky.zig), [Renderer.zig](../../src/render/Renderer.zig), [scene.wgsl](../../src/render/scene.wgsl), [terrain.wgsl](../../src/render/terrain.wgsl), [foliage.wgsl](../../src/render/foliage.wgsl), [water.wgsl](../../src/render/water.wgsl), [Biome.zig](../../src/procedural/Biome.zig), [Scatter.zig](../../src/procedural/Scatter.zig), [Market.zig](../../src/city/Market.zig), [Save.zig](../../src/game/Save.zig), [Director.zig](../../src/audio/Director.zig).

```sh
python3 tools/zig.py test season_examples.zig                              # default pair: 4 of 4
HEAVYWATER_ZIG_CHANNEL=0.17 python3 tools/zig.py test season_examples.zig  # 0.17: 4 of 4
```
