//! Built-in physics backend: axis-aligned boxes without rotation, semi-implicit Euler,
//! positional contact resolution against the ground and each other, and Coulomb-style ground
//! friction. Kinematic bodies follow their velocity exactly and push dynamic bodies and the
//! character without being pushed back. It has no angular dynamics, continuous collision, restitution, or broadphase
//! (O(n²) over at most 128 bodies). Adequate for props and the character; not a rigid-body engine.
const std = @import("std");
const Handle = @import("../engine/Handle.zig");
const Physics = @import("Physics.zig");
const Rigid = @import("Rigid.zig");
const R = @import("Rotation.zig");
const Vec3 = Physics.Vec3;
const BoxWorld = @This();

pub const iterations = 4;
const sleep_speed: f32 = 0.05;

pub const BodyState = struct {
    position: Vec3,
    velocity: Vec3,
    half: Vec3,
    inv_mass: f32,
    friction: f32,
    gravity_scale: f32 = 1,
    kinematic: bool = false,
    grounded: bool = false,
    user: u32,
};

ground: Physics.Ground,
bodies: Handle.Pool(Physics.BodyTag, BodyState, Physics.max_bodies) = .{},
rigids: Handle.Pool(Physics.RigidTag, Rigid.State, Physics.max_rigids) = .{},
meshes: Handle.Pool(Physics.MeshTag, MeshEntry, Physics.max_meshes) = .{},

pub const MeshEntry = struct { mesh: Physics.TriangleMesh, user: u32 };

/// Highest walkable mesh surface hit by a downward ray from `top`, within `depth`.
pub fn meshFloor(self: *const BoxWorld, top: Vec3, depth: f32) ?f32 {
    var best: ?f32 = null;
    var live = self.meshes.live.iterator(.{});
    while (live.next()) |i| {
        const hit = self.meshes.items[i].mesh.raycast(top, .{ 0, -1, 0 }, depth) orelse continue;
        if (hit.normal[1] < Physics.walkable_normal_y) continue;
        if (best == null or hit.point[1] > best.?) best = hit.point[1];
    }
    return best;
}

pub fn createRigid(self: *BoxWorld, desc: Physics.RigidDesc) !Physics.Rigid {
    for (desc.half_extents ++ desc.position ++ desc.orientation ++ desc.linear ++ desc.angular) |v| if (!std.math.isFinite(v)) return error.InvalidBody;
    for (desc.half_extents) |h| if (h <= 0) return error.InvalidBody;
    if (!(desc.mass > 0)) return error.InvalidBody;
    return self.rigids.add(Rigid.init(desc));
}

pub fn create(self: *BoxWorld, desc: Physics.BodyDesc) !Physics.Body {
    for (desc.half_extents ++ desc.position ++ desc.velocity) |v| if (!std.math.isFinite(v)) return error.InvalidBody;
    for (desc.half_extents) |h| if (h <= 0) return error.InvalidBody;
    if (desc.motion == .dynamic and !(desc.mass > 0)) return error.InvalidBody;
    return self.bodies.add(.{
        .position = desc.position,
        .velocity = if (desc.motion == .static) .{ 0, 0, 0 } else desc.velocity,
        .half = desc.half_extents,
        .inv_mass = if (desc.motion == .dynamic) 1 / desc.mass else 0,
        .kinematic = desc.motion == .kinematic,
        .friction = desc.friction,
        .user = desc.user,
    });
}

pub fn destroy(self: *BoxWorld, body: Physics.Body) void {
    _ = self.bodies.remove(body);
}

pub fn step(self: *BoxWorld, dt: f32) void {
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0 and !b.kinematic) continue;
        if (!b.kinematic) b.velocity[1] += Physics.gravity * b.gravity_scale * dt;
        for (0..3) |axis| b.position[axis] += b.velocity[axis] * dt;
        b.grounded = false;
    }
    for (0..iterations) |_| {
        self.solvePairs();
        self.solveGround();
    }
    // Rigid bodies see the boxes' resolved positions and push dynamic ones.
    var rigid = self.rigids.live.iterator(.{});
    while (rigid.next()) |i| Rigid.step(self, &self.rigids.items[i], dt);
    // Vehicles and other oriented boxes contact one another too. Capacity is deliberately small,
    // so four pair passes are cheaper and simpler than maintaining a broadphase.
    var indices: [Physics.max_rigids]usize = undefined;
    var count: usize = 0;
    rigid = self.rigids.live.iterator(.{});
    while (rigid.next()) |i| {
        indices[count] = i;
        count += 1;
    }
    for (0..4) |_| for (0..count) |ai| for (ai + 1..count) |bi| {
        const a = &self.rigids.items[indices[ai]];
        const b = &self.rigids.items[indices[bi]];
        if (Rigid.pairContact(a.*, b.*)) |contact| Rigid.solvePair(a, b, contact);
    };
    live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0 or !b.grounded) continue;
        // Friction removes up to μ·g·dt of horizontal speed per step.
        const speed = @sqrt(b.velocity[0] * b.velocity[0] + b.velocity[2] * b.velocity[2]);
        const reduced = @max(0, speed - b.friction * -Physics.gravity * dt);
        const scale = if (speed > 0) reduced / speed else 0;
        b.velocity[0] *= scale;
        b.velocity[2] *= scale;
        if (reduced < sleep_speed and @abs(b.velocity[1]) < sleep_speed) b.velocity = .{ 0, 0, 0 };
    }
}

