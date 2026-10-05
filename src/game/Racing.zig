//! A seeded elevated sprint course for the fabricated hover racers. The circuit is a smooth
//! 3D road ribbon with two jump gaps, two charge pads, and eight ordered gates. The same route
//! data drives both the generated mesh and race timing, so checkpoints cannot drift from art.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Terrain = @import("../procedural/Terrain.zig");
const Mesh = @import("../render/Mesh.zig");
const V = Physics.Vec3;

pub const node_count = 8;
pub const samples_per_segment = 48;
pub const sample_count = node_count * samples_per_segment;
pub const gate_radius: f32 = 19;
pub const road_half_width: f32 = 8;
const origin_x: f32 = 0;
const origin_z: f32 = -150;

pub const Gate = struct { center: V, forward: V };
pub const TrackFrame = struct { center: V, tangent: V, up: V, radius: f32 = 0 };
pub const Course = struct {
    seed: u64,
    nodes: [node_count]V,
    gates: [node_count]Gate,

    pub fn init(seed: u64) Course {
        const offsets = [_][3]f32{
            .{ 0, 25, 80 },
            .{ 110, 28, 38 },
            .{ 150, 42, -70 },
            .{ 72, 58, -155 },
            .{ -48, 31, -166 },
            .{ -145, 35, -82 },
            .{ -142, 54, 28 },
            .{ -52, 71, 83 },
        };
        var nodes: [node_count]V = undefined;
        for (offsets, &nodes) |offset, *p| {
            const x = origin_x + offset[0];
            const z = origin_z + offset[2];
            p.* = .{ x, Terrain.surface(seed, x, z).height + offset[1], z };
        }
        var gates: [node_count]Gate = undefined;
        for (&gates, 0..) |*gate, i| {
            const before = nodes[(i + node_count - 1) % node_count];
            const after = nodes[(i + 1) % node_count];
            gate.* = .{ .center = nodes[i], .forward = normalize(sub(after, before)) };
        }
        return .{ .seed = seed, .nodes = nodes, .gates = gates };
    }

    pub fn point(self: Course, segment: usize, t_in: f32) V {
        const segment_index = segment % node_count;
        const t = std.math.clamp(t_in, 0, 1);
        if (segment_index == 2 and t >= 0.25 and t <= 0.75) {
            const loop = self.loopFrameAt((t - 0.25) * 2);
            return loop.center;
        }
        if (segment_index == 2 and t > 0.75) {
            const anchor = self.splinePoint(segment_index, 0.25);
            const end = self.splinePoint(segment_index, 1);
            return add(anchor, scale(sub(end, anchor), (t - 0.75) * 4));
        }
        return self.splinePoint(segment_index, t);
    }

    fn splinePoint(self: Course, segment_index: usize, t: f32) V {
        const p0 = self.nodes[(segment_index + node_count - 1) % node_count];
        const p1 = self.nodes[segment_index];
        const p2 = self.nodes[(segment_index + 1) % node_count];
        const p3 = self.nodes[(segment_index + 2) % node_count];
        const t2 = t * t;
        const t3 = t2 * t;
        var out: V = undefined;
        for (0..3) |axis| out[axis] = 0.5 * ((2 * p1[axis]) + (-p0[axis] + p2[axis]) * t + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t2 + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t3);
        return out;
    }

    fn loopFrameAt(self: Course, u_in: f32) TrackFrame {
        const u = std.math.clamp(u_in, 0, 1);
        const theta = u * 2 * std.math.pi;
        const anchor = self.splinePoint(2, 0.25);
        const tangent = normalize(sub(self.splinePoint(2, 0.251), self.splinePoint(2, 0.249)));
        const world_up: V = .{ 0, 1, 0 };
        const center = add(anchor, add(scale(tangent, loop_radius * @sin(theta)), .{ 0, loop_radius * (1 - @cos(theta)), 0 }));
        const forward = add(scale(tangent, @cos(theta)), scale(world_up, @sin(theta)));
        const up = add(scale(tangent, -@sin(theta)), scale(world_up, @cos(theta)));
        return .{ .center = center, .tangent = normalize(forward), .up = normalize(up), .radius = loop_radius };
    }

    /// Return the nearest loop frame while the racer is within the road's capture band.
    pub fn stuntFrame(self: Course, position: V) ?TrackFrame {
        var best: ?TrackFrame = null;
        var distance_sq: f32 = (road_half_width + 7) * (road_half_width + 7);
        for (0..samples_per_segment * 2 + 1) |i| {
            const frame = self.loopFrameAt(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples_per_segment * 2)));
            const delta = sub(frame.center, position);
            const d2 = dot(delta, delta);
            if (d2 < distance_sq) {
                best = frame;
                distance_sq = d2;
            }
        }
        return best;
    }

    pub fn padPosition(self: Course, pad: usize) V {
        return self.point(if (pad == 0) 1 else 5, if (pad == 0) 0.68 else 0.63);
    }

    pub fn onChargePad(self: Course, position: V) bool {
        for (0..2) |pad| {
            const p = self.padPosition(pad);
            const dx = position[0] - p[0];
            const dz = position[2] - p[2];
            const dy = position[1] - p[1];
            if (dx * dx + dz * dz < 11 * 11 and @abs(dy) < 12) return true;
        }
        return false;
    }

    /// Road ribbon, loop and luminous edge rails. The gaps at segments 3 and 7 are deliberate jumps.
    pub fn mesh(self: Course, allocator: std.mem.Allocator) !Mesh {
        var vertices: std.ArrayList(Mesh.Vertex) = .empty;
        errdefer vertices.deinit(allocator);
        var indices: std.ArrayList(u32) = .empty;
        errdefer indices.deinit(allocator);
        for (0..sample_count) |sample_index| {
            const seg = sample_index / samples_per_segment;
            const local = sample_index % samples_per_segment;
            const next_sample = (sample_index + 1) % sample_count;
            if ((seg == 3 and local >= 5 and local <= 7) or (seg == 7 and local >= 5 and local <= 7)) continue;
            const a = self.sample(sample_index);
            const b = self.sample(next_sample);
            const ta = normalize(sub(self.sample((sample_index + 1) % sample_count), self.sample((sample_index + sample_count - 1) % sample_count)));
            const tb = normalize(sub(self.sample((next_sample + 1) % sample_count), self.sample((next_sample + sample_count - 1) % sample_count)));
            const ua = self.frameAtSample(sample_index).up;
            const ub = self.frameAtSample(next_sample).up;
            const sa = normalize(cross(ua, ta));
            const sb = normalize(cross(ub, tb));
            const pa_l = add(a, scale(sa, -road_half_width));
            const pa_r = add(a, scale(sa, road_half_width));
            const pb_l = add(b, scale(sb, -road_half_width));
            const pb_r = add(b, scale(sb, road_half_width));
            const boost = (seg == 1 and local >= 7 and local <= 9) or (seg == 5 and local >= 6 and local <= 8);
            const road_color: [3]f32 = if (boost) .{ 0.13, 0.8, 1 } else .{ 0.16, 0.2, 0.25 };
            try quad(allocator, &vertices, &indices, pa_l, pb_l, pb_r, pa_r, road_color);
            // Luminous edge strips double as visual lane boundaries and guard rails.
            for ([_]f32{ -1, 1 }) |side| {
                const edge_a = add(a, scale(sa, side * (road_half_width - 0.28)));
                const edge_b = add(b, scale(sb, side * (road_half_width - 0.28)));
                const high_a = add(edge_a, scale(ua, 0.34));
                const high_b = add(edge_b, scale(ub, 0.34));
                try quad(allocator, &vertices, &indices, edge_a, high_a, high_b, edge_b, if (boost) .{ 0.05, 0.95, 1 } else .{ 0.08, 0.56, 0.74 });
            }
        }
        return .{ .vertices = try vertices.toOwnedSlice(allocator), .indices = try indices.toOwnedSlice(allocator) };
    }

    /// Install the race deck and edge rails as a static world collider, so hover probes ride the
    /// highway and jumps cross real gaps instead of an invisible terrain floor.
    pub fn createCollider(self: Course, allocator: std.mem.Allocator, physics: *Physics) !Physics.MeshCollider {
        const generated = try self.mesh(allocator);
        defer generated.deinit(allocator);
        const positions = try allocator.alloc(V, generated.vertices.len);
        defer allocator.free(positions);
        for (positions, generated.vertices) |*p, vertex| p.* = vertex.position;
        return physics.createMesh(allocator, positions, generated.indices, 0x52414345);
    }

    fn sample(self: Course, index: usize) V {
        const wrapped = index % sample_count;
        return self.point(wrapped / samples_per_segment, @as(f32, @floatFromInt(wrapped % samples_per_segment)) / samples_per_segment);
    }

    fn frameAtSample(self: Course, index: usize) TrackFrame {
        const wrapped = index % sample_count;
        const segment = wrapped / samples_per_segment;
        const local = @as(f32, @floatFromInt(wrapped % samples_per_segment)) / samples_per_segment;
        if (segment == 2 and local >= 0.25 and local <= 0.75) return self.loopFrameAt((local - 0.25) * 2);
        const tangent = normalize(sub(self.sample((index + 1) % sample_count), self.sample((index + sample_count - 1) % sample_count)));
        return .{ .center = self.sample(index), .tangent = tangent, .up = .{ 0, 1, 0 } };
    }
};

