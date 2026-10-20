//! Starfall's traversal verbs adapted to metres/seconds and Heavy Water's fixed-step physics.
//! Each player owns every timer, resource and attachment; all motion passes through collision.
const std = @import("std");
const math = @import("mach").math;
const Physics = @import("../physics/Physics.zig");
const R = Physics.Rotation;
const V = Physics.Vec3;
const Camera = @import("../world/Camera.zig");
const Input = @import("../engine/Input.zig");
const Biome = @import("../procedural/Biome.zig");
const Player = @This();
pub const Mode = enum { walk, fly };
/// Held boost in free-fly or suit flight doubles the speed every this many seconds.
pub const boost_tier_seconds: f32 = 1.2;
/// Highest boost tier (speed x 2^tier). Terrain streaming, haze and f32 precision limit how far this
/// can go; raise it only as those do (see docs/plans/flight-speed.md).
pub const max_boost_tier: u32 = 3;
pub const Traversal = enum { grapple, hover_jet, flight, hoverboard, energy_skate };
pub const Motion = enum { idle, run, sprint, jump, long_jump, backflip, fall, roll, stomp, wall_slide, climb, hang, mantle, jet, hover, glide, dash, board, skate, grapple_zip, grapple_swing, swim };
pub const eye_height: f32 = 1.62;
pub const walk_speed: f32 = 5.8;
pub const sprint_speed: f32 = 10.8;
pub const jump_speed: f32 = 9.4;
pub const Water = struct { min: V, max: V };
/// Suit tuning from purchased upgrades (see `Progress`); the defaults are the base suit.
pub const Suit = struct {
    fuel_max: f32 = 240,
    /// Multiplies every fuel cost (jets, glide, dashes, boards).
    burn: f32 = 1,
    sprint: f32 = sprint_speed,
    stamina_regen: f32 = 20,
    grapple_range: f32 = 96,
};
/// What surrounds a body this step: authored water volumes, the ground it stands on, and the
/// river surface over it (null on dry land), all supplied by the caller.
pub const Environment = struct { water: []const Water = &.{}, ground: Biome.Kind = .grass, river: ?f32 = null };
/// River water deeper than this floats a walker; a swimmer keeps swimming down to `float_depth`.
pub const swim_depth: f32 = 0.95;
pub const float_depth: f32 = 0.5;
pub const Footing = struct { speed: f32 = 1, traction: f32 = 1 };

/// How the ground underfoot changes running: snow is slow and slides (less traction to start
/// and stop), marsh and sand drag, and wading water slows with its depth.
pub fn footing(ground: Biome.Kind, wading: f32) Footing {
    var f: Footing = switch (ground) {
        .grass, .rock => .{},
        .sand => .{ .speed = 0.9, .traction = 0.85 },
        .marsh => .{ .speed = 0.85, .traction = 0.8 },
        .snow => .{ .speed = 0.8, .traction = 0.45 },
    };
    if (wading > 0) {
        f.speed *= 1 - @min(wading, swim_depth) * 0.5;
        f.traction *= 0.8;
    }
    return f;
}
pub const Grapple = struct {
    mode: enum { ready, windup, zip, swing, cooldown } = .ready,
    point: V = @splat(0),
    normal: V = .{ 0, 1, 0 },
    length: f32 = 0,
    timer: f32 = 0,
    heat: f32 = 0,
};
feet: V = .{ 0, 0, 0 },
velocity: V = .{ 0, 0, 0 },
knockback: V = .{ 0, 0, 0 },
grounded: bool = false,
support: Physics.Body = .none,
mode: Mode = .walk,
shape: Physics.Character = .{},
traversal: Traversal = .grapple,
motion: Motion = .idle,
stamina: f32 = 100,
fuel: f32 = 240,
climb_energy: f32 = 100,
breath: f32 = 12,
hover_enabled: bool = false,
coyote: f32 = 0,
jump_buffer: f32 = 0,
previous_jump: bool = false,
jumped_since_ground: bool = false,
air_assist_engaged: bool = false,
tap_count: u8 = 0,
tap_timer: f32 = 0,
wall_lock: f32 = 0,
grab_cooldown: f32 = 0,
wall_charges: u8 = 2,
wall_normal: V = @splat(0),
ledge_top: V = @splat(0),
hang_timer: f32 = 0,
roll_timer: f32 = 0,
dash_timer: f32 = 0,
dash_cooldown: f32 = 0,
/// Dodge double-tap chain: up to four short boosts, grounded or airborne.
dodge_tap_window: f32 = 0,
dash_chain_timer: f32 = 0,
dash_chain_count: u8 = 0,
dash_direction: V = .{ 0, 0, 1 },
/// Forward plus three rapid dodge taps engages sustained, fuel-powered flight.
flight_tap_window: f32 = 0,
flight_tap_count: u8 = 0,
flight_engaged: bool = false,
/// Seconds boost has been held in powered flight. Every `boost_tier_seconds` adds a tier, and each
/// tier doubles the flight speed.
boost_hold: f32 = 0,
boost_timer: f32 = 0,
boost_cooldown: f32 = 0,
landing: f32 = 0,
long_jump_timer: f32 = 0,
backflip_timer: f32 = 0,
/// Brief landing pulse consumed by combat for a powered dive-kick impact.
energy_kick_timer: f32 = 0,
grapple: Grapple = .{},
suit: Suit = .{},
/// The ground underfoot and the depth of river water around the feet (0 when dry), as of the
/// last step.
ground: Biome.Kind = .grass,
wading: f32 = 0,