fn solveGround(self: *BoxWorld) void {
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        if (b.inv_mass == 0) continue;
        // Highest terrain under the footprint's corners and center supports the box.
        var support = -std.math.inf(f32);
        for ([_][2]f32{ .{ 0, 0 }, .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }) |c| {
            const x = b.position[0] + c[0] * b.half[0];
            const z = b.position[2] + c[1] * b.half[2];
            if (self.ground.at(.{ x, b.position[1], z })) |s| support = @max(support, s.height);
            // Mesh floors below the box's center height also support it.
            if (self.meshFloor(.{ x, b.position[1], z }, b.half[1] + 0.5)) |floor| support = @max(support, floor);
        }
        const bottom = b.position[1] - b.half[1];
        if (bottom < support) {
            b.position[1] = support + b.half[1];
            if (b.velocity[1] < 0) b.velocity[1] = 0;
            b.grounded = true;
        }
    }
}

fn solvePairs(self: *BoxWorld) void {
    var outer = self.bodies.live.iterator(.{});
    while (outer.next()) |i| {
        var inner = self.bodies.live.iterator(.{});
        while (inner.next()) |j| {
            if (j <= i) continue;
            const a = &self.bodies.items[i];
            const b = &self.bodies.items[j];
            const total = a.inv_mass + b.inv_mass;
            if (total == 0) continue;
            var axis: usize = 0;
            var depth = std.math.inf(f32);
            for (0..3) |k| {
                const overlap = a.half[k] + b.half[k] - @abs(b.position[k] - a.position[k]);
                if (overlap <= 0) break;
                if (overlap < depth) {
                    depth = overlap;
                    axis = k;
                }
            } else {
                const sign: f32 = if (b.position[axis] >= a.position[axis]) 1 else -1;
                a.position[axis] -= sign * depth * a.inv_mass / total;
                b.position[axis] += sign * depth * b.inv_mass / total;
                // Remove approaching normal velocity (perfectly inelastic), mass-weighted.
                const approach = (b.velocity[axis] - a.velocity[axis]) * sign;
                if (approach < 0) {
                    a.velocity[axis] += sign * approach * a.inv_mass / total;
                    b.velocity[axis] -= sign * approach * b.inv_mass / total;
                }
                if (axis == 1) {
                    if (sign > 0) b.grounded = true else a.grounded = true;
                }
            }
        }
    }
}

pub fn raycast(self: *const BoxWorld, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Physics.Body) ?Physics.Hit {
    var best: ?Physics.Hit = null;
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const id = self.bodies.idAt(i);
        if (id.eql(ignore)) continue;
        const b = self.bodies.items[i];
        const hit = Physics.rayBox(origin, direction, b.position, b.half) orelse continue;
        if (hit.distance > max_distance or (best != null and hit.distance >= best.?.distance)) continue;
        best = .{ .body = id, .distance = hit.distance, .point = hit.point, .normal = hit.normal, .user = b.user };
    }
    var rigid = self.rigids.live.iterator(.{});
    while (rigid.next()) |i| {
        const hit = Rigid.rayCast(self.rigids.items[i], origin, direction) orelse continue;
        if (hit.distance > max_distance or (best != null and hit.distance >= best.?.distance)) continue;
        best = .{ .rigid = self.rigids.idAt(i), .distance = hit.distance, .point = hit.point, .normal = hit.normal, .user = self.rigids.items[i].user };
    }
    var meshes = self.meshes.live.iterator(.{});
    while (meshes.next()) |i| {
        const limit = if (best) |b| b.distance else max_distance;
        const hit = self.meshes.items[i].mesh.raycast(origin, direction, limit) orelse continue;
        best = .{ .mesh = self.meshes.idAt(i), .distance = hit.distance, .point = hit.point, .normal = hit.normal, .user = self.meshes.items[i].user };
    }
    return best;
}

/// Nearest solid surface along a ray: terrain, any box, or any rigid body except `ignore`.
/// Reports the surface's velocity at the hit so wheels can drive on moving platforms.
pub fn castRay(self: *const BoxWorld, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Physics.Rigid) ?Physics.SurfaceHit {
    return self.castRayImpl(origin, direction, max_distance, ignore, true);
}

/// Raycast bodies and static meshes without walking the terrain heightfield.
pub fn castRayObjects(self: *const BoxWorld, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Physics.Rigid) ?Physics.SurfaceHit {
    return self.castRayImpl(origin, direction, max_distance, ignore, false);
}