pub const loop_radius: f32 = 19;

pub const State = struct {
    gate: u8 = 0,
    active: bool = false,
    finished: bool = false,
    elapsed: f32 = 0,
    best: f32 = 0,
    previous: ?V = null,
    last_event: Event = .none,

    pub const Event = enum { none, started, checkpoint, finished };

    pub fn step(self: *State, course: Course, position: V, dt: f32) Event {
        self.last_event = .none;
        if (self.active) self.elapsed += dt;
        const expected = course.gates[self.gate];
        if (self.previous) |before| if (crossed(before, position, expected)) {
            if (!self.active) {
                self.active = true;
                self.finished = false;
                self.elapsed = 0;
                self.gate = 1;
                self.last_event = .started;
            } else if (@as(usize, self.gate) + 1 == node_count) {
                self.active = false;
                self.finished = true;
                if (self.best == 0 or self.elapsed < self.best) self.best = self.elapsed;
                self.gate = 0;
                self.last_event = .finished;
            } else {
                self.gate += 1;
                self.last_event = .checkpoint;
            }
        };
        self.previous = position;
        return self.last_event;
    }
};

fn crossed(before: V, after: V, gate: Gate) bool {
    const a = dot(sub(before, gate.center), gate.forward);
    const b = dot(sub(after, gate.center), gate.forward);
    if (a > 0 or b <= 0 or b - a < 0.001) return false;
    const t = -a / (b - a);
    const at = add(before, scale(sub(after, before), t));
    const delta = sub(at, gate.center);
    return dot(delta, delta) <= gate_radius * gate_radius;
}