pub fn eye(self: Player) math.Vec3 {
    return math.vec3(self.feet[0], self.feet[1] + @min(eye_height, self.shape.height - 0.12), self.feet[2]);
}
pub fn cancelTraversal(self: *Player) void {
    const selected = self.traversal;
    const hover = self.hover_enabled;
    const stamina = self.stamina;
    const fuel = self.fuel;
    const energy = self.climb_energy;
    self.* = .{ .feet = self.feet, .mode = self.mode, .traversal = selected, .hover_enabled = hover, .stamina = stamina, .fuel = fuel, .climb_energy = energy, .suit = self.suit };
}
pub fn setMode(self: *Player, mode: Mode, camera: Camera) void {
    self.cancelTraversal();
    self.mode = mode;
    self.feet = .{ camera.position.x(), camera.position.y() - eye_height, camera.position.z() };
}
/// Leaves powered flight at the current character position, including from a chase camera.
pub fn exitFlight(self: *Player, camera: *Camera) void {
    self.mode = .walk;
    self.velocity = @splat(0);
    self.grounded = false;
    self.support = .none;
    self.flight_engaged = false;
    self.motion = .fall;
    camera.position = self.eye();
}
/// The current boost tier, 0 when boost is not held in flight.
pub fn boostTier(self: *const Player) u32 {
    return @min(max_boost_tier, @as(u32, @intFromFloat(self.boost_hold / boost_tier_seconds)));
}
fn boostScale(tier: u32) f32 {
    return @floatFromInt(@as(u32, 1) << @intCast(tier));
}
/// How fast velocity may change toward a flight target: never slower than `base`, and scaled to the
/// speeds involved so a tier change (or letting go) settles in about a second at any tier.
fn flightAccel(self: *const Player, base: f32, target_speed: f32) f32 {
    return @max(base, 1.2 * @max(target_speed, R.length(self.velocity)));
}
fn approach(current: V, target: V, amount: f32) V {
    const delta = R.sub(target, current);
    const length = R.length(delta);
    return if (length <= amount or length < 0.00001) target else R.add(current, R.scale(delta, amount / length));
}
fn horizontal(v: V) V {
    return .{ v[0], 0, v[2] };
}
fn decay(value: *f32, dt: f32) void {
    value.* = @max(0, value.* - dt);
}
fn clearAt(self: *const Player, physics: *const Physics, feet: V, height: f32) bool {
    return !physics.overlapsBox(R.add(feet, .{ 0, height / 2 + 0.03, 0 }), .{ self.shape.radius * 0.95, height / 2 - 0.04, self.shape.radius * 0.95 });
}
fn wall(self: *const Player, physics: *const Physics, direction: V) ?Physics.SurfaceHit {
    if (R.length(direction) < 0.5) return null;
    const hit = physics.castRay(R.add(self.feet, .{ 0, 0.95, 0 }), direction, self.shape.radius + 0.38, .none) orelse return null;
    return if (@abs(hit.normal[1]) < 0.3) hit else null;
}
fn ledge(self: *const Player, physics: *const Physics, normal: V) ?V {
    const inward = R.scale(normal, -1);
    const high = R.add(self.feet, .{ 0, 2.2, 0 });
    if (physics.castRay(high, inward, 0.8, .none) != null) return null;
    const above = R.add(high, R.scale(inward, 0.8));
    const hit = physics.castRay(above, .{ 0, -1, 0 }, 1.8, .none) orelse return null;
    if (hit.normal[1] < Physics.walkable_normal_y or hit.point[1] < self.feet[1] + 0.5) return null;
    const top = R.add(hit.point, .{ 0, 0.02, 0 });
    return if (self.clearAt(physics, top, 1.8)) top else null;
}
fn releaseGrapple(self: *Player) void {
    self.grapple.mode = .cooldown;
    self.grapple.timer = 0.32;
}
fn jump(self: *Player, speed: f32) void {
    self.velocity[1] = speed;
    self.grounded = false;
    self.jumped_since_ground = true;
    self.support = .none;
    self.jump_buffer = 0;
    self.coyote = 0;
    self.motion = .jump;
}
fn wallJump(self: *Player) void {
    self.jump(9.2);
    const push = R.scale(self.wall_normal, 8);
    self.velocity[0] = push[0];
    self.velocity[2] = push[2];
    self.wall_lock = 0.16;
    self.grab_cooldown = 0.22;
    self.wall_charges -|= 1;
}