fn castRayImpl(self: *const BoxWorld, origin: Vec3, direction: Vec3, max_distance: f32, ignore: Physics.Rigid, include_ground: bool) ?Physics.SurfaceHit {
    var best: ?Physics.SurfaceHit = null;
    // Terrain: march in 5 cm steps, then bisect the crossing.
    const below = struct {
        fn f(world: *const BoxWorld, p: Vec3) bool {
            const g = world.ground.at(p) orelse return false;
            return p[1] < g.height;
        }
    }.f;
    if (include_ground) {
        var t: f32 = 0;
        if (!below(self, origin)) while (t < max_distance) {
            const next = @min(max_distance, t + 0.05);
            if (below(self, R.add(origin, R.scale(direction, next)))) {
                var lo = t;
                var hi = next;
                for (0..8) |_| {
                    const mid = (lo + hi) / 2;
                    if (below(self, R.add(origin, R.scale(direction, mid)))) hi = mid else lo = mid;
                }
                const point = R.add(origin, R.scale(direction, hi));
                best = .{ .distance = hi, .point = point, .normal = self.ground.sample(self.ground.context, point[0], point[2]).normal, .velocity = .{ 0, 0, 0 } };
                break;
            }
            t = next;
        };
    }
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.bodies.items[i];
        const hit = Physics.rayBox(origin, direction, b.position, b.half) orelse continue;
        if (hit.distance > max_distance or (best != null and hit.distance >= best.?.distance)) continue;
        best = .{ .distance = hit.distance, .point = hit.point, .normal = hit.normal, .velocity = b.velocity };
    }
    var rigid = self.rigids.live.iterator(.{});
    while (rigid.next()) |i| {
        if (self.rigids.idAt(i).eql(ignore)) continue;
        const r = self.rigids.items[i];
        const hit = Rigid.rayCast(r, origin, direction) orelse continue;
        if (hit.distance > max_distance or (best != null and hit.distance >= best.?.distance)) continue;
        best = .{ .distance = hit.distance, .point = hit.point, .normal = hit.normal, .velocity = r.pointVelocity(hit.point) };
    }
    var meshes = self.meshes.live.iterator(.{});
    while (meshes.next()) |i| {
        const limit = if (best) |b| b.distance else max_distance;
        const hit = self.meshes.items[i].mesh.raycast(origin, direction, limit) orelse continue;
        best = .{ .distance = hit.distance, .point = hit.point, .normal = hit.normal, .velocity = .{ 0, 0, 0 } };
    }
    return best;
}

pub fn moveCharacter(self: *BoxWorld, shape: Physics.Character, start: Vec3, displacement: Vec3, snap: bool) Physics.CharacterResult {
    var feet = start;
    // Sub-steps no longer than half the radius keep thin contacts from tunneling.
    const horizontal = @sqrt(displacement[0] * displacement[0] + displacement[2] * displacement[2]);
    // At least one pass, so a kinematic body moving into a standing character pushes it out.
    const steps: usize = @max(1, @as(usize, @intFromFloat(@min(64, @ceil(horizontal / (shape.radius * 0.5))))));
    for (0..steps) |_| {
        feet[0] += displacement[0] / @as(f32, @floatFromInt(steps));
        feet[2] += displacement[2] / @as(f32, @floatFromInt(steps));
        self.pushOut(shape, &feet);
    }
    var result: Physics.CharacterResult = .{ .feet = feet, .grounded = false, .hit_ceiling = false };
    const found = self.characterSupport(shape, feet);
    const support = found.height;
    const target = feet[1] + displacement[1];
    if (displacement[1] > 0) {
        const ceiling = self.characterCeiling(shape, feet);
        if (target + shape.height > ceiling) {
            result.feet[1] = @max(feet[1], ceiling - shape.height);
            result.hit_ceiling = true;
        } else result.feet[1] = target;
    } else result.feet[1] = target;
    // `snap` is the caller's decision (grounded and not jumping); platform carry may make displacement positive.
    if (result.feet[1] <= support or (snap and result.feet[1] - support <= shape.step)) {
        result.feet[1] = support;
        result.grounded = true;
        result.support = found.body;
    }
    return result;
}

