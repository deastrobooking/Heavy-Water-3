//! Publishes one skinned character descriptor. Geometry and pose buffers live in the renderer.
const World = @import("../world/World.zig");
const Catalog = @import("../asset/Catalog.zig");
const Profile = @import("Profile.zig");
pub const Pose = @import("../character/Ranger.zig").Pose;
pub const max_parts = 1;
pub fn build(profile: Profile, pose: Pose, _: Catalog.MeshHandle, out: []World.Prop) usize {
    if (out.len == 0) return 0;
    out[0] = .{ .mesh = .none, .transform = .{ .position = pose.feet }, .tint = .{ 1, 1, 1, 1 }, .character = .{ .profile = profile, .pose = pose } };
    return 1;
}