pub fn step(self: *Player, physics: *Physics, camera: *Camera, input: Input, dt: f32) void {
    self.stepIn(physics, camera, input, .{}, dt);
}
pub fn stepIn(self: *Player, physics: *Physics, camera: *Camera, input: Input, env: Environment, dt: f32) void {
    if (dt <= 0) return;
    if (self.mode == .fly) {
        // The traversal button doubles as a reliable landing control while this mode is active.
        // Keyboard WALK/FLY also exits through Sandbox.Actions.toggle_mode.
        if (input.cycle_mode) {
            self.exitFlight(camera);
            return;
        }
        // Powered flight keeps the ranger visible and collision-aware. The camera aim pitches
        // the whole flight vector so forward flight reads like a superhero dive, not a hover.
        const look = camera.forward();
        const forward: V = .{ look.x(), look.y(), look.z() };
        const right: V = .{ @cos(camera.yaw), 0, -@sin(camera.yaw) };
        const vertical = std.math.clamp(input.up + @as(f32, @floatFromInt(@intFromBool(input.jump))) - @as(f32, @floatFromInt(@intFromBool(input.dodge_held))), -1, 1);
        const raw = R.add(R.add(R.scale(forward, input.forward), R.scale(right, input.right)), .{ 0, vertical, 0 });
        const magnitude = R.length(raw);
        const direction = if (magnitude > 0.05) R.scale(raw, 1 / magnitude) else R.scale(forward, 0.72);
        self.boost_hold = if (input.fast) self.boost_hold + dt else 0;
        const speed: f32 = if (input.fast) 55 * boostScale(self.boostTier()) else 28;
        self.velocity = approach(self.velocity, R.scale(direction, speed), self.flightAccel(if (input.fast) 56 else 38, speed) * dt);
        self.grounded = false;
        self.support = .none;
        self.motion = .jet;
        self.move(physics, dt);
        camera.position = self.eye();
        self.previous_jump = input.jump;
        return;
    }
    if (!self.flight_engaged) self.boost_hold = 0;
    if (self.grounded) {
        self.jumped_since_ground = false;
        self.air_assist_engaged = false;
    }
    const pressed = input.jump_pressed or (input.jump and !self.previous_jump);
    const released = !input.jump and self.previous_jump;
    self.previous_jump = input.jump;
    for ([_]*f32{ &self.jump_buffer, &self.coyote, &self.wall_lock, &self.grab_cooldown, &self.roll_timer, &self.dash_timer, &self.dash_cooldown, &self.dodge_tap_window, &self.dash_chain_timer, &self.boost_timer, &self.boost_cooldown, &self.tap_timer, &self.flight_tap_window, &self.landing, &self.long_jump_timer, &self.backflip_timer, &self.energy_kick_timer, &self.grapple.timer }) |timer| decay(timer, dt);
    if (self.dash_chain_timer == 0) self.dash_chain_count = 0;
    self.grapple.heat = @max(0, self.grapple.heat - 24 * dt);
    if (self.grapple.mode == .cooldown and self.grapple.timer == 0) self.grapple.mode = .ready;
    if (input.cycle_mode) {
        self.traversal = @enumFromInt(@intFromEnum(self.traversal) +% 1);
        self.flight_engaged = false;
        self.air_assist_engaged = false;
        self.flight_tap_count = 0;
        self.releaseGrapple();
        self.motion = .fall;
        self.roll_timer = 0;
        self.dash_timer = 0;
    }
    if (pressed) {
        self.jump_buffer = 0.18;
        self.tap_count = if (self.tap_timer > 0) self.tap_count + 1 else 1;
        self.tap_timer = 0.48;
        if (self.tap_count == 3) {
            self.hover_enabled = !self.hover_enabled;
            self.tap_count = 0;
            self.tap_timer = 0;
        }
    }
    const forward: V = .{ @sin(camera.yaw), 0, @cos(camera.yaw) };
    const right: V = .{ @cos(camera.yaw), 0, -@sin(camera.yaw) };
    const raw = R.add(R.scale(forward, input.forward), R.scale(right, input.right));
    const strength = @min(1, R.length(raw));
    const wish = R.normalize(raw);
    var flight_started = false;
    if (input.dodge and input.forward >= 0.65 and !pressed and !self.flight_engaged) {
        self.flight_tap_count = if (self.flight_tap_window > 0) self.flight_tap_count + 1 else 1;
        self.flight_tap_window = 0.92;
        if (self.flight_tap_count >= 3) {
            self.flight_tap_count = 0;
            self.flight_tap_window = 0;
            self.traversal = .flight;
            self.flight_engaged = true;
            self.grounded = false;
            self.velocity = R.add(R.scale(forward, 32), .{ 0, 12, 0 });
            self.dash_timer = 0;
            self.dash_chain_timer = 0;
            self.dash_chain_count = 0;
            self.releaseGrapple();
            flight_started = true;
        }
    } else if (input.dodge and !self.flight_engaged) {
        self.flight_tap_count = 0;
        self.flight_tap_window = 0;
    }
    var dash_started = flight_started;
    var dash_burst_started = false;
    if (input.dodge and !flight_started) {
        if (self.dodge_tap_window > 0 and self.dash_chain_count < 4) {
            self.dodge_tap_window = 0;
            self.dash_chain_count += 1;
            self.dash_chain_timer = 1.35;
            self.dash_timer = 0.2;
            self.roll_timer = 0;
            self.shape.height = 1.8;
            self.dash_direction = if (strength > 0.1) wish else forward;
            dash_started = true;
            dash_burst_started = true;
        } else if (self.dash_chain_count < 4) {
            self.dodge_tap_window = 0.42;
        }
    }
    var h = horizontal(self.velocity);
    const speed = R.length(h);
    const skating = self.traversal == .energy_skate;
    const board = self.traversal == .hoverboard or skating;
    const was_grounded = self.grounded;
    if (self.grounded) {
        self.coyote = 0.16;
        self.wall_charges = 2;
        if (!self.flight_engaged) self.fuel = @min(self.suit.fuel_max, self.fuel + 12 * dt);
        self.climb_energy = @min(100, self.climb_energy + 13 * dt);
    }
    const sprinting = input.fast and strength > 0.82 and self.stamina > 0;
    self.stamina = std.math.clamp(self.stamina + (if (sprinting and self.grounded) @as(f32, -15) else self.suit.stamina_regen) * dt, 0, 100);
    self.ground = env.ground;
    self.wading = 0;
    // Authored water volumes and rivers use the same collision controller as dry traversal.
    var water_top: ?f32 = null;
    for (env.water) |water| {
        if (self.feet[0] < water.min[0] or self.feet[0] > water.max[0] or self.feet[2] < water.min[2] or self.feet[2] > water.max[2] or self.feet[1] < water.min[1] or self.feet[1] > water.max[1] - 0.3) continue;
        water_top = water.max[1];
        break;
    }
    if (water_top == null) if (env.river) |level| {
        const depth = level - self.feet[1];
        if (depth > (if (self.motion == .swim) float_depth else swim_depth)) water_top = level else if (depth > 0.05) {
            self.wading = depth;
        }
    };
    if (water_top) |top| {
        self.wading = top - self.feet[1];
        self.motion = .swim;
        self.flight_engaged = false;
        self.air_assist_engaged = false;
        self.flight_tap_count = 0;
        self.dash_timer = 0;
        self.releaseGrapple();
        self.grounded = false;
        const submerged = self.feet[1] + 1.35 < top;
        self.breath = std.math.clamp(self.breath + (if (submerged) @as(f32, -1) else 4) * dt, 0, 12);
        h = approach(h, R.scale(wish, if (input.fast) 5 else 3.5), 14 * dt);
        const vy = if (input.jump or self.breath < 2) @as(f32, 4) else if (input.dodge_held) @as(f32, -3) else std.math.clamp((top - 0.72 - self.feet[1]) * 3, -2.5, 3);
        self.velocity = approach(self.velocity, .{ h[0], vy, h[2] }, 18 * dt);
        self.move(physics, dt);
        camera.position = self.eye();
        return;
    }
    self.breath = @min(12, self.breath + 4 * dt);
    if (self.motion == .swim) self.motion = .fall;
    const probe_direction = if (self.motion == .climb or self.motion == .hang) R.scale(self.wall_normal, -1) else if (strength > 0.1) wish else forward;
    const contact = self.wall(physics, probe_direction);
    if (contact) |hit| self.wall_normal = R.normalize(horizontal(hit.normal));
    const pushing = contact != null and R.dot(wish, R.scale(self.wall_normal, -1)) > 0.35;
    var jumped_this_step = false;
    var controlled = false;
    if (self.motion == .hang) {
        self.hang_timer += dt;
        self.stamina = @max(0, self.stamina - 32 * dt);
        if (self.jump_buffer > 0) {
            self.wallJump();
            jumped_this_step = true;
        } else if (input.mantle and self.clearAt(physics, self.ledge_top, 1.8)) {
            self.motion = .mantle;
            self.velocity = .{ 0, 8, 0 };
        } else if (input.dodge or input.forward < -0.35 or self.stamina == 0 or self.hang_timer > 2.5 or contact == null) {
            self.motion = .fall;
            self.grab_cooldown = 0.22;
        } else {
            self.velocity = @splat(0);
            camera.position = self.eye();
            return;
        }
    }
    if (self.motion == .mantle) {
        // Lift clear of the edge before advancing onto its top, through collision throughout.
        if (self.feet[1] < self.ledge_top[1] + 0.06) self.velocity = .{ 0, 8, 0 } else {
            h = R.scale(R.normalize(horizontal(R.sub(self.ledge_top, self.feet))), 4);
            self.velocity = .{ h[0], 0, h[2] };
            if (R.length(horizontal(R.sub(self.ledge_top, self.feet))) < 0.15) {
                self.motion = .fall;
                self.grab_cooldown = 0.22;
            }
        }
        controlled = true;
    } else if (self.motion == .climb) {
        if (self.jump_buffer > 0 and self.wall_charges > 0) {
            self.wallJump();
            jumped_this_step = true;
        } else if (input.dodge or self.climb_energy <= 0 or contact == null) {
            self.motion = .fall;
            self.grab_cooldown = 0.22;
            if (contact == null) {
                self.jump(5.5);
                jumped_this_step = true;
                h = R.scale(self.wall_normal, -3);
                self.velocity[0] = h[0];
                self.velocity[2] = h[2];
            }
        } else {
            self.climb_energy = @max(0, self.climb_energy - 6.2 * dt);
            const lateral = R.cross(.{ 0, 1, 0 }, self.wall_normal);
            self.velocity = R.add(R.scale(lateral, -input.right * 2.8), R.scale(self.wall_normal, -0.6));
            self.velocity[1] = input.forward * 3.8;
            self.grounded = false;
            controlled = true;
            if (input.forward > 0) if (self.ledge(physics, self.wall_normal)) |top| {
                self.ledge_top = top;
                self.motion = .mantle;
            };
        }
    } else if (!board and self.grab_cooldown == 0 and self.grapple.mode != .zip and self.grapple.mode != .swing and self.motion != .stomp) {
        if (pushing and input.mantle and !self.grounded and self.velocity[1] <= 0) {
            if (self.ledge(physics, self.wall_normal)) |top| {
                self.ledge_top = top;
                self.motion = .hang;
                self.hang_timer = 0;
                self.velocity = @splat(0);
                controlled = true;
            }
        } else if (pushing and !self.grounded and self.climb_energy > 7) {
            // Starfall climbs on any push; here a climb starts from a jump into the face,
            // so walking into a closed door or crate row is blocked rather than scaled.
            self.motion = .climb;
            self.velocity = @splat(0);
            self.grounded = false;
            controlled = true;
        }
    }
    if (!controlled and self.motion != .hang and self.motion != .climb) {
        if (self.jump_buffer > 0 and contact != null and !self.grounded and self.wall_charges > 0 and self.grab_cooldown == 0) {
            self.wallJump();
            jumped_this_step = true;
        } else if (self.jump_buffer > 0 and self.coyote > 0) {
            const backflip = self.grounded and input.forward < -0.35 and !board;
            const long_jump = self.grounded and input.forward > 0.35 and strength > 0.35 and (input.fast or input.dodge or input.dodge_held) and !board;
            self.jump(jump_speed * (if (backflip) @as(f32, 1.1) else if (long_jump) @as(f32, 1.12) else if (skating) @as(f32, 1.52) else if (board) @as(f32, 1.32) else 1));
            jumped_this_step = true;
            if (backflip) {
                const flip_speed: f32 = if (input.dodge or input.dodge_held) 9 else 5;
                self.velocity[0] = wish[0] * flip_speed;
                self.velocity[2] = wish[2] * flip_speed;
                self.motion = .backflip;
                self.backflip_timer = 0.72;
            }
            if (long_jump) {
                const launch = if (strength > 0.1) wish else forward;
                const launch_speed: f32 = if (input.dodge or input.dodge_held) 23 else 17;
                self.velocity[0] = launch[0] * launch_speed;
                self.velocity[2] = launch[2] * launch_speed;
                self.motion = .long_jump;
                self.long_jump_timer = 0.68;
            }
            // Dash+jump in the same beat becomes one committed launch, rather than a ground
            // roll that overwrites the jump pose. The dash burst preserves the flip/leap motion.
            if (input.dodge and (backflip or long_jump)) {
                self.dash_direction = if (strength > 0.1) wish else forward;
                self.dash_timer = @max(self.dash_timer, 0.14);
                dash_started = true;
            }
        }
        h = horizontal(self.velocity);
        if (input.dodge and !dash_started) {
            if (self.grounded and board and self.boost_cooldown == 0) {
                self.boost_timer = 0.72;
                self.boost_cooldown = 1;
                h = R.scale(if (strength > 0.1) wish else forward, 22);
            } else if (self.grounded and !board and self.stamina >= 5) {
                self.roll_timer = @max(self.roll_timer, 0.42);
                self.stamina -= 5;
                h = R.scale(if (strength > 0.1) wish else if (speed > 1) R.normalize(h) else forward, @max(speed, 11));
            } else if (!self.grounded and self.dash_timer == 0) {
                // An air tap is a short evasion; double tap again during it for a full boost.
                self.dash_direction = if (strength > 0.1) wish else forward;
                self.dash_timer = 0.12;
            }
        }
        if (input.stomp and !self.grounded) {
            self.motion = .stomp;
            self.velocity[1] = -22;
            self.flight_engaged = false;
            self.air_assist_engaged = false;
            self.releaseGrapple();
        }
        const skate_speed: f32 = if (sprinting) 23 else 16;
        const base_speed = if (skating) skate_speed else if (sprinting) self.suit.sprint else walk_speed;
        const board_scale: f32 = if (board and !skating) 1.65 else 1;
        const boost_scale: f32 = if (self.boost_timer > 0) (if (skating) @as(f32, 1.5) else 2.35) else 1;
        var target = R.scale(wish, base_speed * strength * board_scale * boost_scale);
        var acceleration: f32 = if (self.grounded) (if (strength > 0.05) @as(f32, 45) else 55) else (if (strength > 0.05) @as(f32, 12) else 2);
        if (self.grounded and !board) {
            const f = footing(self.ground, self.wading);
            target = R.scale(target, f.speed);
            acceleration *= f.traction;
        } else if (board and self.grounded and self.ground == .snow) target = R.scale(target, 1.15);
        if (self.wall_lock > 0 or self.grab_cooldown > 0) acceleration *= 0.22;
        if (self.roll_timer > 0) {
            self.motion = .roll;
            self.shape.height = 0.95;
            target = R.scale(R.normalize(R.add(R.normalize(h), R.scale(wish, 0.34))), @max(0, R.length(h) - 6 * dt));
            acceleration = 16;
        } else if (self.clearAt(physics, self.feet, 1.8)) self.shape.height = 1.8;
        if (board) {
            if (strength < 0.05) {
                target = h;
                acceleration = 4;
                target = R.scale(target, @exp(-0.4 * dt));
            }
            if (!self.grounded and strength > 0.05) target = R.scale(R.normalize(R.add(R.scale(R.normalize(h), 0.8), R.scale(wish, 0.2))), @max(R.length(h), R.length(target)));
        }
        h = approach(h, target, acceleration * dt);
        self.velocity[0] = h[0];
        self.velocity[2] = h[2];
        if (released and self.velocity[1] > 3.5) self.velocity[1] = 3.5;
        if (!self.grounded) {
            const gravity: f32 = -15 * (if (self.velocity[1] < 0) @as(f32, 1.35) else 1) * (if (@abs(self.velocity[1]) < 1) @as(f32, 0.55) else 1) * (if (board) @as(f32, 0.42) else 1);
            self.velocity[1] = @max(-35, self.velocity[1] + gravity * dt);
        } else self.velocity[1] = Physics.gravity * dt;
        if (self.motion != .stomp and self.roll_timer == 0 and self.dash_timer == 0) self.motion = if (self.grounded) (if (skating) .skate else if (board) .board else if (strength < 0.05) .idle else if (sprinting) .sprint else .run) else if (self.backflip_timer > 0) .backflip else if (self.long_jump_timer > 0) .long_jump else if (self.velocity[1] > 0) .jump else .fall;
        if (contact != null and pushing and !self.grounded and self.velocity[1] < 0 and self.motion != .stomp and self.grab_cooldown == 0) {
            self.velocity[1] = @max(self.velocity[1], if (self.stamina > 0) @as(f32, -3.5) else -5);
            self.stamina = @max(0, self.stamina - 28 * dt);
            self.motion = .wall_slide;
        }
        if (pressed and !jumped_this_step and self.jumped_since_ground and !self.grounded and self.fuel > 0 and self.motion != .stomp and self.wall_lock == 0 and !self.flight_engaged) {
            self.air_assist_engaged = true;
        }
        if (!input.jump and !pressed) self.air_assist_engaged = false;
        if (self.air_assist_engaged and (input.jump or pressed) and !self.grounded and self.fuel > 0 and self.motion != .stomp and self.wall_lock == 0 and !self.flight_engaged) {
            switch (self.traversal) {
                .grapple, .hover_jet => {
                    self.velocity[1] = if (self.hover_enabled) self.velocity[1] * @exp(-7.5 * dt) else @min(7, self.velocity[1] + 26 * dt);
                    self.fuel = @max(0, self.fuel - 2.5 * self.suit.burn * dt);
                    self.motion = if (self.hover_enabled) .hover else .jet;
                },
                .flight => {
                    if (self.hover_enabled) {
                        self.velocity[1] *= @exp(-8.5 * dt);
                        self.motion = .hover;
                    } else if (input.fast) {
                        self.velocity = R.add(R.scale(forward, 16), .{ 0, @min(5, self.velocity[1] + 22 * dt), 0 });
                        self.motion = .jet;
                    } else {
                        self.velocity[1] = @max(-3.5, self.velocity[1]);
                        self.motion = .glide;
                    }
                    self.fuel = @max(0, self.fuel - (if (input.fast) @as(f32, 2.5) else 1) * self.suit.burn * dt);
                },
                .hoverboard => {
                    self.velocity = R.add(R.scale(if (strength > 0.1) wish else forward, if (input.fast) 20 else 14), .{ 0, @min(6, self.velocity[1] + 23 * dt), 0 });
                    self.fuel = @max(0, self.fuel - 2 * self.suit.burn * dt);
                    self.motion = .board;
                },
                .energy_skate => {
                    self.velocity[1] = @min(7, self.velocity[1] + 28 * dt);
                    self.fuel = @max(0, self.fuel - 8 * self.suit.burn * dt);
                    self.motion = .skate;
                },
            }
        }
        if (self.flight_engaged) {
            if (self.fuel <= 0) {
                self.flight_engaged = false;
            } else {
                const view = camera.forward();
                const flight_forward: V = .{ view.x(), view.y(), view.z() };
                const flight_right = right;
                const vertical = std.math.clamp(input.up + @as(f32, @floatFromInt(@intFromBool(input.jump))), -1, 1);
                const flight_raw = R.add(R.add(R.scale(flight_forward, input.forward), R.scale(flight_right, input.right)), .{ 0, vertical, 0 });
                const flight_length = R.length(flight_raw);
                const flight_strength = @min(1, flight_length);
                const flight_dir = if (flight_length > 0.05) R.scale(flight_raw, 1 / flight_length) else @as(V, .{ 0, 0, 0 });
                self.boost_hold = if (input.fast and flight_strength >= 0.05) self.boost_hold + dt else 0;
                const flight_speed: f32 = if (input.fast) 52 * boostScale(self.boostTier()) else if (input.forward < -0.1) 18 else 32;
                const target_velocity = R.scale(flight_dir, flight_speed * flight_strength);
                self.velocity = approach(self.velocity, target_velocity, self.flightAccel(if (input.fast) 44 else 32, flight_speed * flight_strength) * dt);
                self.grounded = false;
                self.motion = .jet;
                const burn: f32 = if (flight_strength < 0.05) 1.2 else if (input.fast) 6 else 3.2;
                self.fuel = @max(0, self.fuel - burn * self.suit.burn * dt);
            }
        }
        if (dash_burst_started and self.flight_engaged) self.fuel = @max(0, self.fuel - 18 * self.suit.burn);
        if (self.dash_timer > 0) {
            const dash_speed: f32 = if (self.long_jump_timer > 0) 25 else if (self.backflip_timer > 0) 9 else if (self.traversal == .flight and self.flight_engaged) 76 else 42;
            self.velocity = R.add(R.scale(self.dash_direction, dash_speed), .{ 0, self.velocity[1], 0 });
            if (self.long_jump_timer <= 0 and self.backflip_timer <= 0) self.motion = .dash;
        }
        if (board and self.velocity[1] < 0) if (physics.castRay(R.add(self.feet, .{ 0, 0.2, 0 }), .{ 0, -1, 0 }, 3, .none)) |hit| {
            self.velocity[1] = @max(self.velocity[1], -@max(2, hit.distance * 4));
        };
    }
    if (input.grapple and self.traversal == .grapple) {
        if (self.grapple.mode == .zip or self.grapple.mode == .swing or self.grapple.mode == .windup) self.releaseGrapple() else if (self.grapple.mode == .ready and self.grapple.heat <= 86) {
            const f = camera.forward();
            const eyes = self.eye();
            if (physics.raycast(.{ eyes.x(), eyes.y(), eyes.z() }, .{ f.x(), f.y(), f.z() }, self.suit.grapple_range, .none)) |hit| {
                // Static anchors only: a removed bridge is detected again before applying force.
                if (hit.rigid.eql(.none) and hit.body.eql(.none) and hit.distance > 3) {
                    self.grapple.point = hit.point;
                    self.grapple.normal = hit.normal;
                    self.grapple.length = hit.distance;
                    self.grapple.heat += 14;
                    self.grapple.mode = .windup;
                    self.grapple.timer = 0.14;
                }
            }
        }
    }
    if (self.grapple.mode == .windup and self.grapple.timer == 0) self.grapple.mode = if (self.grapple.point[1] > self.feet[1] + 8 and self.grapple.length > 20 and !input.fast) .swing else .zip;
    if (self.grapple.mode == .zip or self.grapple.mode == .swing) {
        const delta = R.sub(self.grapple.point, R.add(self.feet, .{ 0, 1, 0 }));
        const distance = R.length(delta);
        const dir = R.normalize(delta);
        const surface = physics.castRay(R.add(self.grapple.point, R.scale(self.grapple.normal, 0.2)), R.scale(self.grapple.normal, -1), 0.4, .none);
        const obstruction = physics.castRay(R.add(self.feet, .{ 0, 1, 0 }), dir, @max(0, distance - 0.5), .none);
        if (pressed or input.dodge or distance < 1.4 or surface == null or obstruction != null) self.releaseGrapple() else {
            self.grounded = false;
            self.roll_timer = 0;
            if (self.grapple.mode == .zip) {
                self.velocity = R.scale(dir, @min(26, distance * 5));
                self.motion = .grapple_zip;
            } else {
                const radial = R.dot(self.velocity, dir);
                const correction = std.math.clamp((distance - self.grapple.length) * 24 - radial * 4.8, -20, 35);
                self.velocity = R.add(self.velocity, R.scale(R.add(R.scale(dir, correction), R.scale(wish, 16)), dt));
                const magnitude = R.length(self.velocity);
                if (magnitude > 30) self.velocity = R.scale(self.velocity, 30 / magnitude);
                self.motion = .grapple_swing;
            }
        }
    }
    self.move(physics, dt);
    if (self.grounded and !was_grounded) {
        self.air_assist_engaged = false;
        self.landing = 0.25;
        if (self.motion == .stomp) {
            self.energy_kick_timer = 0.3;
            self.jump(8.5);
            self.motion = .jump;
        }
    }
    camera.position = self.eye();
}
const max_move_substeps: f32 = 128;
fn move(self: *Player, physics: *Physics, dt: f32) void {
    const carry = if (self.grounded) physics.velocity(self.support) orelse V{ 0, 0, 0 } else V{ 0, 0, 0 };
    const start = self.feet;
    const movement = R.scale(R.add(R.add(self.velocity, self.knockback), carry), dt);
    // Substeps prevent high-speed dashes and zip pulls crossing thin decks/walls.
    // The cap bounds the cost at boost-tier speeds; the move is split by the capped count, so a long
    // step still covers its full distance (it used to fall short above the old 64-step cap).
    const count: usize = @intFromFloat(@min(max_move_substeps, @max(1, @ceil(R.length(movement) / 0.18))));
    for (0..count) |_| {
        const result = physics.moveCharacter(self.shape, self.feet, R.scale(movement, 1 / @as(f32, @floatFromInt(count))), self.grounded and self.velocity[1] <= 0);
        self.feet = result.feet;
        self.grounded = result.grounded;
        self.support = result.support;
        if (result.hit_ceiling and self.velocity[1] > 0) {
            self.velocity[1] = 0;
            if (self.motion == .mantle) self.motion = .fall;
        }
    }
    for ([_]usize{ 0, 2 }) |k| {
        const actual = (self.feet[k] - start[k]) / dt - carry[k];
        if (@abs(actual) < @abs(self.velocity[k])) self.velocity[k] = actual;
    }
    if (self.grounded and self.velocity[1] < 0) self.velocity[1] = 0;
    self.knockback = R.scale(self.knockback, @exp(-9 * dt));
}