/// Pushes the character's cylinder horizontally out of boxes it overlaps and nudges dynamic ones.
fn pushOut(self: *BoxWorld, shape: Physics.Character, feet: *Vec3) void {
    self.pushOutRigids(shape, feet);
    self.pushOutMeshes(shape, feet);
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = &self.bodies.items[i];
        const top = b.position[1] + b.half[1];
        const bottom = b.position[1] - b.half[1];
        // Boxes low enough to step onto, or entirely overhead, do not block.
        if (feet[1] + shape.step >= top or feet[1] + shape.height <= bottom) continue;
        const cx = std.math.clamp(feet[0], b.position[0] - b.half[0], b.position[0] + b.half[0]);
        const cz = std.math.clamp(feet[2], b.position[2] - b.half[2], b.position[2] + b.half[2]);
        var dx = feet[0] - cx;
        var dz = feet[2] - cz;
        var distance = @sqrt(dx * dx + dz * dz);
        if (distance >= shape.radius) continue;
        if (distance < 1e-5) {
            // Center inside the footprint: leave through the nearest face.
            const ox = b.half[0] - @abs(feet[0] - b.position[0]);
            const oz = b.half[2] - @abs(feet[2] - b.position[2]);
            if (ox < oz) {
                dx = if (feet[0] >= b.position[0]) 1 else -1;
                dz = 0;
                feet[0] += dx * ox;
            } else {
                dx = 0;
                dz = if (feet[2] >= b.position[2]) 1 else -1;
                feet[2] += dz * oz;
            }
            distance = 0;
        } else {
            dx /= distance;
            dz /= distance;
        }
        const depth = shape.radius - distance;
        feet[0] += dx * depth;
        feet[2] += dz * depth;
        if (b.inv_mass > 0) {
            // Walking into a prop shoves it along the contact normal, capped at the push speed.
            const along = -(b.velocity[0] * dx + b.velocity[2] * dz);
            if (along < shape.push) {
                b.velocity[0] -= dx * (shape.push - along) * @min(1, b.inv_mass);
                b.velocity[2] -= dz * (shape.push - along) * @min(1, b.inv_mass);
            }
        }
    }
}

/// Rigid bodies block the character like walls: the closest point on the oriented box to the
/// character's mid-height axis point pushes it out horizontally. Rigid bodies are not pushed back.
fn pushOutRigids(self: *BoxWorld, shape: Physics.Character, feet: *Vec3) void {
    var rigid = self.rigids.live.iterator(.{});
    while (rigid.next()) |i| {
        const r = self.rigids.items[i];
        const mid: Vec3 = .{ feet[0], feet[1] + shape.height / 2, feet[2] };
        var local = R.inverseRotate(r.orientation, R.sub(mid, r.position));
        for (0..3) |k| local[k] = std.math.clamp(local[k], -r.half[k], r.half[k]);
        const closest = r.toWorld(local);
        if (@abs(closest[1] - mid[1]) >= shape.height / 2 - shape.step / 2) continue;
        var dx = mid[0] - closest[0];
        var dz = mid[2] - closest[2];
        var distance = @sqrt(dx * dx + dz * dz);
        if (distance >= shape.radius) continue;
        if (distance < 1e-5) {
            // Inside: leave away from the body's center.
            dx = mid[0] - r.position[0];
            dz = mid[2] - r.position[2];
            const l = @max(1e-5, @sqrt(dx * dx + dz * dz));
            dx /= l;
            dz /= l;
            distance = 0;
            // Move to the box's footprint edge along that direction.
            const reach = r.half[0] + r.half[2];
            feet[0] = r.position[0] + dx * reach;
            feet[2] = r.position[2] + dz * reach;
            continue;
        }
        dx /= distance;
        dz /= distance;
        feet[0] += dx * (shape.radius - distance);
        feet[2] += dz * (shape.radius - distance);
    }
}

/// Steep mesh triangles (walls, trunks) push the character out horizontally; walkable ones
/// are floors handled by support. Tested at three heights on the character's axis.
fn pushOutMeshes(self: *BoxWorld, shape: Physics.Character, feet: *Vec3) void {
    var candidates: [64]u32 = undefined;
    var live = self.meshes.live.iterator(.{});
    while (live.next()) |i| {
        const mesh = &self.meshes.items[i].mesh;
        const lo: Vec3 = .{ feet[0] - shape.radius, feet[1] + shape.step, feet[2] - shape.radius };
        const hi: Vec3 = .{ feet[0] + shape.radius, feet[1] + shape.height, feet[2] + shape.radius };
        const n = mesh.overlap(lo, hi, &candidates);
        for (candidates[0..n]) |t| {
            const tri = mesh.triangles[t];
            if (tri.normal[1] >= Physics.walkable_normal_y) continue;
            for ([_]f32{ shape.step + 0.05, shape.height / 2, shape.height - 0.05 }) |h| {
                const p: Vec3 = .{ feet[0], feet[1] + h, feet[2] };
                const c = Physics.TriangleMesh.closestPoint(tri, p);
                var dx = p[0] - c[0];
                var dz = p[2] - c[2];
                var distance = @sqrt(dx * dx + dz * dz);
                if (distance >= shape.radius or @abs(p[1] - c[1]) > shape.radius) continue;
                if (distance < 1e-5) {
                    // On the plane: leave along the face normal's horizontal direction.
                    const l = @max(1e-5, @sqrt(tri.normal[0] * tri.normal[0] + tri.normal[2] * tri.normal[2]));
                    dx = tri.normal[0] / l;
                    dz = tri.normal[2] / l;
                    distance = 0;
                } else {
                    dx /= distance;
                    dz /= distance;
                }
                feet[0] += dx * (shape.radius - distance);
                feet[2] += dz * (shape.radius - distance);
            }
        }
    }
}

