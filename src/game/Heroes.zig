//! The Wildkin: the heroes players meet, collect and play as.
//!
//! Long ago the Scalari carried Earth's animals off to their labs aboard the Worldcoil Ark and
//! tried to remake them into soldiers. The experiments failed in the best way. The animals
//! woke up clever, upright and super-powered, but with their own big hearts instead of orders,
//! and when the Ark broke apart over the Frontier they scattered across it. Each Wildkin is one
//! of those escapees: a hedgehog who outruns sound, a gator who rolls like a boulder, a spider
//! who weaves light. Find them in the city, the wilds, the mountain caves and the arena, and
//! they join your roster. Any unlocked hero can be played (P1 picks from the Heroes menu, and a
//! hero's form becomes available in the creator).
//!
//! Every hero has three powers (`Specials`, keyed Z / C / H), a passive (health, saber weight,
//! energy regeneration, run speed), and flight if they have wings.
const std = @import("std");
const Profile = @import("Profile.zig");
const Specials = @import("Specials.zig");
const Beasts = @import("../character/Beasts.zig");

pub const Role = enum { speedster, trickster, jumper, gadgeteer, tank, hypnotist, bruiser, leader, boxer, hunter, charger, brawler, smasher, flyer, mage, trapper, blademaster, healer };
/// Where a hero waits to be met. Starters have already joined.
pub const Home = enum { starter, city, wilds, cave, arena };

pub const Hero = struct {
    name: []const u8,
    species: Profile.Species,
    title: []const u8,
    role: Role,
    /// One line for the roster card.
    blurb: []const u8,
    coat: u8,
    marking: u8,
    accent: u8,
    outfit: u8,
    clothing: Profile.Clothing = .undersuit,
    presentation: Profile.Presentation = .masculine,
    powers: [3]Specials.Kind,
    /// Extra maximum health, saber damage factor, energy per second, run-speed factor.
    health: f32 = 0,
    melee: f32 = 1,
    regen: f32 = 8,
    speed: f32 = 1,
    home: Home,
};