fn flatGround(_: ?*const anyopaque, _: f32, _: f32) Physics.GroundSample {
    return .{ .height = 0, .normal = .{ 0, 1, 0 } };
}
const test_dt: f32 = 1.0 / 60.0;
fn runFor(p: *Player, physics: *Physics, camera: *Camera, input: Input, steps: usize) void {
    for (0..steps) |_| {
        p.step(physics, camera, input, test_dt);
        physics.step(test_dt);
    }
}

test "a jump pressed just before landing is buffered; one pressed too early is dropped" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .yaw = 0, .pitch = 0 };
    for ([_]f32{ 0.3, 3 }) |press_height| {
        var p: Player = .{ .feet = .{ 0, 6, 0 } };
        while (p.feet[1] > press_height) runFor(&p, &physics, &camera, .{}, 1);
        runFor(&p, &physics, &camera, .{ .jump_pressed = true }, 1);
        var launched = false;
        for (0..60) |_| {
            runFor(&p, &physics, &camera, .{}, 1);
            launched = launched or p.velocity[1] > 5;
        }
        try std.testing.expectEqual(press_height < 1, launched);
    }
}

test "jump takes off before a second press engages the jetpack" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{};
    var p: Player = .{};
    runFor(&p, &physics, &camera, .{}, 2);
    try std.testing.expect(p.grounded);

    const full_fuel = p.fuel;
    runFor(&p, &physics, &camera, .{ .jump = true }, 1);
    try std.testing.expect(p.velocity[1] > 8);
    runFor(&p, &physics, &camera, .{ .jump = true }, 10);
    try std.testing.expectEqual(full_fuel, p.fuel);
    try std.testing.expect(p.motion != .jet);

    runFor(&p, &physics, &camera, .{}, 1);
    runFor(&p, &physics, &camera, .{ .jump = true }, 1);
    try std.testing.expectEqual(Motion.jet, p.motion);
    try std.testing.expect(p.fuel < full_fuel);
    const assisted_fuel = p.fuel;
    runFor(&p, &physics, &camera, .{ .jump = true }, 8);
    try std.testing.expect(p.fuel < assisted_fuel);
    runFor(&p, &physics, &camera, .{}, 1);
    try std.testing.expect(!p.air_assist_engaged);

    var falling: Player = .{ .feet = .{ 20, 10, 0 } };
    runFor(&falling, &physics, &camera, .{ .jump = true }, 1);
    try std.testing.expect(falling.motion != .jet);
    try std.testing.expectEqual(full_fuel, falling.fuel);
}