fn overlapsFootprint(shape: Physics.Character, feet: Vec3, b: BodyState) bool {
    const cx = std.math.clamp(feet[0], b.position[0] - b.half[0], b.position[0] + b.half[0]);
    const cz = std.math.clamp(feet[2], b.position[2] - b.half[2], b.position[2] + b.half[2]);
    return (feet[0] - cx) * (feet[0] - cx) + (feet[2] - cz) * (feet[2] - cz) < shape.radius * shape.radius;
}

/// Highest standable surface under the character: terrain (no body) or a box top within step reach.
fn characterSupport(self: *const BoxWorld, shape: Physics.Character, feet: Vec3) struct { height: f32, body: Physics.Body } {
    // In hollow space (a cave) the terrain overhead is not underfoot.
    var support = if (self.ground.at(.{ feet[0], feet[1] + 0.5, feet[2] })) |g| g.height else -std.math.inf(f32);
    var body: Physics.Body = .none;
    // Walkable mesh floors under the footprint (center and four points inside the radius).
    const r = shape.radius * 0.7;
    for ([_][2]f32{ .{ 0, 0 }, .{ r, 0 }, .{ -r, 0 }, .{ 0, r }, .{ 0, -r } }) |o| {
        if (self.meshFloor(.{ feet[0] + o[0], feet[1] + shape.step, feet[2] + o[1] }, shape.step + 60)) |floor| support = @max(support, floor);
    }
    // Rigid-body roofs are valid floors for characters in flight and on foot.
    var rigids = self.rigids.live.iterator(.{});
    while (rigids.next()) |i| {
        const rigid = self.rigids.items[i];
        for ([_][2]f32{ .{ 0, 0 }, .{ r, 0 }, .{ -r, 0 }, .{ 0, r }, .{ 0, -r } }) |o| {
            const ray_top = @max(feet[1] + shape.step + 0.1, rigid.position[1] + rigid.radius() + 0.1);
            const origin: Vec3 = .{ feet[0] + o[0], ray_top, feet[2] + o[1] };
            const hit = Rigid.rayCast(rigid, origin, .{ 0, -1, 0 }) orelse continue;
            if (hit.normal[1] >= Physics.walkable_normal_y and hit.point[1] <= feet[1] + shape.step and hit.point[1] > support) support = hit.point[1];
        }
    }
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.bodies.items[i];
        const top = b.position[1] + b.half[1];
        if (top <= feet[1] + shape.step and top > support and overlapsFootprint(shape, feet, b)) {
            support = top;
            body = self.bodies.idAt(i);
        }
    }
    return .{ .height = support, .body = body };
}

fn characterCeiling(self: *const BoxWorld, shape: Physics.Character, feet: Vec3) f32 {
    var ceiling = std.math.inf(f32);
    var live = self.bodies.live.iterator(.{});
    while (live.next()) |i| {
        const b = self.bodies.items[i];
        const bottom = b.position[1] - b.half[1];
        if (bottom >= feet[1] + shape.height - 0.01 and overlapsFootprint(shape, feet, b)) ceiling = @min(ceiling, bottom);
    }
    var meshes = self.meshes.live.iterator(.{});
    while (meshes.next()) |i| {
        const hit = self.meshes.items[i].mesh.raycast(.{ feet[0], feet[1] + shape.height - 0.05, feet[2] }, .{ 0, 1, 0 }, 50) orelse continue;
        ceiling = @min(ceiling, hit.point[1]);
    }
    var rigids = self.rigids.live.iterator(.{});
    while (rigids.next()) |i| {
        const rigid = self.rigids.items[i];
        const head = feet[1] + shape.height - 0.05;
        const ray_bottom = @min(head, rigid.position[1] - rigid.radius() - 0.1);
        const origin: Vec3 = .{ feet[0], ray_bottom, feet[2] };
        const hit = Rigid.rayCast(rigid, origin, .{ 0, 1, 0 }) orelse continue;
        if (hit.normal[1] < -Physics.walkable_normal_y and hit.point[1] >= head - 0.01) ceiling = @min(ceiling, hit.point[1]);
    }
    return ceiling;
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}

test "bodies fall, rest on the ground, stack, and stop sliding" {
    var physics = Physics.init(.{ .sample = flatGround });
    const a = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 3, 0 }, .velocity = .{ 2, 0, 0 } });
    const b = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0.9, 6, 0 } });
    for (0..240) |_| physics.step(1.0 / 60.0);
    const pa = physics.position(a).?;
    const pb = physics.position(b).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), pa[1], 0.01);
    try std.testing.expectEqual(@as(f32, 0), physics.velocity(a).?[0]);
    // b either stacked on a or settled beside it; it never interpenetrates or sinks.
    try std.testing.expect(pb[1] >= 0.49);
    const overlap_x = 1 - @abs(pb[0] - pa[0]);
    const overlap_y = 1 - @abs(pb[1] - pa[1]);
    try std.testing.expect(overlap_x <= 0.02 or overlap_y <= 0.02);
    try std.testing.expectError(error.InvalidBody, physics.createBody(.{ .half_extents = .{ 0, 1, 1 }, .position = .{ 0, 0, 0 } }));
}

