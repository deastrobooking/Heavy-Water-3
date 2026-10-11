//! Built-in data-driven hairstyles. Fewer, fatter, strongly directional clumps than the
//! procedural styles in `hair.zig`; the scalp cap hides the head between them. Mods add styles
//! the same way: a `hair_style.StyleDef` and `HairSpec.custom`.

const std = @import("std");
const spec = @import("spec.zig");
const hs = @import("hair_style.zig");

const C = hs.ClumpDef;
const pi: f32 = std.math.pi;

/// Cropped layered tufts: the default short cut. Short, fat, pointed, never a smooth cap.
const short_spiky = [_]C{
    .{ .az = 0, .el = 1.3, .pitch = 1.1, .length = 0.38, .width = 0.30, .flick = -0.2, .layer = 1 },
    .{ .az = 0.7, .el = 1.15, .yaw = 0.8, .pitch = 0.8, .length = 0.40, .width = 0.30, .layer = 1, .mirror = true },
    .{ .az = 1.5, .el = 1.0, .yaw = 1.6, .pitch = 0.4, .length = 0.40, .width = 0.30, .mirror = true },
    .{ .az = 2.3, .el = 0.9, .yaw = 2.4, .pitch = 0.3, .length = 0.42, .width = 0.30, .mirror = true },
    .{ .az = pi, .el = 0.95, .yaw = pi, .pitch = 0.35, .length = 0.45, .width = 0.32 },
    .{ .az = 2.6, .el = 0.2, .yaw = 2.7, .pitch = -0.3, .length = 0.35, .width = 0.26, .mirror = true },
    .{ .az = pi, .el = 0.1, .yaw = pi, .pitch = -0.3, .length = 0.35, .width = 0.28 },
    .{ .az = 0, .el = 0.8, .pitch = -0.95, .length = 0.38, .width = 0.22, .stand = 0.3 },
    .{ .az = 0.45, .el = 0.72, .yaw = 0.7, .pitch = -0.8, .length = 0.40, .width = 0.20, .stand = 0.3, .mirror = true },
    .{ .az = 0.95, .el = 0.55, .yaw = 1.1, .pitch = -0.6, .length = 0.35, .width = 0.20, .stand = 0.3, .mirror = true },
    .{ .az = 1.45, .el = 0.2, .yaw = 1.6, .pitch = -0.9, .length = 0.30, .width = 0.22, .stand = 0.3, .mirror = true },
};

/// A ridge of tall blades along the midline over shaved sides.
const mohawk = [_]C{
    .{ .az = 0, .el = 0.95, .pitch = 0.95, .length = 0.55, .width = 0.20, .layer = 1 },
    .{ .az = 0, .el = 1.3, .pitch = 1.2, .length = 0.8, .width = 0.22, .layer = 1, .flick = -0.2 },
    .{ .az = pi, .el = 1.3, .yaw = pi, .pitch = 1.1, .length = 0.85, .width = 0.22, .layer = 1, .flick = 0.25 },
    .{ .az = pi, .el = 1.0, .yaw = pi, .pitch = 0.75, .length = 0.8, .width = 0.22, .layer = 1, .flick = 0.35 },
    .{ .az = pi, .el = 0.65, .yaw = pi, .pitch = 0.45, .length = 0.75, .width = 0.22, .flick = 0.4 },
    .{ .az = pi, .el = 0.3, .yaw = pi, .pitch = 0.1, .length = 0.7, .width = 0.22, .flick = 0.4 },
};