test "stomp slams down and bounces on landing; a fast grounded dodge rolls low" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .yaw = 0, .pitch = 0 };
    var p: Player = .{ .feet = .{ 0, 8, 0 } };
    runFor(&p, &physics, &camera, .{ .stomp = true }, 1);
    try std.testing.expectEqual(Motion.stomp, p.motion);
    try std.testing.expect(p.velocity[1] < -20);
    var bounce: f32 = 0;
    for (0..90) |_| {
        runFor(&p, &physics, &camera, .{}, 1);
        bounce = @max(bounce, p.velocity[1]);
    }
    try std.testing.expect(bounce > 8);
    runFor(&p, &physics, &camera, .{ .forward = 1 }, 90);
    try std.testing.expect(p.grounded);
    runFor(&p, &physics, &camera, .{ .forward = 1, .dodge = true }, 1);
    try std.testing.expectEqual(Motion.roll, p.motion);
    try std.testing.expectApproxEqAbs(@as(f32, 0.95), p.shape.height, 0.001);
    runFor(&p, &physics, &camera, .{ .forward = 1 }, 60);
    try std.testing.expectApproxEqAbs(@as(f32, 1.8), p.shape.height, 0.001);
}

test "walking into a wall is blocked; jumping into it climbs and mantles onto the top" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    // A 3 m block whose near face is at z = 1.75.
    _ = try physics.createBox(std.testing.allocator, .{ 0, 1.5, 2.75 }, .{ 2, 1.5, 1 }, R.identity, 0);
    var camera: Camera = .{ .yaw = 0, .pitch = 0 };
    var p: Player = .{ .feet = .{ 0, 0, 0 } };
    for (0..90) |_| {
        runFor(&p, &physics, &camera, .{ .forward = 1 }, 1);
        try std.testing.expect(p.motion != .climb and p.motion != .mantle);
    }
    try std.testing.expect(p.grounded and p.feet[2] < 1.75 and p.feet[1] < 0.01);
    runFor(&p, &physics, &camera, .{ .forward = 1, .jump_pressed = true }, 1);
    var climbed = false;
    for (0..240) |_| {
        runFor(&p, &physics, &camera, .{ .forward = 1 }, 1);
        climbed = climbed or p.motion == .climb;
        if (p.grounded and p.feet[1] > 2.95) break;
    }
    try std.testing.expect(climbed);
    try std.testing.expect(p.grounded and p.feet[1] > 2.95 and p.feet[2] > 1.75);
}

