//! Strategic-scale Sol-system destinations and fictional fusion-pulse transit rules.
//! Planet locations use AU and f64 metadata; regional gameplay remains in bounded local frames.
pub const light_speed_m_s: f64 = 299_792_458;
pub const au_m: f64 = 149_597_870_700;
pub const fusion_pulse_cruise_c: f64 = 0.5;

pub const PlanetId = enum(u8) { mercury, venus, earth, mars, jupiter, saturn, uranus, neptune };
pub const Governance = enum { earth_transition, frontier_charter, colony_council, contested, treaty_zone, research_compact, independent };
pub const Planet = struct {
    id: PlanetId,
    name: []const u8,
    orbit_au: f64,
    gravity_m_s2: f32,
    governance: Governance,
    region: []const u8,
    settlement_hook: []const u8,
};

pub const Moon = struct {
    name: []const u8,
    parent: PlanetId,
    region: []const u8,
    settlement_hook: []const u8,
};

pub const MiningRole = enum { prospector, extractor, hauler };
pub const MiningDroid = struct {
    name: []const u8,
    role: MiningRole,
    health: f32,
    resource_units_per_minute: f32,
    defense_damage: f32,
};

pub const MiningSite = struct {
    body: []const u8,
    planet: PlanetId,
    resource: []const u8,
    operation: []const u8,
};

pub const Council = struct {
    name: []const u8,
    lower_chamber: []const u8,
    upper_chamber: []const u8,
    quorum_percent: u8,
    principles: []const []const u8,
};

/// A political framework for the story: the Solar Assembly grows into the Galactic Democratic
/// Compact only when new peoples choose to join. Hive citizens and Scalari dissidents are not
/// automatically treated as representatives of their former rulers.
pub const democracy = Council{
    .name = "Galactic Democratic Compact",
    .lower_chamber = "Assembly of Citizens",
    .upper_chamber = "Council of Worlds and Habitats",
    .quorum_percent = 60,
    .principles = &.{
        "Every person has equal civic rights regardless of species or origin.",
        "Settlements govern local life; the Compact handles shared defense, transit, and rights guarantees.",
        "Worlds and habitats receive representation without allowing a single capital to rule them.",
        "Membership follows a free, informed public vote; liberation does not impose annexation.",
        "Public war powers expire unless renewed by both chambers, with civilian review of the fleet.",
    },
};

/// These are fictional settlement/campaign records at the canonical eight planet orbits.
/// Gaia is a built habitat in Saturn-space; the Hive/Scalari homeworld remains interstellar.
pub const planets = [_]Planet{
    .{ .id = .mercury, .name = "Mercury", .orbit_au = 0.387, .gravity_m_s2 = 3.70, .governance = .research_compact, .region = "Terminator Foundries", .settlement_hook = "Twilight crater cities, solar furnaces, and relay observatories; rescue workers when a sunward automation network goes rogue." },
    .{ .id = .venus, .name = "Venus", .orbit_au = 0.723, .gravity_m_s2 = 8.87, .governance = .treaty_zone, .region = "Cloudhaven", .settlement_hook = "Floating pressure habitats trade rare cloud chemistry under a strict planetary-protection and worker-rights treaty." },
    .{ .id = .earth, .name = "Earth", .orbit_au = 1.0, .gravity_m_s2 = 9.81, .governance = .earth_transition, .region = "Arbor Frontier", .settlement_hook = "The Arbor canopy shipyard, Pelaglass pressure domes, and Sonorous Reef's fully submerged cetacean city anchor the founding coalition." },
    .{ .id = .mars, .name = "Mars", .orbit_au = 1.524, .gravity_m_s2 = 3.71, .governance = .colony_council, .region = "Ares Commons", .settlement_hook = "A network of canyon farms and lava-tube neighborhoods debates water rights, terraforming pace, and representation for new arrivals." },
    .{ .id = .jupiter, .name = "Jupiter", .orbit_au = 5.204, .gravity_m_s2 = 24.79, .governance = .treaty_zone, .region = "Galilean League", .settlement_hook = "Europa, Ganymede, Callisto, and Io share convoy defense and resource rules while rival interests contest access to the outer moons." },
    .{ .id = .saturn, .name = "Saturn", .orbit_au = 9.582, .gravity_m_s2 = 10.44, .governance = .colony_council, .region = "Ringward Assembly", .settlement_hook = "Titan and Enceladus settlements negotiate ring-mining limits; Gaia's artificial globe and Jovian Gate hold a protected transfer orbit here." },
    .{ .id = .uranus, .name = "Uranus", .orbit_au = 19.201, .gravity_m_s2 = 8.69, .governance = .research_compact, .region = "Blueglass Stations", .settlement_hook = "Remote stations and service habitats face a failing thermal grid during a decades-long polar night." },
    .{ .id = .neptune, .name = "Neptune", .orbit_au = 30.047, .gravity_m_s2 = 11.15, .governance = .independent, .region = "Triton Free Port", .settlement_hook = "Triton's independent port votes on joining the Compact as an intercepted Scalari courier reaches the system edge." },
};