/// Goku: a crown of fat spikes fanned up and out, three bangs falling over the forehead.
const spiky_hero = [_]C{
    .{ .az = 0, .el = 1.3, .pitch = 1.3, .length = 0.85, .width = 0.34, .taper = 1.1, .flick = -0.2, .layer = 1 },
    .{ .az = 0.45, .el = 1.1, .yaw = 0.55, .pitch = 1.0, .length = 0.82, .width = 0.32, .taper = 1.1, .flick = 0.25, .layer = 1, .mirror = true },
    .{ .az = 1.0, .el = 0.95, .yaw = 1.2, .pitch = 0.7, .length = 0.78, .width = 0.30, .taper = 1.1, .flick = 0.3, .mirror = true },
    .{ .az = 1.75, .el = 0.9, .yaw = 2.0, .pitch = 0.5, .length = 0.80, .width = 0.30, .taper = 1.1, .flick = 0.3, .mirror = true },
    .{ .az = pi, .el = 1.0, .yaw = pi, .pitch = 0.6, .length = 0.95, .width = 0.34, .taper = 1.1, .flick = 0.4, .layer = 1 },
    .{ .az = 2.5, .el = 0.55, .yaw = 2.6, .pitch = 0.1, .length = 0.70, .width = 0.28, .taper = 1.1, .flick = 0.3, .mirror = true },
    .{ .az = 0, .el = 0.85, .pitch = -0.9, .length = 0.50, .width = 0.22, .taper = 1.0, .stand = 0.3 },
    .{ .az = 0.5, .el = 0.78, .yaw = 0.8, .pitch = -0.7, .length = 0.52, .width = 0.20, .taper = 1.0, .stand = 0.3, .mirror = true },
    .{ .az = 1.35, .el = 0.45, .yaw = 1.5, .pitch = -0.5, .length = 0.45, .width = 0.20, .taper = 1.0, .stand = 0.3, .mirror = true },
};

/// Vegeta: every blade stands straight up like a flame; the hairline dips to a widow's peak.
const widow_flame = [_]C{
    .{ .az = 0, .el = 0.75, .pitch = 1.45, .length = 1.0, .width = 0.28, .taper = 1.0, .stand = 0.6, .layer = 1 },
    .{ .az = 0.55, .el = 0.95, .yaw = 0.5, .pitch = 1.4, .length = 1.1, .width = 0.30, .taper = 1.0, .stand = 0.6, .flick = 0.15, .layer = 2, .mirror = true },
    .{ .az = 1.15, .el = 0.95, .yaw = 1.1, .pitch = 1.35, .length = 1.0, .width = 0.30, .taper = 1.0, .stand = 0.6, .flick = 0.15, .layer = 1, .mirror = true },
    .{ .az = 1.85, .el = 0.9, .yaw = 1.9, .pitch = 1.3, .length = 0.95, .width = 0.30, .taper = 1.0, .stand = 0.6, .flick = 0.15, .mirror = true },
    .{ .az = 2.6, .el = 0.8, .yaw = 2.6, .pitch = 1.25, .length = 0.9, .width = 0.30, .taper = 1.0, .stand = 0.6, .flick = 0.2, .mirror = true },
    .{ .az = pi, .el = 0.95, .yaw = pi, .pitch = 1.3, .length = 1.0, .width = 0.32, .taper = 1.0, .stand = 0.6, .flick = 0.2, .layer = 1 },
    .{ .az = 0, .el = 1.4, .pitch = 1.5, .length = 1.15, .width = 0.30, .taper = 1.0, .stand = 0.7, .layer = 2 },
};

/// Gohan: short swept spikes with one long curled lock hanging between the eyes.
const fringe_spikes = [_]C{
    .{ .az = 0.25, .el = 1.25, .yaw = 0.3, .pitch = 0.95, .length = 0.62, .width = 0.30, .taper = 1.1, .flick = -0.3, .layer = 1, .mirror = true },
    .{ .az = 0.9, .el = 1.05, .yaw = 1.0, .pitch = 0.7, .length = 0.60, .width = 0.30, .taper = 1.1, .flick = 0.2, .mirror = true },
    .{ .az = 1.7, .el = 0.9, .yaw = 1.8, .pitch = 0.45, .length = 0.62, .width = 0.30, .taper = 1.1, .flick = 0.25, .mirror = true },
    .{ .az = 2.5, .el = 0.75, .yaw = 2.6, .pitch = 0.2, .length = 0.62, .width = 0.30, .taper = 1.1, .flick = 0.25, .mirror = true },
    .{ .az = pi, .el = 0.9, .yaw = pi, .pitch = 0.4, .length = 0.7, .width = 0.32, .taper = 1.1, .flick = 0.3 },
    .{ .az = 0.08, .el = 0.95, .yaw = 0.15, .pitch = -1.15, .length = 0.78, .width = 0.16, .taper = 1.0, .curl = 0.9, .stand = 0.35, .layer = 1, .sway = true },
    .{ .az = 0.6, .el = 0.8, .yaw = 0.9, .pitch = -0.75, .length = 0.50, .width = 0.22, .taper = 1.0, .stand = 0.3, .mirror = true },
    .{ .az = 1.4, .el = 0.45, .yaw = 1.5, .pitch = -0.9, .length = 0.50, .width = 0.22, .taper = 1.0, .stand = 0.3, .mirror = true },
};