test "grapple zips toward a static anchor and releases on arrival; flight glides" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    _ = try physics.createBox(std.testing.allocator, .{ 0, 10, 31 }, .{ 5, 10, 1 }, R.identity, 0);
    var camera: Camera = .{ .yaw = 0, .pitch = std.math.atan2(@as(f32, 1.4), 28) };
    var p: Player = .{ .feet = .{ 0, 0, 0 } };
    runFor(&p, &physics, &camera, .{}, 10);
    runFor(&p, &physics, &camera, .{ .grapple = true }, 1);
    try std.testing.expect(p.grapple.mode == .windup);
    var zipped = false;
    for (0..150) |_| {
        runFor(&p, &physics, &camera, .{}, 1);
        zipped = zipped or p.motion == .grapple_zip;
    }
    try std.testing.expect(zipped and p.feet[2] > 26);
    try std.testing.expect(p.grapple.mode == .ready or p.grapple.mode == .cooldown);

    var glider: Player = .{ .feet = .{ 50, 0, 0 }, .traversal = .flight };
    runFor(&glider, &physics, &camera, .{}, 2);
    runFor(&glider, &physics, &camera, .{ .jump = true }, 6);
    runFor(&glider, &physics, &camera, .{}, 1);
    runFor(&glider, &physics, &camera, .{ .jump = true }, 12);
    try std.testing.expectEqual(Motion.glide, glider.motion);
    try std.testing.expect(glider.velocity[1] >= -3.5);
    try std.testing.expect(glider.fuel < glider.suit.fuel_max);
}