pub const roster = [_]Hero{
    .{ .name = "BOLT QUILL", .species = .hedgehog, .title = "The Blue Blur", .role = .speedster, .blurb = "Runs so fast the wind needs a nap. Spins into a ball and bowls through bots.", .coat = 0, .marking = 8, .accent = 1, .outfit = 3, .powers = .{ .spin_dash, .quill_storm, .homing_hop }, .speed = 1.35, .regen = 10, .home = .starter },
    .{ .name = "JINX KITSU", .species = .fox, .title = "Foxfire Trickster", .role = .trickster, .blurb = "Throws dancing foxfire and vanishes in a puff of mirage.", .coat = 1, .marking = 2, .accent = 2, .outfit = 7, .presentation = .feminine, .powers = .{ .fox_fire, .mirage_step, .tail_whirl }, .speed = 1.15, .regen = 10, .home = .starter },
    .{ .name = "CAPTAIN SHELLSHOCK", .species = .turtle, .title = "The Living Fortress", .role = .tank, .blurb = "Slow to start, impossible to stop. His shell is his shield and his bowling ball.", .coat = 4, .marking = 11, .accent = 0, .outfit = 2, .powers = .{ .shell_guard, .shell_spin, .tidal_slam }, .health = 60, .speed = 0.92, .home = .starter },
    .{ .name = "HOPPER VEX", .species = .rabbit, .title = "Moon Jumper", .role = .jumper, .blurb = "Bounces higher than the canopy and lands like thunder.", .coat = 2, .marking = 12, .accent = 2, .outfit = 0, .presentation = .feminine, .powers = .{ .moon_leap, .thump_quake, .bunny_barrage }, .speed = 1.2, .home = .city },
    .{ .name = "ROOK BANDIT", .species = .raccoon, .title = "Gadget Thief", .role = .gadgeteer, .blurb = "Builds turrets from junk and disappears in smoke before anyone notices.", .coat = 3, .marking = 10, .accent = 3, .outfit = 5, .powers = .{ .gizmo_turret, .smoke_bomb, .trash_toss }, .regen = 11, .home = .city },
    .{ .name = "RIBBIT REX", .species = .frog, .title = "Pond Thunder", .role = .jumper, .blurb = "A tongue like a whip and a hop like a cannon.", .coat = 5, .marking = 14, .accent = 3, .outfit = 1, .powers = .{ .super_hop, .tongue_lash, .splash_quake }, .speed = 1.1, .home = .wilds },
    .{ .name = "COIL", .species = .snake, .title = "The Hypnotist", .role = .hypnotist, .blurb = "One look into her spinning eyes and bots forget what they were doing.", .coat = 6, .marking = 14, .accent = 3, .outfit = 5, .presentation = .feminine, .powers = .{ .hypno_gaze, .venom_cloud, .coil_strike }, .home = .cave },
    .{ .name = "GUS CHOMPA", .species = .alligator, .title = "Swamp Tank", .role = .bruiser, .blurb = "Big grin, bigger bite. Rolls like a log and stomps like a quake.", .coat = 6, .marking = 8, .accent = 1, .outfit = 1, .powers = .{ .jaw_snap, .death_roll, .swamp_stomp }, .health = 50, .melee = 1.2, .home = .wilds },
    .{ .name = "PIP", .species = .possum, .title = "Never Really Gone", .role = .trickster, .blurb = "Plays dead, gets back up, and throws the bots' own junk at them.", .coat = 7, .marking = 2, .accent = 2, .outfit = 7, .powers = .{ .play_dead, .junk_bomb, .tail_trip }, .regen = 11, .home = .city },
    .{ .name = "KING RORY", .species = .lion, .title = "Heart of the Pride", .role = .leader, .blurb = "His roar shakes the Hive, and his rally gets the whole team back up.", .coat = 8, .marking = 11, .accent = 1, .outfit = 3, .clothing = .exo_rig, .powers = .{ .mighty_roar, .pounce, .pride_rally }, .health = 30, .melee = 1.2, .home = .cave },
    .{ .name = "ELLIE TRUNKWELL", .species = .elephant, .title = "The Stampede", .role = .tank, .blurb = "Never forgets a face and never loses a shoving match.", .coat = 9, .marking = 2, .accent = 0, .outfit = 6, .presentation = .feminine, .powers = .{ .trunk_blast, .stampede, .earthshaker }, .health = 80, .speed = 0.9, .home = .wilds },
    .{ .name = "BOOMER JO", .species = .kangaroo, .title = "Outback Boxer", .role = .boxer, .blurb = "Pogo-bounces into the fight and lands a haymaker on the way down.", .coat = 11, .marking = 8, .accent = 1, .outfit = 3, .presentation = .feminine, .powers = .{ .haymaker, .pogo_bounce, .pouch_shield }, .melee = 1.3, .speed = 1.15, .home = .arena },
    .{ .name = "LUNA HOWL", .species = .wolf, .title = "Moon Hunter", .role = .hunter, .blurb = "Leads the pack dash and heals friends with a moonlit howl.", .coat = 7, .marking = 2, .accent = 0, .outfit = 2, .presentation = .feminine, .powers = .{ .moon_howl, .pack_dash, .frost_bite }, .speed = 1.2, .melee = 1.15, .home = .cave },
    .{ .name = "RAMTANK", .species = .rhino, .title = "Unstoppable Horn", .role = .charger, .blurb = "Points his horn at a problem and charges until it is not a problem.", .coat = 9, .marking = 3, .accent = 1, .outfit = 5, .clothing = .hardsuit, .powers = .{ .horn_charge, .iron_hide, .ground_crack }, .health = 70, .melee = 1.25, .home = .arena },
    .{ .name = "BAO BAMBOO", .species = .panda, .title = "Kung-Fu Snack Master", .role = .brawler, .blurb = "Spins a bamboo staff, bounces on her belly, and always shares her snacks.", .coat = 2, .marking = 10, .accent = 3, .outfit = 0, .presentation = .feminine, .powers = .{ .bamboo_whirl, .belly_bounce, .snack_break }, .health = 40, .home = .city },
    .{ .name = "KONG KOBALT", .species = .gorilla, .title = "Mountain Fist", .role = .smasher, .blurb = "Pounds the ground, tosses boulders, and drums his chest so loud bots freeze.", .coat = 10, .marking = 9, .accent = 0, .outfit = 2, .clothing = .exo_rig, .powers = .{ .ground_pound, .boulder_toss, .chest_drum }, .health = 60, .melee = 1.3, .home = .cave },
    .{ .name = "SKYE TALON", .species = .eagle, .title = "Lord of the Updraft", .role = .flyer, .blurb = "Dives out of the sun and blows whole squads away with one wingbeat.", .coat = 11, .marking = 2, .accent = 1, .outfit = 2, .powers = .{ .dive_bomb, .gale_gust, .sky_lift }, .speed = 1.1, .home = .wilds },
    .{ .name = "BLITZ", .species = .hawk, .title = "Red Streak", .role = .flyer, .blurb = "The fastest wings on the Frontier, and a sky full of feathers.", .coat = 12, .marking = 8, .accent = 1, .outfit = 5, .presentation = .feminine, .powers = .{ .talon_strike, .feather_barrage, .updraft }, .speed = 1.2, .home = .arena },
    .{ .name = "SAGE HOOT", .species = .owl, .title = "Night Scholar", .role = .mage, .blurb = "Reads the stars, casts moonlight lances, and wards the team with wisdom.", .coat = 11, .marking = 8, .accent = 4, .outfit = 7, .powers = .{ .moon_lance, .night_veil, .wisdom_ward }, .regen = 12, .home = .cave },
    .{ .name = "ECHO VESPER", .species = .bat, .title = "Sound of the Night", .role = .flyer, .blurb = "Hears a bot think from a mile away and answers with a sonic screech.", .coat = 13, .marking = 10, .accent = 2, .outfit = 5, .presentation = .feminine, .powers = .{ .sonic_screech, .echo_pulse, .night_glide }, .regen = 10, .home = .cave },
    .{ .name = "SILK WEBSTER", .species = .spider, .title = "The Loom", .role = .trapper, .blurb = "Eight legs, eight plans. Webs that glow, snare and swing.", .coat = 10, .marking = 12, .accent = 2, .outfit = 3, .powers = .{ .web_snare, .web_swing, .spiderling_swarm }, .speed = 1.1, .home = .cave },
    .{ .name = "KAI MANTIS", .species = .mantis, .title = "Calm Blade", .role = .blademaster, .blurb = "Still as a leaf, then a whirlwind of scythes.", .coat = 5, .marking = 15, .accent = 3, .outfit = 0, .powers = .{ .scythe_flurry, .mantis_leap, .zen_guard }, .melee = 1.4, .home = .wilds },
    .{ .name = "SCARAB SOL", .species = .beetle, .title = "Sun Shell", .role = .tank, .blurb = "Catches sunlight in her shell and fires it right back.", .coat = 15, .marking = 14, .accent = 1, .outfit = 6, .presentation = .feminine, .powers = .{ .horn_toss, .solar_flare, .carapace }, .health = 50, .home = .arena },
    .{ .name = "BUZZ HONEYJET", .species = .bee, .title = "Sweet Sting", .role = .healer, .blurb = "Keeps the team buzzing with honey and the bots busy with stingers.", .coat = 14, .marking = 10, .accent = 1, .outfit = 5, .powers = .{ .honey_heal, .sting_swarm, .buzz_dash }, .regen = 12, .speed = 1.1, .home = .city },
    .{ .name = "FLUTTER PRISM", .species = .butterfly, .title = "Rainbow Wing", .role = .mage, .blurb = "Every flap scatters prism dust; every glance can be a rainbow beam.", .coat = 13, .marking = 15, .accent = 2, .outfit = 7, .presentation = .feminine, .powers = .{ .prism_dust, .rainbow_beam, .wing_gust }, .regen = 12, .home = .wilds },
    .{ .name = "PINCH", .species = .scorpion, .title = "Desert Guard", .role = .bruiser, .blurb = "Two pincers, one stinger, zero patience for bullies.", .coat = 1, .marking = 10, .accent = 3, .outfit = 1, .powers = .{ .tail_sting, .sandstorm, .pincer_slam }, .health = 40, .melee = 1.2, .home = .arena },
};
pub const count = roster.len;

