//! Allocation-free skeletal animation clips. Tracks contain local rotation deltas so locomotion
//! can blend over a character's relaxed/rest pose before aim and combat layers are applied.
const std = @import("std");
const Math = @import("math.zig");
const Skeleton = @import("skeleton.zig");
const V = Math.Vec3;
const Q = Math.Quat;

pub const Key = struct { time: f32, value: Q = Q.identity };
pub const Track = struct { joint: u16, keys: []const Key };
pub const Clip = struct {
    duration: f32,
    looping: bool = true,
    tracks: []const Track,
};
pub const ClipId = enum { idle, walk, run, climb, air };
pub const Blend = struct { from: ClipId, to: ClipId, alpha: f32 };

/// Per-character motion transition state. Time is supplied by the fixed-step game clock, so the
/// rendered pose stays identical across split-screen views and does not depend on draw order.
pub const Controller = struct {
    from: ClipId = .idle,
    current: ClipId = .idle,
    elapsed: f32 = 0,
    last_time: f32 = 0,
    initialized: bool = false,
    pub const fade_seconds: f32 = 0.18;

    pub fn update(self: *Controller, target: ClipId, now: f32) Blend {
        if (!self.initialized) {
            self.initialized = true;
            self.from = target;
            self.current = target;
            self.last_time = now;
            self.elapsed = fade_seconds;
            return .{ .from = target, .to = target, .alpha = 1 };
        }
        const dt = std.math.clamp(now - self.last_time, 0, 0.1);
        self.last_time = now;
        if (target != self.current) {
            self.from = self.current;
            self.current = target;
            self.elapsed = 0;
        } else {
            self.elapsed = @min(fade_seconds, self.elapsed + dt);
        }
        return .{ .from = self.from, .to = self.current, .alpha = std.math.clamp(self.elapsed / fade_seconds, 0, 1) };
    }
};

/// Sample a sorted local-rotation track. Looping clips interpolate across their final/first
/// key seam, which permits tracks to omit a duplicated endpoint key.
pub fn sample(clip: Clip, track: Track, time: f32) Q {
    const keys = track.keys;
    if (keys.len == 0 or clip.duration <= 0) return Q.identity;
    if (keys.len == 1) return keys[0].value;
    const t = if (clip.looping) @mod(time, clip.duration) else std.math.clamp(time, 0, clip.duration);

    if (t < keys[0].time) {
        if (!clip.looping) return keys[0].value;
        const span = keys[0].time + clip.duration - keys[keys.len - 1].time;
        const alpha = if (span > 0) (t + clip.duration - keys[keys.len - 1].time) / span else 0;
        return Q.nlerp(keys[keys.len - 1].value, keys[0].value, alpha);
    }
    for (keys[0 .. keys.len - 1], keys[1..]) |left, right| {
        if (t <= right.time) {
            const span = right.time - left.time;
            const alpha = if (span > 0) (t - left.time) / span else 0;
            return Q.nlerp(left.value, right.value, alpha);
        }
    }
    if (!clip.looping) return keys[keys.len - 1].value;
    const last = keys[keys.len - 1];
    const first = keys[0];
    const span = clip.duration - last.time + first.time;
    const alpha = if (span > 0) (t - last.time) / span else 0;
    return Q.nlerp(last.value, first.value, alpha);
}

/// Blend a clip's local rotation deltas over the current pose. Parent order is irrelevant here;
/// the caller refreshes forward kinematics after all animation layers have been applied.
pub fn apply(clip: Clip, pose: *Skeleton.Pose, time: f32, weight: f32) void {
    const w = std.math.clamp(weight, 0, 1);
    if (w <= 0) return;
    for (clip.tracks) |track| {
        if (track.joint >= pose.local.len) continue;
        const base = pose.local[track.joint].rotation;
        const animated = sample(clip, track, time).mul(base).normalize();
        pose.local[track.joint].rotation = Q.nlerp(base, animated, w);
    }
}

fn axis(angle: f32) Q {
    return Q.fromAxisAngle(V.unit_x, angle);
}

const arm_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(-0.49) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0.49) },
};
const arm_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0.49) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.49) },
};
const thigh_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0.65) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.65) },
};
const thigh_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(-0.65) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0.65) },
};
const shin_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0.78) },
};
const shin_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0.78) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0) },
};
const torso = [_]Key{
    .{ .time = 0, .value = Q.identity },           .{ .time = std.math.pi * 0.5, .value = Q.fromAxisAngle(V.unit_y, 0.05) },
    .{ .time = std.math.pi, .value = Q.identity }, .{ .time = std.math.pi * 1.5, .value = Q.fromAxisAngle(V.unit_y, -0.05) },
};

pub const walk_tracks = [_]Track{
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_l), .keys = &arm_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_r), .keys = &arm_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_l), .keys = &thigh_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_r), .keys = &thigh_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.shin_l), .keys = &shin_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.shin_r), .keys = &shin_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.chest), .keys = &torso },
};
pub const walk = Clip{ .duration = 2 * std.math.pi, .tracks = &walk_tracks };