test "free flight stays above terrain and lands on rigid bodies" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .position = math.vec3(0, eye_height + 0.1, 0) };
    var player: Player = .{ .mode = .fly };
    var descend: Input = .{};
    descend.up = -1;
    runFor(&player, &physics, &camera, descend, 120);
    try std.testing.expectApproxEqAbs(@as(f32, 0), player.feet[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, eye_height), camera.position.y(), 0.001);

    _ = try physics.createRigid(.{ .half_extents = .{ 2, 0.5, 2 }, .position = .{ 8, 0.5, 0 }, .mass = 20 });
    for (0..30) |_| physics.step(test_dt);
    camera.position = math.vec3(8, 2.7, 0);
    player.setMode(.fly, camera);
    runFor(&player, &physics, &camera, descend, 60);
    try std.testing.expectApproxEqAbs(@as(f32, 1), player.feet[1], 0.01);
    try std.testing.expectApproxEqAbs(player.feet[1] + eye_height, camera.position.y(), 0.001);
}

test "three quick jump taps toggle hover" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{};
    var p: Player = .{};
    for (0..3) |_| {
        runFor(&p, &physics, &camera, .{ .jump_pressed = true }, 1);
        runFor(&p, &physics, &camera, .{}, 5);
    }
    try std.testing.expect(p.hover_enabled);
}