test "raycast finds the nearest box face and respects ignore and range" {
    var physics = Physics.init(.{ .sample = flatGround });
    const near = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 1, 5 }, .motion = .static, .user = 7 });
    _ = try physics.createBody(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 1, 9 }, .motion = .static, .user = 8 });
    const hit = physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 20, .none).?;
    try std.testing.expectEqual(@as(u32, 7), hit.user);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), hit.distance, 0.0001);
    try std.testing.expectEqual(@as(f32, -1), hit.normal[2]);
    try std.testing.expectEqual(@as(u32, 8), physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 20, near).?.user);
    try std.testing.expect(physics.raycast(.{ 0, 1, 0 }, .{ 0, 0, 1 }, 4, .none) == null);
}

test "object-only raycast skips terrain and still hits bodies" {
    var physics = Physics.init(.{ .sample = flatGround });
    const body = try physics.createBody(.{ .half_extents = .{ 1, 1, 1 }, .position = .{ 0, 5, 0 }, .motion = .static });
    const ray_origin: Vec3 = .{ 0, 10, 0 };
    const down: Vec3 = .{ 0, -1, 0 };
    try std.testing.expectApproxEqAbs(@as(f32, 4), physics.castRay(ray_origin, down, 12, .none).?.distance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), physics.castRayObjects(ray_origin, down, 12, .none).?.distance, 0.001);
    physics.destroyBody(body);
    try std.testing.expect(physics.castRay(ray_origin, down, 12, .none) != null);
    try std.testing.expect(physics.castRayObjects(ray_origin, down, 12, .none) == null);
    physics.deinit();
}

test "character is blocked by static boxes, steps onto low ones, and pushes dynamic props" {
    var physics = Physics.init(.{ .sample = flatGround });
    const shape: Physics.Character = .{};
    _ = try physics.createBody(.{ .half_extents = .{ 0.5, 2, 0.5 }, .position = .{ 0, 2, 3 }, .motion = .static });
    var feet: Physics.Vec3 = .{ 0, 0, 0 };
    for (0..120) |_| feet = physics.moveCharacter(shape, feet, .{ 0, -0.1, 0.1 }, true).feet;
    try std.testing.expect(feet[2] <= 2.5 - shape.radius + 0.001);
    try std.testing.expectEqual(@as(f32, 0), feet[1]);
    // A 0.3 m ledge is within step height.
    _ = try physics.createBody(.{ .half_extents = .{ 2, 0.15, 2 }, .position = .{ 10, 0.15, 0 }, .motion = .static });
    feet = .{ 7, 0, 0 };
    var result: Physics.CharacterResult = undefined;
    // Ledge spans x ∈ [8, 12]; stop on it at x = 11.
    for (0..40) |_| {
        result = physics.moveCharacter(shape, feet, .{ 0.1, -0.05, 0 }, true);
        feet = result.feet;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), feet[1], 0.0001);
    try std.testing.expect(result.grounded);
    const prop = try physics.createBody(.{ .half_extents = .{ 0.4, 0.4, 0.4 }, .position = .{ -5, 0.4, 1 } });
    feet = .{ -5, 0, 0 };
    for (0..30) |_| {
        feet = physics.moveCharacter(shape, feet, .{ 0, 0, 0.05 }, true).feet;
        physics.step(1.0 / 60.0);
    }
    try std.testing.expect(physics.position(prop).?[2] > 1.2);
}

test "kinematic platforms carry props, push the character, and ignore gravity" {
    var physics = Physics.init(.{ .sample = flatGround });
    const shape: Physics.Character = .{};
    const lift = try physics.createBody(.{ .half_extents = .{ 1, 0.1, 1 }, .position = .{ 0, 0.1, 0 }, .motion = .kinematic });
    const crate = try physics.createBody(.{ .half_extents = .{ 0.3, 0.3, 0.3 }, .position = .{ 0.5, 0.5, 0 } });
    physics.setVelocity(lift, .{ 0, 1, 0 });
    for (0..120) |_| physics.step(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 2.1), physics.position(lift).?[1], 0.001);
    // The crate rides on top of the platform.
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), physics.position(crate).?[1], 0.02);
    // The character standing on the platform reports it as support.
    const on = physics.moveCharacter(shape, .{ -0.5, 2.2, 0 }, .{ 0, -0.1, 0 }, true);
    try std.testing.expect(on.grounded and on.support.eql(lift));
    // A door sliding into a still character pushes it out.
    const door = try physics.createBody(.{ .half_extents = .{ 1, 1, 0.1 }, .position = .{ 10, 1, 0 }, .motion = .kinematic });
    const pushed = physics.moveCharacter(shape, .{ 10.5, 0, 0.05 }, .{ 0, 0, 0 }, true);
    try std.testing.expect(@abs(pushed.feet[2]) >= 0.1 + shape.radius - 0.001);
    _ = door;
}