const run_arm_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(-0.72) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0.72) },
};
const run_arm_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0.72) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.72) },
};
const run_thigh_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0.86) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.86) },
};
const run_thigh_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(-0.86) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0.86) },
};
const run_shin_left = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(0) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(1.05) },
};
const run_shin_right = [_]Key{
    .{ .time = 0, .value = axis(0) },           .{ .time = std.math.pi * 0.5, .value = axis(1.05) },
    .{ .time = std.math.pi, .value = axis(0) }, .{ .time = std.math.pi * 1.5, .value = axis(0) },
};
pub const run_tracks = [_]Track{
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_l), .keys = &run_arm_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_r), .keys = &run_arm_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_l), .keys = &run_thigh_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_r), .keys = &run_thigh_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.shin_l), .keys = &run_shin_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.shin_r), .keys = &run_shin_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.chest), .keys = &torso },
};
pub const run = Clip{ .duration = 2 * std.math.pi, .tracks = &run_tracks };

const climb_arm_left = [_]Key{
    .{ .time = 0, .value = axis(-0.55) },           .{ .time = std.math.pi * 0.5, .value = axis(0.32) },
    .{ .time = std.math.pi, .value = axis(-0.55) }, .{ .time = std.math.pi * 1.5, .value = axis(0.32) },
};
const climb_arm_right = [_]Key{
    .{ .time = 0, .value = axis(0.32) },           .{ .time = std.math.pi * 0.5, .value = axis(-0.55) },
    .{ .time = std.math.pi, .value = axis(0.32) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.55) },
};
const climb_thigh_left = [_]Key{
    .{ .time = 0, .value = axis(0.38) },            .{ .time = std.math.pi * 0.5, .value = axis(-0.12) },
    .{ .time = std.math.pi, .value = axis(-0.12) }, .{ .time = std.math.pi * 1.5, .value = axis(0.38) },
};
const climb_thigh_right = [_]Key{
    .{ .time = 0, .value = axis(-0.12) },          .{ .time = std.math.pi * 0.5, .value = axis(0.38) },
    .{ .time = std.math.pi, .value = axis(0.38) }, .{ .time = std.math.pi * 1.5, .value = axis(-0.12) },
};
pub const climb_tracks = [_]Track{
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_l), .keys = &climb_arm_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.upper_arm_r), .keys = &climb_arm_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.lower_arm_l), .keys = &shin_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.lower_arm_r), .keys = &shin_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_l), .keys = &climb_thigh_left },
    .{ .joint = @intFromEnum(Skeleton.Joint.thigh_r), .keys = &climb_thigh_right },
    .{ .joint = @intFromEnum(Skeleton.Joint.chest), .keys = &torso },
};
pub const climb = Clip{ .duration = 2 * std.math.pi, .tracks = &climb_tracks };
pub const idle = Clip{ .duration = 1, .tracks = &.{} };
pub const air = Clip{ .duration = 1, .tracks = &.{} };

pub fn get(id: ClipId) Clip {
    return switch (id) {
        .idle => idle,
        .walk => walk,
        .run => run,
        .climb => climb,
        .air => air,
    };
}

test "rotation tracks interpolate keys and loop across the clip seam" {
    const keys = [_]Key{
        .{ .time = 0, .value = axis(0) },
        .{ .time = 0.5, .value = axis(1.2) },
    };
    const clip: Clip = .{ .duration = 1, .tracks = &.{} };
    const track: Track = .{ .joint = 0, .keys = &keys };
    const quarter = sample(clip, track, 0.25);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(quarter.dot(axis(0.6))), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(sample(clip, track, 1).dot(axis(0))), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(sample(clip, track, -0.5).dot(axis(1.2))), 1e-5);
}

test "animation blend applies local joint deltas without replacing the rest pose" {
    var skel: Skeleton.Skeleton = .{};
    defer skel.deinit(std.testing.allocator);
    _ = try skel.addBone(std.testing.allocator, "root", Skeleton.no_parent, V.zero);
    _ = try skel.addBone(std.testing.allocator, "arm", 0, V.init(1, 0, 0));
    var pose = try Skeleton.Pose.init(std.testing.allocator, &skel);
    defer pose.deinit(std.testing.allocator);
    const half = [_]Key{.{ .time = 0, .value = axis(1) }};
    const tracks = [_]Track{.{ .joint = 1, .keys = &half }};
    const clip: Clip = .{ .duration = 1, .looping = false, .tracks = &tracks };
    apply(clip, &pose, 0, 0.5);
    const expected = Q.nlerp(Q.identity, axis(1), 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(pose.local[1].rotation.dot(expected)), 1e-5);
    try std.testing.expect(pose.local[1].translation.approxEq(V.init(1, 0, 0), 1e-5));
}

test "motion controller crossfades and retargets clips from fixed-step time" {
    var controller: Controller = .{};
    const first = controller.update(.walk, 10);
    try std.testing.expectEqual(ClipId.walk, first.from);
    try std.testing.expectEqual(@as(f32, 1), first.alpha);
    const switched = controller.update(.run, 10.016);
    try std.testing.expectEqual(ClipId.walk, switched.from);
    try std.testing.expectEqual(ClipId.run, switched.to);
    try std.testing.expectApproxEqAbs(@as(f32, 0), switched.alpha, 1e-5);
    const middle = controller.update(.run, 10.106);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), middle.alpha, 0.02);
    const done = controller.update(.run, 10.25);
    try std.testing.expectEqual(@as(f32, 1), done.alpha);
    const retarget = controller.update(.climb, 10.266);
    try std.testing.expectEqual(ClipId.run, retarget.from);
    try std.testing.expectEqual(ClipId.climb, retarget.to);
}