/// A long Super Saiyan flare: very tall blades behind, a heavy mane streaming down the back.
const super_flare = [_]C{
    .{ .az = 0, .el = 1.35, .pitch = 1.35, .length = 1.2, .width = 0.36, .taper = 1.0, .stand = 0.5, .layer = 2 },
    .{ .az = 0.5, .el = 1.15, .yaw = 0.6, .pitch = 1.2, .length = 1.3, .width = 0.36, .taper = 1.0, .flick = 0.3, .layer = 2, .mirror = true },
    .{ .az = 1.1, .el = 1.0, .yaw = 1.3, .pitch = 1.0, .length = 1.3, .width = 0.36, .taper = 1.0, .flick = 0.3, .layer = 1, .mirror = true },
    .{ .az = 1.8, .el = 0.9, .yaw = 2.0, .pitch = 0.6, .length = 1.4, .width = 0.36, .taper = 1.0, .flick = 0.35, .layer = 1, .mirror = true },
    .{ .az = 2.5, .el = 0.7, .yaw = 2.7, .pitch = 0.1, .length = 1.5, .width = 0.36, .taper = 1.0, .flick = 0.4, .mirror = true, .sway = true },
    .{ .az = pi, .el = 1.0, .yaw = pi, .pitch = 0.5, .length = 1.6, .width = 0.40, .taper = 1.0, .flick = 0.45, .layer = 1, .sway = true },
    .{ .az = pi, .el = 0.3, .yaw = pi, .pitch = -0.5, .length = 1.5, .width = 0.40, .taper = 1.0, .flick = 0.5, .sway = true },
    .{ .az = 0.15, .el = 0.9, .yaw = 0.25, .pitch = -1.2, .length = 0.85, .width = 0.18, .taper = 1.0, .curl = 0.5, .stand = 0.3, .layer = 1 },
    .{ .az = 0.7, .el = 0.8, .yaw = 1.0, .pitch = -1.0, .length = 0.75, .width = 0.20, .taper = 1.0, .stand = 0.3, .mirror = true },
    .{ .az = 1.4, .el = 0.4, .yaw = 1.5, .pitch = -1.25, .length = 0.95, .width = 0.20, .taper = 1.0, .stand = 0.3, .mirror = true, .sway = true },
};