/// The hero whose form this is.
pub fn forSpecies(species: Profile.Species) ?u8 {
    for (roster, 0..) |h, i| if (h.species == species) return @intCast(i);
    return null;
}

/// A hero's playable profile (their look; the player's own name is kept by the caller if wanted).
pub fn profile(index: u8) Profile {
    const h = roster[index];
    var p: Profile = .{
        .species = h.species,
        .coat = h.coat,
        .marking = h.marking,
        .accent = h.accent,
        .outfit = h.outfit,
        .clothing = h.clothing,
        .armor = .none,
        .helmet = .open,
        .presentation = h.presentation,
    };
    p.setName(h.name) catch unreachable;
    return p;
}

/// Heroes that have joined from the start.
pub fn starters() u32 {
    var bits: u32 = 0;
    for (roster, 0..) |h, i| if (h.home == .starter) {
        bits |= @as(u32, 1) << @intCast(i);
    };
    return bits;
}

/// Creator forms unlocked by a roster: human, plus each joined hero's species.
pub fn forms(unlocked: u32) u32 {
    var bits: u32 = 1;
    for (roster, 0..) |h, i| if (unlocked & (@as(u32, 1) << @intCast(i)) != 0) {
        bits |= @as(u32, 1) << @intCast(@intFromEnum(h.species));
    };
    return bits;
}