fn runIn(p: *Player, physics: *Physics, camera: *Camera, input: Input, env: Environment, steps: usize) void {
    for (0..steps) |_| {
        p.stepIn(physics, camera, input, env, test_dt);
        physics.step(test_dt);
    }
}

fn groundSpeed(p: Player) f32 {
    return @sqrt(p.velocity[0] * p.velocity[0] + p.velocity[2] * p.velocity[2]);
}

test "snow, marsh and shallow water slow a runner; snow slides further to a stop" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .yaw = 0, .pitch = 0 };
    var speeds: [4]f32 = undefined;
    var slides: [2]f32 = undefined;
    for ([_]Environment{ .{ .ground = .grass }, .{ .ground = .snow }, .{ .ground = .marsh }, .{ .ground = .grass, .river = 0.6 } }, 0..) |env, i| {
        var p: Player = .{ .feet = .{ 0, 0, 0 } };
        runIn(&p, &physics, &camera, .{ .forward = 1 }, env, 120);
        speeds[i] = groundSpeed(p);
        if (i < 2) {
            const start = p.feet[2];
            runIn(&p, &physics, &camera, .{}, env, 120);
            slides[i] = p.feet[2] - start;
        }
    }
    try std.testing.expectApproxEqAbs(walk_speed, speeds[0], 0.05);
    try std.testing.expect(speeds[1] < speeds[0] * 0.85 and speeds[2] < speeds[0] * 0.9);
    // Wading thigh-deep halves the pace or so.
    try std.testing.expect(speeds[3] < speeds[0] * 0.8);
    try std.testing.expect(slides[1] > slides[0] * 1.5);
}

test "a river deep enough floats a walker into a swim, and the bank walks them out" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .yaw = 0, .pitch = 0 };
    var p: Player = .{ .feet = .{ 0, 0, 0 } };
    // Shallow: wading, still on the bed.
    runIn(&p, &physics, &camera, .{}, .{ .river = 0.5 }, 30);
    try std.testing.expect(p.motion != .swim and p.wading > 0.4 and p.grounded);
    // Deep: the body rises and swims at the surface, breath intact.
    runIn(&p, &physics, &camera, .{ .forward = 1 }, .{ .river = 1.4 }, 120);
    try std.testing.expectEqual(Motion.swim, p.motion);
    try std.testing.expect(p.feet[1] > 0.4 and p.breath > 11);
    // Back on dry ground the swim ends.
    runIn(&p, &physics, &camera, .{}, .{}, 90);
    try std.testing.expect(p.motion != .swim and p.grounded and p.wading == 0);
}

test "held boost doubles free-fly speed every tier and letting go drops back" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .position = math.vec3(0, 3000, 0) };
    var player: Player = .{ .mode = .fly };
    player.setMode(.fly, camera);
    const forward: Input = .{ .forward = 1, .fast = true };
    runFor(&player, &physics, &camera, forward, 60);
    try std.testing.expectEqual(@as(u32, 0), player.boostTier());
    try std.testing.expectApproxEqAbs(@as(f32, 55), R.length(player.velocity), 1);
    var expected: f32 = 55;
    for (1..max_boost_tier + 1) |tier| {
        runFor(&player, &physics, &camera, forward, @intFromFloat(boost_tier_seconds * 60));
        expected *= 2;
        try std.testing.expectEqual(@as(u32, @intCast(tier)), player.boostTier());
        try std.testing.expectApproxEqRel(expected, R.length(player.velocity), 0.03);
    }
    // The tier is capped, and a step this long still covers its whole distance (the substep cap).
    const before = player.feet;
    runFor(&player, &physics, &camera, forward, 60);
    try std.testing.expectEqual(max_boost_tier, player.boostTier());
    try std.testing.expectApproxEqRel(expected, R.length(R.sub(player.feet, before)), 0.03);
    runFor(&player, &physics, &camera, .{ .forward = 1 }, 120);
    try std.testing.expectEqual(@as(u32, 0), player.boostTier());
    try std.testing.expectApproxEqAbs(@as(f32, 28), R.length(player.velocity), 1);
}

test "suit flight boost doubles each tier too and costs the same fuel" {
    var physics = Physics.init(.{ .sample = flatGround });
    defer physics.deinit();
    var camera: Camera = .{ .position = math.vec3(0, 3000, 0) };
    var player: Player = .{ .feet = .{ 0, 3000, 0 }, .traversal = .flight, .flight_engaged = true };
    player.setMode(.walk, camera);
    player.feet = .{ 0, 3000, 0 };
    player.traversal = .flight;
    player.flight_engaged = true;
    const forward: Input = .{ .forward = 1, .fast = true };
    runIn(&player, &physics, &camera, forward, .{}, @intFromFloat(boost_tier_seconds * 60 * 2 + 40));
    try std.testing.expectEqual(@as(u32, 2), player.boostTier());
    try std.testing.expectApproxEqRel(@as(f32, 52 * 4), R.length(player.velocity), 0.05);
    try std.testing.expect(player.fuel < player.suit.fuel_max);
}