/// Mega Man: a rounded bob whose ends flip outward, with a short straight fringe.
const flip_bob = [_]C{
    .{ .az = 0.5, .el = 1.25, .yaw = 0.5, .pitch = 0.1, .length = 0.62, .width = 0.30, .taper = 1.6, .stand = 0.5, .flick = 0.5, .layer = 1, .mirror = true },
    .{ .az = 1.2, .el = 0.95, .yaw = 1.2, .pitch = -0.4, .length = 0.62, .width = 0.30, .taper = 1.6, .stand = 0.4, .flick = 1.0, .mirror = true },
    .{ .az = 1.9, .el = 0.7, .yaw = 1.9, .pitch = -0.7, .length = 0.62, .width = 0.30, .taper = 1.6, .stand = 0.35, .flick = 1.1, .mirror = true },
    .{ .az = 2.6, .el = 0.55, .yaw = 2.6, .pitch = -0.8, .length = 0.62, .width = 0.30, .taper = 1.6, .stand = 0.35, .flick = 1.1, .mirror = true },
    .{ .az = pi, .el = 0.6, .yaw = pi, .pitch = -0.8, .length = 0.62, .width = 0.32, .taper = 1.6, .stand = 0.35, .flick = 1.1 },
    .{ .az = pi, .el = 1.2, .yaw = pi, .pitch = 0.4, .length = 0.55, .width = 0.32, .taper = 1.6, .flick = -0.4, .layer = 1 },
    .{ .az = 0, .el = 1.0, .pitch = -1.2, .length = 0.42, .width = 0.26, .taper = 1.4, .stand = 0.3 },
    .{ .az = 0.45, .el = 0.95, .yaw = 0.6, .pitch = -1.05, .length = 0.44, .width = 0.24, .taper = 1.4, .stand = 0.3, .mirror = true },
    .{ .az = 0.95, .el = 0.8, .yaw = 1.0, .pitch = -0.9, .length = 0.46, .width = 0.24, .taper = 1.4, .stand = 0.3, .mirror = true },
};

/// Gundam pilot: thick bangs swept hard to one side over big wavy volume.
const pilot_sweep = [_]C{
    .{ .az = 0.0, .el = 1.2, .yaw = 0.9, .pitch = -0.2, .length = 0.85, .width = 0.34, .taper = 1.3, .curl = 0.6, .stand = 0.5, .flick = -0.5, .layer = 2 },
    .{ .az = 0.3, .el = 1.0, .yaw = 1.0, .pitch = -0.5, .length = 0.80, .width = 0.32, .taper = 1.3, .curl = 0.7, .stand = 0.4, .flick = -0.3, .layer = 1 },
    .{ .az = -0.3, .el = 1.05, .yaw = 0.7, .pitch = -0.6, .length = 0.85, .width = 0.30, .taper = 1.3, .curl = 0.7, .stand = 0.4, .flick = -0.3, .layer = 1 },
    .{ .az = 0.9, .el = 0.8, .yaw = 1.2, .pitch = -0.6, .length = 0.55, .width = 0.30, .taper = 1.3, .curl = 0.5, .stand = 0.3 },
    .{ .az = -0.9, .el = 0.8, .yaw = -1.1, .pitch = -0.8, .length = 0.5, .width = 0.30, .taper = 1.3, .curl = -0.4, .stand = 0.3 },
    .{ .az = 1.6, .el = 0.8, .yaw = 1.7, .pitch = -0.4, .length = 0.62, .width = 0.32, .taper = 1.4, .curl = 0.3, .stand = 0.4, .mirror = true },
    .{ .az = 2.4, .el = 0.8, .yaw = 2.5, .pitch = -0.2, .length = 0.62, .width = 0.32, .taper = 1.4, .curl = 0.3, .stand = 0.4, .flick = 0.5, .mirror = true },
    .{ .az = pi, .el = 0.8, .yaw = pi, .pitch = -0.1, .length = 0.65, .width = 0.34, .taper = 1.4, .stand = 0.4, .flick = 0.6 },
    .{ .az = pi, .el = 1.3, .yaw = pi, .pitch = 0.5, .length = 0.55, .width = 0.34, .taper = 1.3, .flick = 0.3, .layer = 1 },
    .{ .az = 1.2, .el = 1.3, .yaw = 1.5, .pitch = 0.3, .length = 0.6, .width = 0.34, .taper = 1.3, .flick = 0.2, .layer = 1, .mirror = true },
};

