//! Specials: three powers per character, paid from energy (0–100, regenerating) and gated by
//! cooldowns. Humans get their class kit; each Wildkin form gets its hero's kit (`Heroes`).
//!
//! Rangers use tech: an **arc grenade** (thrown; bursts for 60 and a 2 s stun), a **sentry
//! turret** (zaps the nearest unit in sight four times a second for 20 s) and an **overshield**
//! (80 over health for 8 s). Synthetics have powers: the **phase dash** (a 14 m blink that cuts
//! and stuns along its path), the **kinetic slam** (70 within 8 m, thrown and stunned) and the
//! **lumen lance** (a 2.5 s channelled beam, 90 a second; a second press ends it).
//!
//! Every power is one row of `info`: a mechanic and its numbers. The mechanics:
//!
//! - **grenade:** thrown; bursts on contact or after 1.2 s (`damage` within `radius`, `stun`).
//! - **sentry:** a turret zapping the nearest unit in sight for `time` s (`damage` per zap).
//! - **shield:** `damage` points of overshield for `time` s.
//! - **blink:** a dash up to `radius` metres, stopping at walls; cuts along the path.
//! - **slam:** a shockwave around the body (`damage`, `stun`, thrown at `push`).
//! - **lance:** a channelled beam along the aim for `time` s, `damage` per second.
//! - **launch:** the body is thrown forward (`push`) and up (`lift`); with `damage`, it spins
//!   through what it hits (an aura for `time` s).
//! - **aura:** damage around the body each moment for `time` s.
//! - **field:** a lingering zone where the aim lands (`damage` per second, `stun`, `time` s).
//! - **cone:** a blast in front (`radius` long, `damage`, `stun`, `push`; negative pulls).
//! - **heal:** restores `damage` health to every player within `radius`.
//! - **chain:** zaps up to `count` units in sight within `radius` (`damage` each).
//! - **vanish:** unseen by the Hive for `time` s, healing `damage`.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Profile = @import("Profile.zig");
const Enemies = @import("Enemies.zig");
const Combat = @import("Combat.zig");
const Heroes = @import("Heroes.zig");
const Ranger = @import("../character/Ranger.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Specials = @This();

pub const max_players = 4;
pub const max_energy: f32 = 100;
pub const max_grenades = 8;
pub const max_fields = 8;

pub const Kind = enum {
    // Ranger tech and Synthetic powers.
    arc_grenade,
    sentry,
    overshield,
    phase_dash,
    kinetic_slam,
    lumen_lance,
    // Wildkin, three per hero in roster order.
    spin_dash,
    quill_storm,
    homing_hop,
    fox_fire,
    mirage_step,
    tail_whirl,
    shell_guard,
    shell_spin,
    tidal_slam,
    moon_leap,
    thump_quake,
    bunny_barrage,
    gizmo_turret,
    smoke_bomb,
    trash_toss,
    super_hop,
    tongue_lash,
    splash_quake,
    hypno_gaze,
    venom_cloud,
    coil_strike,
    jaw_snap,
    death_roll,
    swamp_stomp,
    play_dead,
    junk_bomb,
    tail_trip,
    mighty_roar,
    pounce,
    pride_rally,
    trunk_blast,
    stampede,
    earthshaker,
    haymaker,
    pogo_bounce,
    pouch_shield,
    moon_howl,
    pack_dash,
    frost_bite,
    horn_charge,
    iron_hide,
    ground_crack,
    bamboo_whirl,
    belly_bounce,
    snack_break,
    ground_pound,
    boulder_toss,
    chest_drum,
    dive_bomb,
    gale_gust,
    sky_lift,
    talon_strike,
    feather_barrage,
    updraft,
    moon_lance,
    night_veil,
    wisdom_ward,
    sonic_screech,
    echo_pulse,
    night_glide,
    web_snare,
    web_swing,
    spiderling_swarm,
    scythe_flurry,
    mantis_leap,
    zen_guard,
    horn_toss,
    solar_flare,
    carapace,
    honey_heal,
    sting_swarm,
    buzz_dash,
    prism_dust,
    rainbow_beam,
    wing_gust,
    tail_sting,
    sandstorm,
    pincer_slam,
};
pub const kind_count = @typeInfo(Kind).@"enum".fields.len;

pub const Mechanic = enum { grenade, sentry, shield, blink, slam, lance, launch, aura, field, cone, heal, chain, vanish };

pub const Info = struct {
    label: []const u8,
    mechanic: Mechanic,
    cost: f32,
    cooldown: f32,
    damage: f32 = 0,
    radius: f32 = 0,
    stun: f32 = 0,
    push: f32 = 0,
    lift: f32 = 0,
    time: f32 = 0,
    count: u8 = 0,
    color: [3]f32 = .{ 0.85, 0.85, 1 },
};

pub fn info(kind: Kind) Info {
    return switch (kind) {
        .arc_grenade => .{ .label = "ARC GRENADE", .mechanic = .grenade, .cost = 30, .cooldown = 4, .damage = 60, .radius = 5, .stun = 2, .push = 3, .color = .{ 0.45, 0.8, 1 } },
        .sentry => .{ .label = "SENTRY", .mechanic = .sentry, .cost = 50, .cooldown = 15, .damage = 8, .time = 20, .color = .{ 0.4, 0.95, 1 } },
        .overshield => .{ .label = "OVERSHIELD", .mechanic = .shield, .cost = 40, .cooldown = 12, .damage = 80, .time = 8, .color = .{ 0.4, 0.85, 1 } },
        .phase_dash => .{ .label = "PHASE DASH", .mechanic = .blink, .cost = 25, .cooldown = 2.5, .damage = 45, .radius = 14, .stun = 1, .push = 4, .color = .{ 0.75, 0.9, 1 } },
        .kinetic_slam => .{ .label = "KINETIC SLAM", .mechanic = .slam, .cost = 40, .cooldown = 6, .damage = 70, .radius = 8, .stun = 1.5, .push = 14, .color = .{ 0.85, 0.75, 1 } },
        .lumen_lance => .{ .label = "LUMEN LANCE", .mechanic = .lance, .cost = 60, .cooldown = 10, .damage = 90, .time = 2.5, .color = .{ 0.95, 0.9, 1 } },

        .spin_dash => .{ .label = "SPIN DASH", .mechanic = .launch, .cost = 20, .cooldown = 2, .damage = 120, .radius = 2.2, .stun = 0.5, .push = 26, .lift = 2, .time = 0.8, .color = .{ 0.2, 0.5, 1 } },
        .quill_storm => .{ .label = "QUILL STORM", .mechanic = .slam, .cost = 35, .cooldown = 6, .damage = 45, .radius = 6, .stun = 0.8, .push = 6, .color = .{ 0.3, 0.6, 1 } },
        .homing_hop => .{ .label = "HOMING HOP", .mechanic = .launch, .cost = 20, .cooldown = 3, .damage = 70, .radius = 2, .stun = 0.6, .push = 10, .lift = 13, .time = 0.6, .color = .{ 0.4, 0.7, 1 } },
        .fox_fire => .{ .label = "FOX FIRE", .mechanic = .chain, .cost = 30, .cooldown = 4, .damage = 40, .radius = 28, .count = 3, .color = .{ 1, 0.55, 0.25 } },
        .mirage_step => .{ .label = "MIRAGE STEP", .mechanic = .vanish, .cost = 30, .cooldown = 10, .damage = 20, .time = 4, .color = .{ 1, 0.7, 0.9 } },
        .tail_whirl => .{ .label = "TAIL WHIRL", .mechanic = .slam, .cost = 25, .cooldown = 4, .damage = 35, .radius = 5, .stun = 1, .push = 10, .color = .{ 1, 0.6, 0.3 } },
        .shell_guard => .{ .label = "SHELL GUARD", .mechanic = .shield, .cost = 40, .cooldown = 12, .damage = 140, .time = 8, .color = .{ 0.4, 0.9, 0.5 } },
        .shell_spin => .{ .label = "SHELL SPIN", .mechanic = .launch, .cost = 30, .cooldown = 5, .damage = 90, .radius = 2.5, .stun = 0.6, .push = 12, .time = 2.5, .color = .{ 0.5, 0.9, 0.5 } },
        .tidal_slam => .{ .label = "TIDAL SLAM", .mechanic = .slam, .cost = 40, .cooldown = 7, .damage = 55, .radius = 9, .stun = 1.2, .push = 14, .color = .{ 0.3, 0.7, 1 } },
        .moon_leap => .{ .label = "MOON LEAP", .mechanic = .launch, .cost = 15, .cooldown = 2, .push = 6, .lift = 17, .color = .{ 0.9, 0.9, 1 } },
        .thump_quake => .{ .label = "THUMP QUAKE", .mechanic = .slam, .cost = 35, .cooldown = 5, .damage = 50, .radius = 7, .stun = 1.2, .push = 8, .color = .{ 0.9, 0.8, 0.6 } },
        .bunny_barrage => .{ .label = "BUNNY BARRAGE", .mechanic = .cone, .cost = 25, .cooldown = 3, .damage = 55, .radius = 7, .stun = 0.5, .push = 8, .color = .{ 1, 0.7, 0.8 } },
        .gizmo_turret => .{ .label = "GIZMO TURRET", .mechanic = .sentry, .cost = 45, .cooldown = 14, .damage = 9, .time = 20, .color = .{ 0.7, 0.9, 0.4 } },
        .smoke_bomb => .{ .label = "SMOKE BOMB", .mechanic = .field, .cost = 30, .cooldown = 8, .damage = 5, .radius = 6, .stun = 2.5, .time = 4, .color = .{ 0.6, 0.6, 0.65 } },
        .trash_toss => .{ .label = "TRASH TOSS", .mechanic = .grenade, .cost = 25, .cooldown = 4, .damage = 55, .radius = 5, .stun = 1.5, .push = 5, .color = .{ 0.75, 0.75, 0.4 } },
        .super_hop => .{ .label = "SUPER HOP", .mechanic = .launch, .cost = 15, .cooldown = 2, .push = 8, .lift = 18, .color = .{ 0.4, 1, 0.4 } },
        .tongue_lash => .{ .label = "TONGUE LASH", .mechanic = .cone, .cost = 25, .cooldown = 3, .damage = 45, .radius = 10, .stun = 0.8, .push = -10, .color = .{ 1, 0.4, 0.5 } },
        .splash_quake => .{ .label = "SPLASH QUAKE", .mechanic = .slam, .cost = 35, .cooldown = 6, .damage = 50, .radius = 8, .stun = 1, .push = 10, .color = .{ 0.4, 0.8, 1 } },
        .hypno_gaze => .{ .label = "HYPNO GAZE", .mechanic = .cone, .cost = 30, .cooldown = 7, .damage = 10, .radius = 12, .stun = 3.5, .color = .{ 0.8, 0.4, 1 } },
        .venom_cloud => .{ .label = "VENOM CLOUD", .mechanic = .field, .cost = 35, .cooldown = 8, .damage = 30, .radius = 5, .stun = 0.3, .time = 5, .color = .{ 0.5, 1, 0.3 } },
        .coil_strike => .{ .label = "COIL STRIKE", .mechanic = .blink, .cost = 25, .cooldown = 3, .damage = 55, .radius = 12, .stun = 1, .push = 6, .color = .{ 0.4, 0.9, 0.4 } },
        .jaw_snap => .{ .label = "JAW SNAP", .mechanic = .cone, .cost = 25, .cooldown = 3, .damage = 95, .radius = 5, .stun = 0.8, .push = 4, .color = .{ 0.9, 0.9, 0.7 } },
        .death_roll => .{ .label = "DEATH ROLL", .mechanic = .launch, .cost = 35, .cooldown = 6, .damage = 110, .radius = 2.6, .stun = 0.8, .push = 10, .time = 2, .color = .{ 0.4, 0.7, 0.3 } },
        .swamp_stomp => .{ .label = "SWAMP STOMP", .mechanic = .slam, .cost = 40, .cooldown = 7, .damage = 60, .radius = 8, .stun = 1.3, .push = 10, .color = .{ 0.5, 0.6, 0.3 } },
        .play_dead => .{ .label = "PLAY DEAD", .mechanic = .vanish, .cost = 30, .cooldown = 14, .damage = 40, .time = 5, .color = .{ 0.9, 0.85, 0.9 } },
        .junk_bomb => .{ .label = "JUNK BOMB", .mechanic = .grenade, .cost = 25, .cooldown = 4, .damage = 50, .radius = 5, .stun = 1.5, .push = 4, .color = .{ 0.8, 0.7, 0.5 } },
        .tail_trip => .{ .label = "TAIL TRIP", .mechanic = .cone, .cost = 20, .cooldown = 4, .damage = 15, .radius = 6, .stun = 2.5, .push = 3, .color = .{ 0.95, 0.75, 0.8 } },
        .mighty_roar => .{ .label = "MIGHTY ROAR", .mechanic = .cone, .cost = 35, .cooldown = 8, .damage = 20, .radius = 14, .stun = 2.5, .push = 16, .color = .{ 1, 0.8, 0.3 } },
        .pounce => .{ .label = "POUNCE", .mechanic = .blink, .cost = 25, .cooldown = 3, .damage = 70, .radius = 14, .stun = 1.2, .push = 6, .color = .{ 1, 0.75, 0.3 } },
        .pride_rally => .{ .label = "PRIDE RALLY", .mechanic = .heal, .cost = 45, .cooldown = 14, .damage = 50, .radius = 14, .color = .{ 1, 0.9, 0.4 } },
        .trunk_blast => .{ .label = "TRUNK BLAST", .mechanic = .cone, .cost = 30, .cooldown = 5, .damage = 40, .radius = 12, .stun = 1, .push = 22, .color = .{ 0.7, 0.8, 1 } },
        .stampede => .{ .label = "STAMPEDE", .mechanic = .launch, .cost = 35, .cooldown = 6, .damage = 100, .radius = 2.6, .stun = 1, .push = 20, .time = 1.2, .color = .{ 0.75, 0.7, 0.7 } },
        .earthshaker => .{ .label = "EARTHSHAKER", .mechanic = .slam, .cost = 45, .cooldown = 8, .damage = 70, .radius = 10, .stun = 1.5, .push = 10, .color = .{ 0.8, 0.7, 0.5 } },
        .haymaker => .{ .label = "HAYMAKER", .mechanic = .cone, .cost = 25, .cooldown = 3, .damage = 110, .radius = 4.5, .stun = 1, .push = 18, .color = .{ 1, 0.5, 0.3 } },
        .pogo_bounce => .{ .label = "POGO BOUNCE", .mechanic = .launch, .cost = 15, .cooldown = 2, .damage = 40, .radius = 2, .stun = 0.5, .push = 9, .lift = 16, .time = 0.5, .color = .{ 1, 0.7, 0.4 } },
        .pouch_shield => .{ .label = "POUCH SHIELD", .mechanic = .shield, .cost = 35, .cooldown = 12, .damage = 90, .time = 8, .color = .{ 1, 0.8, 0.5 } },
        .moon_howl => .{ .label = "MOON HOWL", .mechanic = .heal, .cost = 40, .cooldown = 12, .damage = 35, .radius = 16, .color = .{ 0.75, 0.85, 1 } },
        .pack_dash => .{ .label = "PACK DASH", .mechanic = .blink, .cost = 25, .cooldown = 3, .damage = 50, .radius = 16, .stun = 0.8, .push = 5, .color = .{ 0.7, 0.8, 1 } },
        .frost_bite => .{ .label = "FROST BITE", .mechanic = .cone, .cost = 25, .cooldown = 4, .damage = 70, .radius = 5, .stun = 2, .push = 3, .color = .{ 0.6, 0.9, 1 } },
        .horn_charge => .{ .label = "HORN CHARGE", .mechanic = .launch, .cost = 30, .cooldown = 5, .damage = 130, .radius = 2.4, .stun = 1.2, .push = 24, .time = 1, .color = .{ 0.85, 0.8, 0.7 } },
        .iron_hide => .{ .label = "IRON HIDE", .mechanic = .shield, .cost = 40, .cooldown = 12, .damage = 120, .time = 10, .color = .{ 0.7, 0.75, 0.8 } },
        .ground_crack => .{ .label = "GROUND CRACK", .mechanic = .slam, .cost = 40, .cooldown = 7, .damage = 65, .radius = 9, .stun = 1.4, .push = 8, .color = .{ 0.85, 0.65, 0.4 } },
        .bamboo_whirl => .{ .label = "BAMBOO WHIRL", .mechanic = .aura, .cost = 30, .cooldown = 6, .damage = 80, .radius = 3, .stun = 0.4, .time = 2.5, .color = .{ 0.5, 0.95, 0.4 } },
        .belly_bounce => .{ .label = "BELLY BOUNCE", .mechanic = .slam, .cost = 30, .cooldown = 5, .damage = 55, .radius = 7, .stun = 1, .push = 12, .color = .{ 0.95, 0.95, 0.9 } },
        .snack_break => .{ .label = "SNACK BREAK", .mechanic = .heal, .cost = 40, .cooldown = 12, .damage = 60, .radius = 10, .color = .{ 1, 0.85, 0.5 } },
        .ground_pound => .{ .label = "GROUND POUND", .mechanic = .slam, .cost = 40, .cooldown = 7, .damage = 80, .radius = 9, .stun = 1.5, .push = 12, .color = .{ 0.7, 0.6, 0.5 } },
        .boulder_toss => .{ .label = "BOULDER TOSS", .mechanic = .grenade, .cost = 35, .cooldown = 5, .damage = 90, .radius = 6, .stun = 1.5, .push = 8, .color = .{ 0.65, 0.6, 0.55 } },
        .chest_drum => .{ .label = "CHEST DRUM", .mechanic = .cone, .cost = 30, .cooldown = 8, .damage = 15, .radius = 12, .stun = 2, .push = 12, .color = .{ 0.9, 0.6, 0.3 } },
        .dive_bomb => .{ .label = "DIVE BOMB", .mechanic = .blink, .cost = 30, .cooldown = 4, .damage = 75, .radius = 18, .stun = 1.2, .push = 8, .color = .{ 1, 0.85, 0.4 } },
        .gale_gust => .{ .label = "GALE GUST", .mechanic = .cone, .cost = 30, .cooldown = 6, .damage = 20, .radius = 14, .stun = 1, .push = 20, .color = .{ 0.85, 0.95, 1 } },
        .sky_lift => .{ .label = "SKY LIFT", .mechanic = .launch, .cost = 15, .cooldown = 3, .push = 4, .lift = 20, .color = .{ 0.9, 0.95, 1 } },
        .talon_strike => .{ .label = "TALON STRIKE", .mechanic = .blink, .cost = 25, .cooldown = 3, .damage = 65, .radius = 14, .stun = 1, .push = 6, .color = .{ 1, 0.5, 0.35 } },
        .feather_barrage => .{ .label = "FEATHER BARRAGE", .mechanic = .chain, .cost = 35, .cooldown = 5, .damage = 30, .radius = 30, .count = 5, .color = .{ 1, 0.6, 0.4 } },
        .updraft => .{ .label = "UPDRAFT", .mechanic = .launch, .cost = 15, .cooldown = 3, .push = 4, .lift = 18, .color = .{ 0.95, 0.9, 1 } },
        .moon_lance => .{ .label = "MOON LANCE", .mechanic = .lance, .cost = 55, .cooldown = 10, .damage = 85, .time = 2.2, .color = .{ 0.75, 0.8, 1 } },
        .night_veil => .{ .label = "NIGHT VEIL", .mechanic = .vanish, .cost = 30, .cooldown = 12, .damage = 20, .time = 4, .color = .{ 0.4, 0.4, 0.7 } },
        .wisdom_ward => .{ .label = "WISDOM WARD", .mechanic = .heal, .cost = 40, .cooldown = 12, .damage = 45, .radius = 14, .color = .{ 0.8, 0.85, 1 } },
        .sonic_screech => .{ .label = "SONIC SCREECH", .mechanic = .cone, .cost = 30, .cooldown = 6, .damage = 25, .radius = 12, .stun = 3, .push = 6, .color = .{ 0.85, 0.5, 1 } },
        .echo_pulse => .{ .label = "ECHO PULSE", .mechanic = .chain, .cost = 30, .cooldown = 4, .damage = 35, .radius = 26, .count = 4, .color = .{ 0.75, 0.5, 1 } },
        .night_glide => .{ .label = "NIGHT GLIDE", .mechanic = .vanish, .cost = 25, .cooldown = 10, .damage = 15, .time = 3, .color = .{ 0.5, 0.35, 0.8 } },
        .web_snare => .{ .label = "WEB SNARE", .mechanic = .field, .cost = 30, .cooldown = 6, .damage = 4, .radius = 6, .stun = 3.5, .time = 4, .color = .{ 0.95, 0.95, 1 } },
        .web_swing => .{ .label = "WEB SWING", .mechanic = .blink, .cost = 15, .cooldown = 2, .damage = 10, .radius = 18, .stun = 0.4, .color = .{ 0.9, 0.9, 1 } },
        .spiderling_swarm => .{ .label = "SPIDERLING SWARM", .mechanic = .chain, .cost = 35, .cooldown = 6, .damage = 20, .radius = 24, .count = 6, .color = .{ 1, 0.4, 0.5 } },
        .scythe_flurry => .{ .label = "SCYTHE FLURRY", .mechanic = .aura, .cost = 30, .cooldown = 5, .damage = 140, .radius = 3, .stun = 0.3, .time = 1.5, .color = .{ 0.6, 1, 0.5 } },
        .mantis_leap => .{ .label = "MANTIS LEAP", .mechanic = .blink, .cost = 20, .cooldown = 3, .damage = 60, .radius = 12, .stun = 0.8, .push = 4, .color = .{ 0.6, 1, 0.5 } },
        .zen_guard => .{ .label = "ZEN GUARD", .mechanic = .shield, .cost = 35, .cooldown = 10, .damage = 100, .time = 6, .color = .{ 0.7, 1, 0.7 } },
        .horn_toss => .{ .label = "HORN TOSS", .mechanic = .cone, .cost = 25, .cooldown = 4, .damage = 70, .radius = 5, .stun = 1, .push = 20, .color = .{ 1, 0.8, 0.3 } },
        .solar_flare => .{ .label = "SOLAR FLARE", .mechanic = .lance, .cost = 55, .cooldown = 10, .damage = 100, .time = 2, .color = .{ 1, 0.85, 0.35 } },
        .carapace => .{ .label = "CARAPACE", .mechanic = .shield, .cost = 40, .cooldown = 12, .damage = 130, .time = 9, .color = .{ 1, 0.75, 0.3 } },
        .honey_heal => .{ .label = "HONEY HEAL", .mechanic = .heal, .cost = 35, .cooldown = 9, .damage = 50, .radius = 14, .color = .{ 1, 0.8, 0.2 } },
        .sting_swarm => .{ .label = "STING SWARM", .mechanic = .chain, .cost = 30, .cooldown = 4, .damage = 30, .radius = 26, .count = 5, .color = .{ 1, 0.85, 0.2 } },
        .buzz_dash => .{ .label = "BUZZ DASH", .mechanic = .blink, .cost = 20, .cooldown = 2.5, .damage = 40, .radius = 12, .stun = 0.6, .push = 4, .color = .{ 1, 0.9, 0.3 } },
        .prism_dust => .{ .label = "PRISM DUST", .mechanic = .field, .cost = 35, .cooldown = 8, .damage = 20, .radius = 6, .stun = 2.5, .time = 4, .color = .{ 1, 0.6, 1 } },
        .rainbow_beam => .{ .label = "RAINBOW BEAM", .mechanic = .lance, .cost = 55, .cooldown = 10, .damage = 80, .time = 2.5, .color = .{ 0.6, 1, 0.9 } },
        .wing_gust => .{ .label = "WING GUST", .mechanic = .cone, .cost = 25, .cooldown = 5, .damage = 15, .radius = 12, .stun = 0.8, .push = 18, .color = .{ 0.9, 0.8, 1 } },
        .tail_sting => .{ .label = "TAIL STING", .mechanic = .cone, .cost = 25, .cooldown = 3, .damage = 85, .radius = 6, .stun = 1.2, .push = 4, .color = .{ 0.9, 0.5, 1 } },
        .sandstorm => .{ .label = "SANDSTORM", .mechanic = .field, .cost = 35, .cooldown = 8, .damage = 35, .radius = 7, .stun = 0.2, .time = 5, .color = .{ 0.95, 0.8, 0.5 } },
        .pincer_slam => .{ .label = "PINCER SLAM", .mechanic = .slam, .cost = 30, .cooldown = 5, .damage = 60, .radius = 6, .stun = 1.2, .push = 8, .color = .{ 1, 0.6, 0.4 } },
    };
}

/// What a body brings to a fight: three powers and its passives.
pub const Loadout = struct {
    kit: [3]Kind,
    /// Energy per second, extra maximum health, saber damage factor, run-speed factor.
    regen: f32,
    health: f32,
    melee: f32,
    speed: f32 = 1,
};

pub fn loadout(profile: Profile) Loadout {
    if (profile.species != .human) if (Heroes.forSpecies(profile.species)) |i| {
        const h = Heroes.roster[i];
        return .{ .kit = h.powers, .regen = h.regen, .health = h.health, .melee = h.melee, .speed = h.speed };
    };
    return switch (profile.class) {
        .ranger => .{ .kit = .{ .arc_grenade, .sentry, .overshield }, .regen = 10, .health = 0, .melee = 1 },
        .synthetic => .{ .kit = .{ .phase_dash, .kinetic_slam, .lumen_lance }, .regen = 7, .health = 30, .melee = 1.25 },
    };
}

/// What a special needs from its player this step.
pub const Use = struct {
    eye: V,
    forward: V,
    feet: V,
    /// Press edges of special 1–3.
    pressed: [3]bool = @splat(false),
};

pub const Player = struct {
    energy: f32 = max_energy,
    cooldowns: [3]f32 = @splat(0),
    /// A channelled lance: time left and which power it is.
    lance: f32 = 0,
    lance_kind: Kind = .lumen_lance,
    /// A damaging aura around the body (spins, flurries): time left and which power.
    aura: f32 = 0,
    aura_kind: Kind = .bamboo_whirl,
    aura_tick: f32 = 0,
    /// Unseen by the Hive for this long.
    hidden: f32 = 0,
    /// The body's cast or throw pose, and how long it holds.
    pose: Ranger.Action = .none,
    pose_left: f32 = 0,
};

pub const Grenade = struct { owner: u8, kind: Kind = .arc_grenade, position: V, velocity: V, fuse: f32 };
pub const Sentry = struct { kind: Kind = .sentry, position: V, life: f32, cooldown: f32 = 0, aim: V = .{ 0, 0, 1 } };
/// A lingering zone (webs, smoke, venom, dust, sand).
pub const Field = struct { kind: Kind, position: V, left: f32, tick: f32 = 0 };

pub const Event = union(enum) {
    used: struct { player: u8, kind: Kind },
    /// Pressed without the energy, or still cooling down.
    denied: u8,
    burst: V,
    blink: struct { player: u8, to: V },
    /// Throw the player's body (leaps, dashes, charges).
    launch: struct { player: u8, velocity: V },
    /// Heal every player within `radius` of `center` by `amount` (radius 0: only `player`).
    heal: struct { player: u8, center: V, radius: f32, amount: f32 },
    zap: V,
    hive: Enemies.Event,
};

players: [max_players]Player = @splat(.{}),
grenades: [max_grenades]?Grenade = @splat(null),
sentries: [max_players]?Sentry = @splat(null),
fields: [max_fields]?Field = @splat(null),

fn push(out: []Event, n: *usize, e: Event) void {
    if (n.* < out.len) out[n.*] = e;
    n.* += 1;
}

fn relay(out: []Event, n: *usize, hive: []const Enemies.Event) void {
    for (hive) |e| push(out, n, .{ .hive = e });
}

fn flat(v: V) V {
    const h: V = .{ v[0], 0, v[2] };
    const l = R.length(h);
    return if (l > 0.05) R.scale(h, 1 / l) else .{ 0, 0, 1 };
}

/// The pose a special holds the body in, if any (it overrides the weapon's).
pub fn stance(self: *const Specials, p: usize) ?Combat.Stance {
    const s = self.players[p];
    if (s.lance > 0) return .{ .action = .cast };
    if (s.pose_left > 0) return .{ .action = s.pose, .t = 1 - s.pose_left / 0.35 };
    return null;
}

/// Unseen by the Hive (vanish powers).
pub fn hidden(self: *const Specials, p: usize) bool {
    return self.players[p].hidden > 0;
}

/// One fixed step of player `p`'s specials: energy, cooldowns, presses, channels and auras.
pub fn step(self: *Specials, p: u8, profile: Profile, physics: *const Physics, enemies: *Enemies, combat: *Combat, use: Use, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    const s = &self.players[p];
    const kit = loadout(profile);
    s.energy = @min(max_energy, s.energy + kit.regen * dt);
    for (&s.cooldowns) |*c| c.* = @max(0, c.* - dt);
    s.pose_left = @max(0, s.pose_left - dt);
    s.hidden = @max(0, s.hidden - dt);
    for (use.pressed, 0..) |pressed, i| if (pressed) {
        const kind = kit.kit[i];
        // A second press ends a lance early.
        if (info(kind).mechanic == .lance and s.lance > 0) {
            s.lance = 0;
            continue;
        }
        const about = info(kind);
        if (s.cooldowns[i] > 0 or s.energy < about.cost) {
            push(out, &n, .{ .denied = p });
            continue;
        }
        s.energy -= about.cost;
        s.cooldowns[i] = about.cooldown;
        push(out, &n, .{ .used = .{ .player = p, .kind = kind } });
        self.activate(p, kind, physics, enemies, combat, use, out, &n, &hive, &hn);
    };
    if (s.lance > 0) {
        const about = info(s.lance_kind);
        s.lance = @max(0, s.lance - dt);
        const reach = if (physics.castRay(use.eye, use.forward, 60, .none)) |hit| hit.distance else 60;
        _ = enemies.strikeCapsule(use.eye, use.forward, reach, 0.6, about.damage * dt, &hive, &hn);
        // From the hands, toward where the eyes aim.
        const from = if (combat.arsenals[p].grip) |g| g.base else R.add(use.eye, R.add(R.scale(use.forward, 0.9), .{ 0, -0.4, 0 }));
        const end = R.add(use.eye, R.scale(use.forward, reach));
        const span = R.sub(end, from);
        const length = @max(0.1, R.length(span));
        effect(combat, .{ .kind = .beam, .position = from, .dir = R.scale(span, 1 / length), .life = dt * 1.5, .size = 0.55, .length = length, .color = about.color });
    }
    if (s.aura > 0) {
        const about = info(s.aura_kind);
        s.aura = @max(0, s.aura - dt);
        s.aura_tick -= dt;
        const center = R.add(use.feet, .{ 0, 0.9, 0 });
        _ = enemies.strikeArea(center, about.radius, about.damage * dt, null, &hive, &hn);
        if (s.aura_tick <= 0) {
            s.aura_tick = 0.12;
            if (about.stun > 0) _ = enemies.shock(center, about.radius + 0.5, about.stun, 2);
            effect(combat, .{ .kind = .burst, .position = center, .life = 0.15, .size = about.radius * 0.8, .color = about.color });
        }
    }
    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

fn effectSlot(combat: *const Combat) usize {
    var oldest: usize = 0;
    for (combat.effects, 0..) |slot, i| {
        const e = slot orelse return i;
        if (e.age > combat.effects[oldest].?.age) oldest = i;
    }
    return oldest;
}

fn effect(combat: *Combat, e: Combat.Effect) void {
    combat.effects[effectSlot(combat)] = e;
}

fn pose(s: *Player, action: Ranger.Action, seconds: f32) void {
    s.pose = action;
    s.pose_left = seconds;
}

fn activate(self: *Specials, p: u8, kind: Kind, physics: *const Physics, enemies: *Enemies, combat: *Combat, use: Use, out: []Event, n: *usize, hive: []Enemies.Event, hn: *usize) void {
    const s = &self.players[p];
    const fwd = flat(use.forward);
    const about = info(kind);
    const chest = R.add(use.feet, .{ 0, 1.0, 0 });
    switch (about.mechanic) {
        .grenade => {
            pose(s, .throw, 0.35);
            const g: Grenade = .{ .owner = p, .kind = kind, .position = R.add(use.eye, R.add(R.scale(fwd, 0.6), .{ 0, -0.2, 0 })), .velocity = R.add(R.scale(use.forward, 16), .{ 0, 4, 0 }), .fuse = 1.2 };
            for (&self.grenades) |*slot| if (slot.* == null) {
                slot.* = g;
                break;
            };
        },
        .sentry => {
            pose(s, .throw, 0.35);
            var at = R.add(use.feet, R.scale(fwd, 1.6));
            if (physics.castRay(R.add(at, .{ 0, 1.5, 0 }), .{ 0, -1, 0 }, 6, .none)) |hit| at = hit.point;
            self.sentries[p] = .{ .kind = kind, .position = at, .life = about.time, .aim = fwd };
        },
        .shield => {
            combat.vitals[p].shield = about.damage;
            combat.vitals[p].shield_time = about.time;
            effect(combat, .{ .kind = .burst, .position = chest, .life = 0.5, .size = 2, .color = about.color });
        },
        .blink => {
            pose(s, .cast, 0.2);
            var reach = about.radius;
            if (physics.castRay(chest, fwd, reach + 0.6, .none)) |hit| reach = @max(0, hit.distance - 0.6);
            var units: u32 = 0;
            var nests: u16 = 0;
            _ = enemies.strikeBlade(chest, fwd, reach, 1.2, about.damage, R.add(R.scale(fwd, about.push), .{ 0, 2, 0 }), about.stun, &units, &nests, hive, hn);
            effect(combat, .{ .kind = .trail, .position = R.add(chest, R.scale(fwd, reach / 2)), .dir = fwd, .life = 0.3, .size = 0.5, .length = reach, .color = about.color });
            push(out, n, .{ .blink = .{ .player = p, .to = R.add(use.feet, R.scale(fwd, reach)) } });
        },
        .slam => {
            pose(s, .cast, 0.35);
            const center = R.add(use.feet, .{ 0, 0.8, 0 });
            _ = enemies.strikeArea(center, about.radius, about.damage, null, hive, hn);
            _ = enemies.shock(center, about.radius, about.stun, about.push);
            effect(combat, .{ .kind = .burst, .position = center, .life = 0.45, .size = about.radius, .color = about.color });
            push(out, n, .{ .burst = center });
        },
        .lance => {
            s.lance = about.time;
            s.lance_kind = kind;
        },
        .launch => {
            pose(s, .cast, 0.25);
            push(out, n, .{ .launch = .{ .player = p, .velocity = R.add(R.scale(fwd, about.push), .{ 0, about.lift, 0 }) } });
            if (about.damage > 0) {
                s.aura = about.time;
                s.aura_kind = kind;
                s.aura_tick = 0;
            }
            effect(combat, .{ .kind = .burst, .position = use.feet, .life = 0.3, .size = 2, .color = about.color });
        },
        .aura => {
            pose(s, .swing, 0.35);
            s.aura = about.time;
            s.aura_kind = kind;
            s.aura_tick = 0;
        },
        .field => {
            pose(s, .throw, 0.35);
            // On the first unit along the aim, else where the aim lands, else ahead; then down
            // onto the ground below.
            const reach = if (physics.castRay(use.eye, use.forward, 30, .none)) |hit| hit.distance else 14;
            const t = enemies.aimAt(use.eye, use.forward, reach, 1) orelse reach;
            var at = R.add(use.eye, R.scale(use.forward, t));
            if (physics.castRay(R.add(at, .{ 0, 2, 0 }), .{ 0, -1, 0 }, 40, .none)) |hit| at = hit.point;
            var oldest: usize = 0;
            for (&self.fields, 0..) |*slot, i| {
                if (slot.* == null) {
                    oldest = i;
                    break;
                }
                if (slot.*.?.left < self.fields[oldest].?.left) oldest = i;
            }
            self.fields[oldest] = .{ .kind = kind, .position = at, .left = about.time };
        },
        .cone => {
            pose(s, .cast, 0.3);
            _ = enemies.cone(chest, fwd, about.radius, 0.5, about.damage, about.stun, about.push, hive, hn);
            effect(combat, .{ .kind = .trail, .position = R.add(chest, R.scale(fwd, about.radius / 2)), .dir = fwd, .life = 0.25, .size = about.radius * 0.5, .length = about.radius, .color = about.color });
            push(out, n, .{ .burst = R.add(chest, R.scale(fwd, about.radius * 0.5)) });
        },
        .heal => {
            pose(s, .cast, 0.35);
            push(out, n, .{ .heal = .{ .player = p, .center = use.feet, .radius = about.radius, .amount = about.damage } });
            effect(combat, .{ .kind = .burst, .position = chest, .life = 0.6, .size = about.radius * 0.5, .color = about.color });
        },
        .chain => {
            pose(s, .cast, 0.3);
            var done: u32 = 0;
            for (0..about.count) |_| {
                const target = enemies.nearestUnitExcept(chest, about.radius, done) orelse break;
                done |= @as(u32, 1) << @intCast(target.index);
                const to = R.sub(target.position, chest);
                const dist = R.length(to);
                if (dist < 0.1) continue;
                const dir = R.scale(to, 1 / dist);
                if (physics.castRay(chest, dir, dist, .none)) |hit| if (hit.distance < dist - 1.5) continue;
                var skip: u32 = ~(@as(u32, 1) << @intCast(target.index));
                _ = enemies.strikeThrough(chest, dir, dist + 1, 0.3, about.damage, 1, &skip, hive, hn);
                effect(combat, .{ .kind = .beam, .position = chest, .dir = dir, .life = 0.18, .size = 0.3, .length = dist, .color = about.color });
            }
        },
        .vanish => {
            pose(s, .cast, 0.35);
            s.hidden = about.time;
            push(out, n, .{ .heal = .{ .player = p, .center = use.feet, .radius = 0, .amount = about.damage } });
            effect(combat, .{ .kind = .burst, .position = chest, .life = 0.6, .size = 2.5, .color = about.color });
        },
    }
}

/// Grenades, sentries and fields: once per fixed step, after the players.
pub fn stepWorld(self: *Specials, physics: *const Physics, enemies: *Enemies, combat: *Combat, dt: f32, out: []Event) usize {
    var n: usize = 0;
    var hive: [16]Enemies.Event = undefined;
    var hn: usize = 0;
    for (&self.grenades) |*slot| if (slot.*) |*g| {
        g.fuse -= dt;
        g.velocity[1] -= 9.81 * dt;
        const travel = R.scale(g.velocity, dt);
        const length = R.length(travel);
        var burst = g.fuse <= 0 or enemies.nearestUnit(g.position, 1.6) != null;
        if (!burst and length > 1e-4) {
            if (physics.castRay(g.position, R.scale(travel, 1 / length), length, .none)) |hit| {
                g.position = hit.point;
                burst = true;
            } else g.position = R.add(g.position, travel);
        }
        if (burst) {
            const about = info(g.kind);
            _ = enemies.strikeArea(g.position, about.radius, about.damage, null, &hive, &hn);
            _ = enemies.shock(g.position, about.radius, about.stun, about.push);
            effect(combat, .{ .kind = .burst, .position = g.position, .life = 0.4, .size = about.radius, .color = about.color });
            push(out, &n, .{ .burst = g.position });
            slot.* = null;
        }
    };
    for (&self.sentries) |*slot| if (slot.*) |*t| {
        t.life -= dt;
        if (t.life <= 0) {
            slot.* = null;
            continue;
        }
        t.cooldown = @max(0, t.cooldown - dt);
        if (t.cooldown > 0) continue;
        const muzzle = R.add(t.position, .{ 0, 1.1, 0 });
        const target = enemies.nearestUnit(muzzle, 40) orelse continue;
        const to = R.sub(target, muzzle);
        const dist = R.length(to);
        if (dist < 0.1) continue;
        const dir = R.scale(to, 1 / dist);
        // Only what the turret can see.
        if (physics.castRay(muzzle, dir, dist, .none)) |hit| if (hit.distance < dist - 1.5) continue;
        t.aim = dir;
        t.cooldown = 0.25;
        const about = info(t.kind);
        _ = enemies.strikeAlong(muzzle, dir, dist + 1, 0.1, about.damage, &hive, &hn);
        effect(combat, .{ .kind = .beam, .position = muzzle, .dir = dir, .life = 0.08, .size = 0.25, .length = dist, .color = about.color });
        push(out, &n, .{ .zap = muzzle });
    };
    for (&self.fields) |*slot| if (slot.*) |*f| {
        const about = info(f.kind);
        f.left -= dt;
        if (f.left <= 0) {
            slot.* = null;
            continue;
        }
        const center = R.add(f.position, .{ 0, 1, 0 });
        _ = enemies.strikeArea(center, about.radius, about.damage * dt, null, &hive, &hn);
        f.tick -= dt;
        if (f.tick <= 0) {
            f.tick = 0.5;
            if (about.stun > 0) _ = enemies.shock(center, about.radius, about.stun, 0);
            effect(combat, .{ .kind = .burst, .position = center, .life = 0.5, .size = about.radius, .color = about.color });
        }
    };
    relay(out, &n, hive[0..@min(hn, hive.len)]);
    return n;
}

fn testPhysics() Physics {
    return Physics.init(.{ .sample = struct {
        fn f(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
            return .{ .height = 0, .normal = .{ 0, 1, 0 } };
        }
    }.f });
}

test "each class has its own specials, paid in energy and gated by cooldowns" {
    var physics = testPhysics();
    defer physics.deinit();
    var enemies: Enemies = .{};
    var combat: Combat = .{};
    var specials: Specials = .{};
    var events: [32]Event = undefined;
    const dt = 1.0 / 60.0;
    const use: Use = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 } };
    const ranger: Profile = .{ .class = .ranger };
    const synthetic: Profile = .{ .class = .synthetic };

    // Ranger: the overshield soaks a hit before health.
    var press = use;
    press.pressed = .{ false, false, true };
    _ = specials.step(0, ranger, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(specials.players[0].energy < 61);
    var hurt: [4]Combat.Event = undefined;
    var hn: usize = 0;
    _ = combat.hurt(0, 50, &hurt, &hn);
    try std.testing.expectEqual(@as(f32, 100), combat.vitals[0].health);
    try std.testing.expectEqual(@as(f32, 30), combat.vitals[0].shield);
    // Pressed again while cooling down: refused, no energy spent.
    const before = specials.players[0].energy;
    const count = specials.step(0, ranger, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(count >= 1 and events[0] == .denied);
    try std.testing.expect(specials.players[0].energy > before);

    // An arc grenade thrown at a trooper bursts on it and stuns it.
    enemies.units[0] = .{ .kind = .trooper, .nest = 0, .position = .{ 0, 0, 7 }, .health = 500, .orbit = 0 };
    press.pressed = .{ true, false, false };
    _ = specials.step(1, ranger, &physics, &enemies, &combat, press, dt, &events);
    var bursts: usize = 0;
    for (0..90) |_| {
        const k = specials.stepWorld(&physics, &enemies, &combat, dt, &events);
        for (events[0..@min(k, events.len)]) |e| bursts += @intFromBool(e == .burst);
    }
    try std.testing.expectEqual(@as(usize, 1), bursts);
    try std.testing.expect(enemies.units[0].?.health < 500 and enemies.units[0].?.stun > 1);

    // A sentry zaps the unit in sight.
    press.pressed = .{ false, true, false };
    _ = specials.step(2, ranger, &physics, &enemies, &combat, press, dt, &events);
    const health = enemies.units[0].?.health;
    for (0..30) |_| _ = specials.stepWorld(&physics, &enemies, &combat, dt, &events);
    try std.testing.expect(enemies.units[0].?.health < health);

    // Synthetic: the phase dash blinks ahead through the trooper and stuns it.
    enemies.units[0].?.stun = 0;
    press.pressed = .{ true, false, false };
    const k = specials.step(3, synthetic, &physics, &enemies, &combat, press, dt, &events);
    var blinked = false;
    for (events[0..@min(k, events.len)]) |e| if (e == .blink) {
        blinked = e.blink.to[2] > 13;
    };
    try std.testing.expect(blinked and enemies.units[0].?.stun > 0);
    // Kinetic slam throws everything nearby away.
    specials.players[3].energy = max_energy;
    enemies.units[1] = .{ .kind = .drone, .nest = 0, .position = .{ 3, 1, 0 }, .health = 500, .orbit = 0 };
    press.pressed = .{ false, true, false };
    _ = specials.step(3, synthetic, &physics, &enemies, &combat, press, dt, &events);
    try std.testing.expect(enemies.units[1].?.velocity[0] > 3 and enemies.units[1].?.health < 500);
    // The lumen lance channels a beam; the body holds the cast pose meanwhile.
    press.pressed = .{ false, false, true };
    specials.players[3].energy = max_energy;
    const lance_health = enemies.units[0].?.health;
    _ = specials.step(3, synthetic, &physics, &enemies, &combat, press, dt, &events);
    for (0..60) |_| _ = specials.step(3, synthetic, &physics, &enemies, &combat, use, dt, &events);
    try std.testing.expect(enemies.units[0].?.health < lance_health - 80);
    try std.testing.expectEqual(Ranger.Action.cast, specials.stance(3).?.action);
    try std.testing.expectEqual(@as(f32, 1.25), loadout(synthetic).melee);
}

test "every Wildkin power is affordable, distinct, and does what its mechanic says" {
    // Every power can be paid from a full bar and has the numbers its mechanic needs.
    for (0..kind_count) |k| {
        const about = info(@enumFromInt(k));
        try std.testing.expect(about.cost > 0 and about.cost <= max_energy and about.cooldown > 0);
        switch (about.mechanic) {
            .grenade, .slam, .cone => try std.testing.expect(about.radius > 0 and (about.damage > 0 or about.stun > 0)),
            .blink, .chain, .heal => try std.testing.expect(about.radius > 0),
            .shield => try std.testing.expect(about.damage > 0 and about.time > 0),
            .lance, .aura, .field, .sentry, .vanish => try std.testing.expect(about.time > 0),
            .launch => try std.testing.expect(about.push > 0 or about.lift > 0),
        }
    }
    var physics = testPhysics();
    defer physics.deinit();
    var combat: Combat = .{};
    var events: [32]Event = undefined;
    const dt = 1.0 / 60.0;
    const use: Use = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 }, .pressed = .{ true, false, false } };
    const idle: Use = .{ .eye = .{ 0, 1.6, 0 }, .forward = .{ 0, 0, 1 }, .feet = .{ 0, 0, 0 } };
    // Each hero's three powers, on a squad in front: every one hurts, stuns, moves, heals or hides.
    for (Heroes.roster, 0..) |hero, hi| for (0..3) |slot| {
        var specials: Specials = .{};
        var enemies: Enemies = .{};
        for (0..3) |u| enemies.units[u] = .{ .kind = .trooper, .nest = 0, .position = .{ (@as(f32, @floatFromInt(u)) - 1) * 1.5, 0, 4 }, .health = 1000, .orbit = 0 };
        var press = use;
        press.pressed = @splat(false);
        press.pressed[slot] = true;
        const kind = hero.powers[slot];
        var effects = false;
        var count = specials.step(0, Heroes.profile(@intCast(hi)), &physics, &enemies, &combat, press, dt, &events);
        for (events[0..@min(count, events.len)]) |e| effects = effects or e == .launch or e == .heal or e == .blink;
        for (0..240) |_| {
            count = specials.step(0, Heroes.profile(@intCast(hi)), &physics, &enemies, &combat, idle, dt, &events);
            for (events[0..@min(count, events.len)]) |e| effects = effects or e == .launch or e == .heal;
            _ = specials.stepWorld(&physics, &enemies, &combat, dt, &events);
        }
        for (enemies.units) |u| if (u) |unit| {
            effects = effects or unit.health < 1000 or unit.stun > 0;
        } else {
            effects = true;
        };
        effects = effects or specials.hidden(0) or combat.vitals[0].shield > 0;
        if (!effects) std.debug.print("{s}: {s} had no effect\n", .{ hero.name, @tagName(kind) });
        try std.testing.expect(effects);
        combat = .{};
    };
}
