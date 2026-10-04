//! animegen — procedural anime-style characters & clothing, in pure Zig.
//!
//!   spec ──► skeleton ──► body loft ──► clothing shells / skirt / hair ──► Mesh
//!                │                                                          │
//!                └──► Pose (FK, IK, spring bones) ──► skin matrices / DQs ──┘
//!
//! Shading math (toon ramp, rim, outlines, eye & face-shadow textures) lives in
//! `toon`, written so each function ports 1:1 to a shader.

const std = @import("std");

pub const math = @import("math.zig");
pub const curve = @import("curve.zig");
pub const mesh = @import("mesh.zig");
pub const skeleton = @import("skeleton.zig");
pub const Animation = @import("Animation.zig");
pub const spec = @import("spec.zig");
pub const body = @import("body.zig");
pub const clothing = @import("clothing.zig");
pub const hair = @import("hair.zig");
pub const ik = @import("ik.zig");
pub const spring = @import("spring.zig");
pub const toon = @import("toon.zig");
pub const raster = @import("raster.zig");
pub const character = @import("character.zig");
pub const preview = @import("preview.zig");
pub const loft = @import("loft.zig");

// Convenience re-exports
pub const Vec2 = math.Vec2;
pub const Vec3 = math.Vec3;
pub const Quat = math.Quat;
pub const Mat4 = math.Mat4;
pub const Transform = math.Transform;
pub const Mesh = mesh.Mesh;
pub const Skeleton = skeleton.Skeleton;
pub const Pose = skeleton.Pose;
pub const Joint = skeleton.Joint;
pub const CharacterSpec = spec.CharacterSpec;
pub const Character = character.Character;
pub const Instance = character.Instance;

test {
    _ = math;
    _ = curve;
    _ = mesh;
    _ = skeleton;
    _ = Animation;
    _ = spec;
    _ = body;
    _ = clothing;
    _ = hair;
    _ = ik;
    _ = spring;
    _ = toon;
    _ = raster;
    _ = character;
    _ = preview;
    _ = loft;
}
