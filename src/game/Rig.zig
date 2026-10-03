//! A player's skeleton in the simulation: the same body as their drawn character and the same
//! procedural poser (`Ranger.poseSkeleton`), without a mesh. It answers where the right hand is
//! and which way the blade or barrel points, so saber cuts land where the blade is drawn and
//! shots leave from the hand. Rebuilt only when the body changes (height, build, presentation).
const std = @import("std");
const Ranger = @import("../character/Ranger.zig");
const Profile = @import("Profile.zig");
const generator = @import("../character/body.zig");
const sk = @import("../character/skeleton.zig");
const spec = @import("../character/spec.zig");
const m = @import("../character/math.zig");
const Rig = @This();

skeleton: sk.Skeleton,
pose: sk.Pose,
body: spec.BodySpec,

pub fn init(a: std.mem.Allocator, profile: Profile) !Rig {
    const b = Ranger.bodySpec(profile);
    const character: spec.CharacterSpec = .{ .body = b };
    var skeleton = try generator.buildSkeleton(a, character, generator.computeLandmarks(character));
    errdefer skeleton.deinit(a);
    return .{ .skeleton = skeleton, .pose = try sk.Pose.init(a, &skeleton), .body = b };
}

pub fn deinit(self: *Rig, a: std.mem.Allocator) void {
    self.pose.deinit(a);
    self.skeleton.deinit(a);
}

/// Rebuilds when the body differs from the one this rig was built for.
pub fn refresh(self: *Rig, a: std.mem.Allocator, profile: Profile) !void {
    if (std.meta.eql(self.body, Ranger.bodySpec(profile))) return;
    var next = try init(a, profile);
    errdefer next.deinit(a);
    self.deinit(a);
    self.* = next;
}

pub const Hand = struct {
    /// Right hand (palm) in the world.
    position: [3]f32,
    /// Forearm direction through the hand (the saber blade's direction), world, unit.
    blade: [3]f32,
};

fn world(state: Ranger.Pose, p: m.Vec3) m.Vec3 {
    return m.Quat.fromAxisAngle(m.Vec3.unit_y, state.yaw).rotate(p).add(m.Vec3.init(state.feet[0], state.feet[1], state.feet[2]));
}

/// Poses the skeleton for `state` and reports the right hand.
pub fn hand(self: *Rig, state: Ranger.Pose) Hand {
    Ranger.poseSkeleton(&self.pose, &self.skeleton, state);
    const h = self.pose.global[sk.Joint.hand_r.idx()].translation;
    const e = self.pose.global[sk.Joint.lower_arm_r.idx()].translation;
    const hw = world(state, h);
    const dir = world(state, h).sub(world(state, e)).normalizeOr(m.Vec3.unit_z);
    return .{ .position = .{ hw.x, hw.y, hw.z }, .blade = .{ dir.x, dir.y, dir.z } };
}

test "the saber arm sweeps across the front, and aiming brings the hand forward" {
    const a = std.testing.allocator;
    var rig = try Rig.init(a, .{});
    defer rig.deinit(a);
    const base: Ranger.Pose = .{ .feet = .{ 10, 0, 5 }, .yaw = 0 };
    const rest = rig.hand(base);
    // Relaxed: the hand hangs at the right side (-X is the right), below the chest.
    try std.testing.expect(rest.position[0] < 10 and rest.position[1] < 1.2);
    // A forehand cut starts on the right and finishes on the left, in front.
    var swing = base;
    swing.action = .swing;
    swing.arc = .forehand;
    swing.action_t = 0;
    const start = rig.hand(swing);
    swing.action_t = 1;
    const end = rig.hand(swing);
    // The right shoulder sits off-centre, so the follow-through reaches just past the midline;
    // the blade itself points well to the left.
    try std.testing.expect(start.position[0] < 10 - 0.3 and end.position[0] > 10 + 0.15);
    try std.testing.expect(start.blade[0] < -0.7 and end.blade[0] > 0.7);
    swing.action_t = 0.5;
    const middle = rig.hand(swing);
    try std.testing.expect(middle.position[2] > 5 + 0.4 and middle.blade[2] > 0.7);
    // Aiming level: the hand is ahead of the chest and the barrel points ahead.
    var aim = base;
    aim.action = .aim;
    const held = rig.hand(aim);
    try std.testing.expect(held.position[2] > 5 + 0.25 and held.position[1] > 1.0);
    // Turning the body turns the hand with it.
    aim.yaw = std.math.pi / 2.0;
    const turned = rig.hand(aim);
    try std.testing.expect(turned.position[0] > 10 + 0.25);
    // The body is rebuilt only when it changes.
    try rig.refresh(a, .{});
    try rig.refresh(a, .{ .height = 1.08 });
    try std.testing.expect(rig.body.height > 1.9);
}