/// Locally visitable destinations around each planet; this deliberately omits orbital mechanics.
pub const moons = [_]Moon{
    .{ .name = "Luna", .parent = .earth, .region = "South Pole Relay", .settlement_hook = "A public transit hub and water-ice reserve where Earth's first Compact charter is debated." },
    .{ .name = "Phobos", .parent = .mars, .region = "Stickney Dockyards", .settlement_hook = "Low-gravity shipyards are being pressured to manufacture Scalari-compatible mining rigs." },
    .{ .name = "Deimos", .parent = .mars, .region = "Far Lantern", .settlement_hook = "A small relay community intercepts a prospector swarm mapping Mars's aquifers." },
    .{ .name = "Io", .parent = .jupiter, .region = "Sulfur Arc", .settlement_hook = "Volcanic extraction crawlers cross a constantly resurfaced field of sulfur vents." },
    .{ .name = "Europa", .parent = .jupiter, .region = "Under-Ice Commons", .settlement_hook = "Ice-mining machines threaten protected subsurface oceans and the settlement's water treaty." },
    .{ .name = "Ganymede", .parent = .jupiter, .region = "Magnetosphere Works", .settlement_hook = "A shielded mining port and magnetic research city organize a convoy-defense vote." },
    .{ .name = "Callisto", .parent = .jupiter, .region = "Quiet Crater", .settlement_hook = "A neutral repair station hides a Scalari material cache beneath a crater settlement." },
    .{ .name = "Titan", .parent = .saturn, .region = "Methane Reach", .settlement_hook = "Hauler droids cross hydrocarbon seas under a fragile labor and extraction compact." },
    .{ .name = "Enceladus", .parent = .saturn, .region = "Geyser Fields", .settlement_hook = "Ice prospectors crowd the plume zone while local scientists demand a biosphere safeguard." },
    .{ .name = "Titania", .parent = .uranus, .region = "Crown Ice Works", .settlement_hook = "A remote ice quarry loses contact during an extended power-grid failure." },
    .{ .name = "Oberon", .parent = .uranus, .region = "Outer Crater Port", .settlement_hook = "A free port votes on whether to accept Compact rescue crews or stay independent." },
    .{ .name = "Triton", .parent = .neptune, .region = "Free Port", .settlement_hook = "An independence vote and an incoming Scalari courier turn a quiet ice settlement into a crisis." },
};

/// The starter Scalari machine is a vulnerable, modular civilian-industrial unit; combat models
/// protect a site, while the droid itself scans, drills, or carries a small resource load.
pub const mining_droid = MiningDroid{ .name = "Talus-class Prospector", .role = .prospector, .health = 45, .resource_units_per_minute = 4, .defense_damage = 2 };

/// Persistent Scalari extraction fronts give each local planet or moon a concrete first mission.
pub const mining_sites = [_]MiningSite{
    .{ .body = "Mercury", .planet = .mercury, .resource = "solar glass", .operation = "Prospectors mark a dawn-side solar-furnace field for stripping." },
    .{ .body = "Venus / Cloudhaven", .planet = .venus, .resource = "carbon silicates", .operation = "Extractor barges steal pressure-habitat filters and seed a terraforming sabotage plot." },
    .{ .body = "Earth / Arbor Frontier", .planet = .earth, .resource = "lumen and alloys", .operation = "Scalari droids survey the frontier shipyard's living-root power network." },
    .{ .body = "Mars / Ares Commons", .planet = .mars, .resource = "water ice", .operation = "A prospecting convoy maps aquifers under a community water reserve." },
    .{ .body = "Jupiter / Europa", .planet = .jupiter, .resource = "ice and reactor salts", .operation = "Drills breach a protected under-ice survey zone." },
    .{ .body = "Saturn / Titan", .planet = .saturn, .resource = "hydrocarbons", .operation = "Haulers divert methane away from a habitat heating grid." },
    .{ .body = "Uranus / Titania", .planet = .uranus, .resource = "cryogenic volatiles", .operation = "A remote excavation site overloads the local thermal relay." },
    .{ .body = "Neptune / Triton", .planet = .neptune, .resource = "nitrogen ice", .operation = "A Scalari survey swarm arrives during Triton's Compact membership vote." },
};

pub const StationModule = enum { landing_dock, habitat, refinery, mining_bay, power_relay, greenhouse, defense_grid, terraformer, assembly_chamber };
pub const starter_station_modules = [_]StationModule{ .landing_dock, .habitat, .refinery, .mining_bay, .power_relay };

pub const Transit = struct {
    distance_au: f64,
    speed_c: f64 = fusion_pulse_cruise_c,

    /// Strategic route duration before acceleration, braking, or encounter detours.
    pub fn seconds(self: Transit) f64 {
        return self.distance_au * au_m / (self.speed_c * light_speed_m_s);
    }

    pub fn minutes(self: Transit) f64 {
        return self.seconds() / 60;
    }
};

pub fn planet(id: PlanetId) Planet {
    return planets[@intFromEnum(id)];
}

pub fn transitBetween(a: PlanetId, b: PlanetId) Transit {
    const delta = @abs(planet(a).orbit_au - planet(b).orbit_au);
    return .{ .distance_au = delta };
}

/// Values are intentionally records rather than absolute renderer coordinates.
pub fn validate() bool {
    if (planets.len != 8 or fusion_pulse_cruise_c <= 0 or fusion_pulse_cruise_c >= 1 or democracy.quorum_percent < 50 or democracy.principles.len == 0 or moons.len != 12 or mining_sites.len != planets.len or mining_droid.health <= 0 or mining_droid.resource_units_per_minute <= 0) return false;
    for (planets, 0..) |p, i| {
        if (@as(usize, @intFromEnum(p.id)) != i or p.name.len == 0 or p.region.len == 0 or p.settlement_hook.len == 0 or p.orbit_au <= 0 or p.gravity_m_s2 <= 0) return false;
        if (i > 0 and p.orbit_au <= planets[i - 1].orbit_au) return false;
    }
    for (moons) |m| if (m.name.len == 0 or m.region.len == 0 or m.settlement_hook.len == 0) return false;
    for (mining_sites, 0..) |site, i| if (@as(usize, @intFromEnum(site.planet)) != i or site.body.len == 0 or site.resource.len == 0 or site.operation.len == 0) return false;
    return true;
}