fn quad(allocator: std.mem.Allocator, vertices: *std.ArrayList(Mesh.Vertex), indices: *std.ArrayList(u32), a: V, b: V, c: V, d: V, color: [3]f32) !void {
    const base: u32 = @intCast(vertices.items.len);
    const n = normalize(cross(sub(b, a), sub(c, a)));
    for ([_]V{ a, b, c, d }, 0..) |p, i| vertices.append(allocator, .{ .position = p, .normal = n, .uv = .{ if (i == 1 or i == 2) @as(f32, 1) else 0, if (i >= 2) @as(f32, 1) else 0 }, .color = color }) catch return error.OutOfMemory;
    try indices.appendSlice(allocator, &.{ base, base + 1, base + 2, base, base + 2, base + 3 });
}

fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn scale(a: V, s: f32) V {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: V, b: V) V {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn normalize(a: V) V {
    const length = @sqrt(dot(a, a));
    return if (length > 1e-5) scale(a, 1 / length) else .{ 0, 0, 1 };
}

test "race gate order starts, advances only through the expected gate, and records a lap" {
    const course = Course.init(42);
    var race: State = .{};
    const gate = course.gates[0];
    _ = race.step(course, sub(gate.center, scale(gate.forward, 5)), 1.0 / 60.0);
    try std.testing.expectEqual(State.Event.started, race.step(course, add(gate.center, scale(gate.forward, 5)), 1.0 / 60.0));
    try std.testing.expectEqual(@as(u8, 1), race.gate);
    const next = course.gates[1];
    _ = race.step(course, sub(next.center, scale(next.forward, 5)), 0.1);
    try std.testing.expectEqual(State.Event.checkpoint, race.step(course, add(next.center, scale(next.forward, 5)), 0.1));
    try std.testing.expect(race.elapsed >= 0.1);
}

test "seeded racecourse has a closed route, elevated jumps, boost pads, and render geometry" {
    const allocator = std.testing.allocator;
    const course = Course.init(77);
    try std.testing.expectApproxEqAbs(course.nodes[0][0], course.point(node_count, 0)[0], 0.001);
    try std.testing.expect(course.nodes[3][1] > course.nodes[0][1] + 15);
    try std.testing.expect(course.onChargePad(course.padPosition(0)));
    const mesh = try course.mesh(allocator);
    defer mesh.deinit(allocator);
    try std.testing.expect(mesh.vertices.len > 1000);
    try std.testing.expect(mesh.indices.len > mesh.vertices.len);
}

test "vertical loop closes smoothly and turns the track upside down" {
    const course = Course.init(77);
    const entry = course.point(2, 0.25);
    const exit = course.point(2, 0.75);
    try std.testing.expectApproxEqAbs(entry[0], exit[0], 0.001);
    try std.testing.expectApproxEqAbs(entry[1], exit[1], 0.001);
    try std.testing.expectApproxEqAbs(entry[2], exit[2], 0.001);
    const bottom = course.loopFrameAt(0);
    const top = course.loopFrameAt(0.5);
    try std.testing.expectApproxEqAbs(-1, top.up[1], 0.001);
    try std.testing.expectApproxEqAbs(2 * loop_radius, top.center[1] - bottom.center[1], 0.01);
    try std.testing.expect(course.stuntFrame(top.center) != null);
    const geometry = try course.mesh(std.testing.allocator);
    defer geometry.deinit(std.testing.allocator);
    try std.testing.expect(geometry.vertices.len > 3000);
}

test "raceway static collider is the first floor hit above the terrain" {
    const allocator = std.testing.allocator;
    const course = Course.init(77);
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    _ = try course.createCollider(allocator, &physics);
    const p = course.point(0, 0);
    const hit = physics.castRay(.{ p[0], p[1] + 8, p[2] }, .{ 0, -1, 0 }, 20, .none).?;
    try std.testing.expect(hit.distance < 9 and hit.distance > 6);
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}