test "a tilted rigid box falls, settles flat, and pushes a crate" {
    var physics = Physics.init(.{ .sample = flatGround });
    const box = try physics.createRigid(.{ .half_extents = .{ 0.5, 0.25, 1 }, .position = .{ 0, 2, 0 }, .orientation = R.axisAngle(.{ 1, 0, 1 }, 0.5), .mass = 50 });
    for (0..300) |_| physics.step(1.0 / 60.0);
    const pose = physics.rigidPose(box).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), pose.position[1], 0.02);
    // Local up is world up again (it rests on its largest face).
    try std.testing.expect(R.rotate(pose.orientation, .{ 0, 1, 0 })[1] > 0.999);
    try std.testing.expect(R.length(physics.rigidVelocity(box).?.linear) < 0.05);

    // Sliding into a crate shoves it along.
    const crate = try physics.createBody(.{ .half_extents = .{ 0.4, 0.4, 0.4 }, .position = .{ 0, 0.4, 3 }, .mass = 10 });
    physics.setRigidState(box, pose, .{ 0, 0, 6 }, .{ 0, 0, 0 });
    for (0..90) |_| physics.step(1.0 / 60.0);
    try std.testing.expect(physics.position(crate).?[2] > 3.2);
    try std.testing.expect(physics.rigidPose(box).?.position[2] < physics.position(crate).?[2]);
}

test "rigid bodies stop at static walls and block the character; surface rays report motion" {
    var physics = Physics.init(.{ .sample = flatGround });
    _ = try physics.createBody(.{ .half_extents = .{ 3, 2, 0.2 }, .position = .{ 0, 2, 5 }, .motion = .static });
    const box = try physics.createRigid(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 0.5, 0 }, .linear = .{ 0, 0, 12 }, .mass = 20 });
    for (0..120) |_| physics.step(1.0 / 60.0);
    try std.testing.expect(physics.rigidPose(box).?.position[2] < 4.8 - 0.49);

    const pose = physics.rigidPose(box).?;
    const feet = physics.moveCharacter(.{}, .{ pose.position[0] - 2, 0, pose.position[2] }, .{ 3, 0, 0 }, true).feet;
    try std.testing.expect(feet[0] <= pose.position[0] - 0.5 - 0.3);

    const lift = try physics.createBody(.{ .half_extents = .{ 1, 0.1, 1 }, .position = .{ 20, 1, 0 }, .motion = .kinematic, .velocity = .{ 0, 2, 0 } });
    _ = lift;
    const hit = physics.castRay(.{ 20, 3, 0 }, .{ 0, -1, 0 }, 5, .none).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1.9), hit.distance, 0.0001);
    try std.testing.expectEqual(@as(f32, 2), hit.velocity[1]);
    const ground = physics.castRay(.{ -20, 1, 0 }, .{ 0, -1, 0 }, 5, .none).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1), ground.distance, 0.001);
}

test "oriented rigid bodies collide with one another and carry character floor and ceiling contacts" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    const a = try physics.createRigid(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 10, -1.5 }, .linear = .{ 0, 0, 4 }, .mass = 30 });
    const b = try physics.createRigid(.{ .half_extents = .{ 0.5, 0.5, 0.5 }, .position = .{ 0, 10, 1.5 }, .linear = .{ 0, 0, -4 }, .mass = 30 });
    for (0..45) |_| physics.step(1.0 / 60.0);
    const pa = physics.rigidPose(a).?.position;
    const pb = physics.rigidPose(b).?.position;
    try std.testing.expect(pb[2] - pa[2] >= 0.99);
    try std.testing.expect(@abs(physics.rigidVelocity(a).?.linear[2]) < 0.1);
    try std.testing.expect(@abs(physics.rigidVelocity(b).?.linear[2]) < 0.1);

    const platform = try physics.createRigid(.{ .half_extents = .{ 2, 0.5, 2 }, .position = .{ 8, 0.5, 0 }, .mass = 200 });
    for (0..60) |_| physics.step(1.0 / 60.0);
    const pose = physics.rigidPose(platform).?;
    const support = physics.moveCharacter(.{}, .{ 8, 1.2, 0 }, .{ 0, -0.5, 0 }, false);
    try std.testing.expect(support.grounded);
    try std.testing.expectApproxEqAbs(pose.position[1] + 0.5, support.feet[1], 0.02);
    const under = physics.moveCharacter(.{}, .{ 8, pose.position[1] - 0.5 - 1.8, 0 }, .{ 0, 1, 0 }, false);
    try std.testing.expect(under.hit_ceiling);
}