pub fn winged(index: u8) bool {
    return Beasts.winged(roster[index].species);
}

test "every Wildkin form has exactly one hero, valid colours, distinct powers and a home" {
    try std.testing.expect(count <= 32);
    for (1..Profile.species_count) |s| {
        var found: usize = 0;
        for (roster) |h| found += @intFromBool(@intFromEnum(h.species) == s);
        try std.testing.expectEqual(@as(usize, 1), found);
    }
    var names: [count][]const u8 = undefined;
    for (roster, 0..) |h, i| {
        try std.testing.expect(h.coat < Profile.coat_colors.len and h.marking < Profile.coat_colors.len);
        try std.testing.expect(h.accent < Profile.accent_colors.len and h.outfit < Profile.outfit_colors.len);
        try std.testing.expect(h.powers[0] != h.powers[1] and h.powers[1] != h.powers[2] and h.powers[0] != h.powers[2]);
        // Names fit a profile name and are unique.
        var p: Profile = .{};
        try p.setName(h.name);
        for (names[0..i]) |other| try std.testing.expect(!std.mem.eql(u8, other, h.name));
        names[i] = h.name;
        const back = profile(@intCast(i));
        try std.testing.expectEqual(h.species, back.species);
    }
    // Every hero's powers belong to that hero alone.
    for (roster, 0..) |a, i| for (roster[i + 1 ..]) |b| for (a.powers) |pa| for (b.powers) |pb| try std.testing.expect(pa != pb);
    try std.testing.expect(starters() != 0 and @popCount(starters()) == 3);
    const f = forms(starters());
    try std.testing.expect(f & 1 != 0 and f & (@as(u32, 1) << @intFromEnum(Profile.Species.hedgehog)) != 0);
}