/// A heavy fringe across the forehead with two long locks framing the face.
const big_fringe = [_]C{
    .{ .az = 0.0, .el = 1.0, .pitch = -1.2, .length = 0.62, .width = 0.26, .taper = 1.3, .stand = 0.35, .layer = 2 },
    .{ .az = 0.35, .el = 0.95, .yaw = 0.5, .pitch = -1.1, .length = 0.64, .width = 0.26, .taper = 1.3, .stand = 0.35, .layer = 2, .mirror = true },
    .{ .az = 0.75, .el = 0.85, .yaw = 0.95, .pitch = -0.95, .length = 0.6, .width = 0.26, .taper = 1.3, .stand = 0.35, .layer = 1, .mirror = true },
    .{ .az = 1.2, .el = 0.65, .yaw = 1.4, .pitch = -1.25, .length = 1.0, .width = 0.22, .taper = 1.1, .stand = 0.3, .layer = 1, .sway = true, .mirror = true },
    .{ .az = 0.0, .el = 1.4, .yaw = pi, .pitch = 0.3, .length = 0.7, .width = 0.34, .taper = 1.4, .stand = 0.5, .flick = 0.3 },
    .{ .az = 1.7, .el = 1.0, .yaw = 1.9, .pitch = 0.1, .length = 0.62, .width = 0.32, .taper = 1.4, .stand = 0.45, .flick = 0.4, .mirror = true },
    .{ .az = 2.5, .el = 0.8, .yaw = 2.6, .pitch = -0.4, .length = 0.62, .width = 0.32, .taper = 1.4, .stand = 0.4, .flick = 0.5, .mirror = true },
    .{ .az = pi, .el = 0.75, .yaw = pi, .pitch = -0.5, .length = 0.65, .width = 0.34, .taper = 1.4, .stand = 0.4, .flick = 0.5 },
    .{ .az = pi, .el = 1.2, .yaw = pi, .pitch = 0.1, .length = 0.65, .width = 0.34, .taper = 1.4, .flick = 0.3 },
};

/// Short sides, a bundled knot at the crown and a few spikes of fringe.
const topknot = [_]C{
    .{ .az = pi, .el = 1.15, .yaw = pi, .pitch = 1.15, .length = 0.55, .width = 0.30, .taper = 1.8, .stand = 0.6, .layer = 2 },
    .{ .az = 3.5, .el = 1.2, .yaw = 3.7, .pitch = 1.0, .length = 0.5, .width = 0.28, .taper = 1.8, .stand = 0.6, .layer = 2, .curl = 0.5 },
    .{ .az = 2.8, .el = 1.2, .yaw = 2.6, .pitch = 1.0, .length = 0.5, .width = 0.28, .taper = 1.8, .stand = 0.6, .layer = 2, .curl = -0.5 },
    .{ .az = pi, .el = 1.15, .yaw = pi, .pitch = 0.5, .length = 0.65, .width = 0.30, .taper = 1.3, .stand = 0.7, .layer = 3, .flick = 0.5 },
    .{ .az = 0.3, .el = 1.35, .yaw = 0.3, .pitch = 0.9, .length = 0.4, .width = 0.30, .taper = 1.1, .flick = -0.6, .layer = 1, .mirror = true },
    .{ .az = 1.2, .el = 1.2, .yaw = 1.3, .pitch = 0.7, .length = 0.35, .width = 0.30, .taper = 1.1, .mirror = true },
    .{ .az = 0, .el = 0.9, .pitch = -1.0, .length = 0.38, .width = 0.22, .stand = 0.3 },
    .{ .az = 0.5, .el = 0.8, .yaw = 0.8, .pitch = -0.8, .length = 0.4, .width = 0.20, .stand = 0.3, .mirror = true },
};
const topknot_cap: hs.CapDef = .{ .hairline = .{ 0.55, 0.5, 0.3, -0.5, -0.7 } };