test "character climbs a mesh ramp, is stopped by a steep wall, and stands on an angled deck" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    const allocator = std.testing.allocator;
    const shape: Physics.Character = .{};
    // 15° ramp rising along +Z from z = 2 to z = 22, 4 m wide.
    const rise = 20 * @tan(@as(f32, 15.0) * std.math.pi / 180.0);
    const ramp = [_]Vec3{ .{ -2, 0, 2 }, .{ 2, 0, 2 }, .{ -2, rise, 22 }, .{ 2, rise, 22 } };
    _ = try physics.createMesh(allocator, &ramp, &.{ 0, 2, 1, 1, 2, 3 }, 7);
    var feet: Vec3 = .{ 0, 0, 0 };
    var grounded = false;
    for (0..300) |_| {
        const r = physics.moveCharacter(shape, feet, .{ 0, -0.1, 0.06 }, true);
        feet = r.feet;
        grounded = r.grounded;
    }
    try std.testing.expect(feet[2] > 16 and feet[2] < 22);
    // A cylinder on a slope rests on its uphill footprint sample, 0.7 r × tan 15° above center.
    const center_height = (feet[2] - 2) / 20 * rise;
    try std.testing.expectApproxEqAbs(center_height + shape.radius * 0.7 * rise / 20, feet[1], 0.01);
    try std.testing.expect(grounded);

    // An 80° wall (a steep quad) blocks walking along +X.
    const lean = 4 * @tan(@as(f32, 10.0) * std.math.pi / 180.0);
    const wall = [_]Vec3{ .{ 10, 0, -3 }, .{ 10, 0, 3 }, .{ 10 + lean, 4, -3 }, .{ 10 + lean, 4, 3 } };
    _ = try physics.createMesh(allocator, &wall, &.{ 0, 1, 2, 2, 1, 3 }, 8);
    feet = .{ 6, 0, 0 };
    for (0..120) |_| feet = physics.moveCharacter(shape, feet, .{ 0.08, -0.1, 0 }, true).feet;
    // The wall leans away; above step height (0.45 m) its face is at x = 10 + 0.45 · tan 10°.
    const face = 10 + (shape.step + 0.05) * lean / 4;
    try std.testing.expectApproxEqAbs(face - shape.radius, feet[0], 0.02);

    // A deck tilted 5° about Z, top surface around y = 3 near its center.
    const tilt = R.axisAngle(.{ 0, 0, 1 }, @as(f32, 5.0) * std.math.pi / 180.0);
    const deck = try physics.createBox(allocator, .{ 30, 2.8, 0 }, .{ 6, 0.2, 2 }, tilt, 9);
    feet = .{ 30, 3.5, 0 };
    for (0..30) |_| feet = physics.moveCharacter(shape, feet, .{ 0, -0.1, 0 }, true).feet;
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), feet[1], 0.05);
    // Walking toward the high end climbs the deck.
    for (0..40) |_| feet = physics.moveCharacter(shape, feet, .{ 0.1, -0.1, 0 }, true).feet;
    try std.testing.expect(feet[1] > 3.2);

    // Rays and picking see meshes; placement overlap does too.
    const hit = physics.raycast(.{ 30, 10, 0 }, .{ 0, -1, 0 }, 20, .none).?;
    try std.testing.expect(hit.mesh.eql(deck) and hit.user == 9);
    try std.testing.expect(physics.castRay(.{ 0, 10, 12 }, .{ 0, -1, 0 }, 20, .none).?.distance < 10);
    try std.testing.expect(physics.overlapsBox(.{ 30, 3, 0 }, .{ 0.5, 0.5, 0.5 }));
    physics.destroyMesh(deck);
    try std.testing.expect(!physics.overlapsBox(.{ 30, 3, 0 }, .{ 0.5, 0.5, 0.5 }));
}

test "crates rest on mesh floors and rigid bodies settle on a tilted mesh deck" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    const allocator = std.testing.allocator;
    const floor = [_]Vec3{ .{ -5, 3, -5 }, .{ 5, 3, -5 }, .{ -5, 3, 5 }, .{ 5, 3, 5 } };
    _ = try physics.createMesh(allocator, &floor, &.{ 0, 2, 1, 1, 2, 3 }, 1);
    const crate = try physics.createBody(.{ .half_extents = .{ 0.4, 0.4, 0.4 }, .position = .{ 0, 6, 0 } });
    const deck = try physics.createBox(allocator, .{ 20, 2, 0 }, .{ 4, 0.25, 3 }, R.axisAngle(.{ 1, 0, 0 }, 0.08), 2);
    _ = deck;
    const box = try physics.createRigid(.{ .half_extents = .{ 0.5, 0.3, 0.5 }, .position = .{ 20, 4, 0 }, .mass = 30 });
    for (0..240) |_| physics.step(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 3.4), physics.position(crate).?[1], 0.02);
    const pose = physics.rigidPose(box).?;
    // Resting on the deck top (y ≈ 2.25 at its center), not on the ground below.
    try std.testing.expect(pose.position[1] > 2.4 and pose.position[1] < 2.7);
    try std.testing.expect(R.length(physics.rigidVelocity(box).?.linear) < 0.2);
}