/// A spiky ponytail: three fat blades bunched at the back of the crown, short spikes in front.
const spike_tail = [_]C{
    .{ .az = pi, .el = 1.0, .yaw = pi, .pitch = 0.85, .length = 1.1, .width = 0.32, .taper = 1.0, .stand = 0.5, .flick = 0.2, .layer = 2, .sway = true },
    .{ .az = pi, .el = 0.9, .yaw = pi, .pitch = 0.35, .length = 1.25, .width = 0.34, .taper = 1.0, .stand = 0.5, .flick = 0.3, .layer = 2, .sway = true },
    .{ .az = 3.5, .el = 0.9, .yaw = 3.8, .pitch = 0.2, .length = 1.1, .width = 0.30, .taper = 1.0, .stand = 0.5, .flick = 0.3, .layer = 2, .sway = true },
    .{ .az = 2.8, .el = 0.9, .yaw = 2.5, .pitch = 0.2, .length = 1.1, .width = 0.30, .taper = 1.0, .stand = 0.5, .flick = 0.3, .layer = 2, .sway = true },
    .{ .az = pi, .el = 0.85, .yaw = pi, .pitch = -0.3, .length = 1.0, .width = 0.30, .taper = 1.0, .stand = 0.5, .flick = 0.4, .layer = 2, .sway = true },
    .{ .az = 0.2, .el = 1.3, .yaw = 0.2, .pitch = 1.0, .length = 0.5, .width = 0.30, .taper = 1.1, .flick = -0.4, .layer = 1, .mirror = true },
    .{ .az = 1.0, .el = 1.1, .yaw = 1.1, .pitch = 0.7, .length = 0.5, .width = 0.30, .taper = 1.1, .mirror = true },
    .{ .az = 1.8, .el = 1.0, .yaw = 2.0, .pitch = 0.6, .length = 0.5, .width = 0.30, .taper = 1.1, .mirror = true },
    .{ .az = 0, .el = 0.85, .pitch = -0.95, .length = 0.45, .width = 0.22, .taper = 1.0, .stand = 0.3 },
    .{ .az = 0.5, .el = 0.78, .yaw = 0.8, .pitch = -0.8, .length = 0.45, .width = 0.2, .taper = 1.0, .stand = 0.3, .mirror = true },
    .{ .az = 1.35, .el = 0.45, .yaw = 1.5, .pitch = -0.9, .length = 0.4, .width = 0.2, .taper = 1.0, .stand = 0.3, .mirror = true },
};

const mohawk_cap: hs.CapDef = .{ .hairline = .{ 0.62, 0.2, -0.3, -0.88, -0.95 } };
const high_front_cap: hs.CapDef = .{ .hairline = .{ 0.75, 0.55, 0.0, -0.7, -0.9 } };

const table = [_]struct { style: spec.HairStyle, def: hs.StyleDef }{
    .{ .style = .short_spiky, .def = .{ .name = "short_spiky", .clumps = &short_spiky } },
    .{ .style = .mohawk, .def = .{ .name = "mohawk", .clumps = &mohawk, .cap = mohawk_cap } },
    .{ .style = .spiky_hero, .def = .{ .name = "spiky_hero", .clumps = &spiky_hero } },
    .{ .style = .widow_flame, .def = .{ .name = "widow_flame", .clumps = &widow_flame, .cap = high_front_cap } },
    .{ .style = .fringe_spikes, .def = .{ .name = "fringe_spikes", .clumps = &fringe_spikes } },
    .{ .style = .super_flare, .def = .{ .name = "super_flare", .clumps = &super_flare } },
    .{ .style = .flip_bob, .def = .{ .name = "flip_bob", .clumps = &flip_bob } },
    .{ .style = .pilot_sweep, .def = .{ .name = "pilot_sweep", .clumps = &pilot_sweep } },
    .{ .style = .big_fringe, .def = .{ .name = "big_fringe", .clumps = &big_fringe } },
    .{ .style = .topknot, .def = .{ .name = "topknot", .clumps = &topknot, .cap = topknot_cap } },
    .{ .style = .spike_tail, .def = .{ .name = "spike_tail", .clumps = &spike_tail } },
};

/// Every built-in definition, for tests and tools.
pub const all = blk: {
    var defs: [table.len]hs.StyleDef = undefined;
    for (table, 0..) |e, i| defs[i] = e.def;
    const out = defs;
    break :blk out;
};

/// The data definition behind a style, or null for styles still generated procedurally.
pub fn lookup(style: spec.HairStyle) ?*const hs.StyleDef {
    inline for (&table) |*e| if (e.style == style) return &e.def;
    return null;
}

test "every built-in definition validates" {
    for (all) |d| try hs.validate(d);
}
