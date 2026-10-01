//! Hive enemy faction: Mechanized drones, Dread Spires, and Bio-Corruption.
//! Implements Hive construction nodes, base building corruption pylons, and unit simulation.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Weapon = @import("../combat/Weapon.zig");
const V = Physics.Vec3;
const R = Physics.Rotation;

pub const UnitKind = enum(u8) {
    hive_drone,          // Fast swarming light bot with red pulse lasers
    corrupt_chimera,     // Enslaved wild beast carrying a control collar
    synthetic_trooper,   // Megaman/Metroid-style hostile humanoid bot
    dread_spire_walker,  // Giant siege walker with heavy cannons
};

pub const HiveUnit = struct {
    active: bool = false,
    kind: UnitKind = .hive_drone,
    position: V = @splat(0),
    velocity: V = @splat(0),
    health: f32 = 100.0,
    max_health: f32 = 100.0,
    collar_intact: bool = true, // Can be shattered with precise shots to free unit!
    shoot_cooldown: f32 = 0,
    alerted: bool = false,

    pub fn takeDamage(self: *HiveUnit, amount: f32, is_precise_shot: bool) struct { died: bool, freed: bool } {
        self.health = @max(0, self.health - amount);
        self.alerted = true;

        if (self.collar_intact and is_precise_shot and self.health <= self.max_health * 0.4) {
            // Shatter the control collar! Unit breaks free from the Hive!
            self.collar_intact = false;
            return .{ .died = false, .freed = true };
        }

        return .{ .died = (self.health == 0), .freed = false };
    }

    pub fn update(self: *HiveUnit, target_player: V, dt: f32) ?struct { damage: f32, aim_dir: V } {
        if (!self.active or !self.collar_intact) return null;
        self.shoot_cooldown = @max(0, self.shoot_cooldown - dt);

        const to_target = R.sub(target_player, self.position);
        const dist = R.length(to_target);

        if (dist < 40.0) {
            self.alerted = true;
        }

        if (self.alerted and dist > 4.0) {
            const dir = R.normalize(to_target);
            const speed: f32 = if (self.kind == .hive_drone) 14.0 else 7.0;
            self.velocity = R.scale(dir, speed);
            self.position = R.add(self.position, R.scale(self.velocity, dt));

            if (self.shoot_cooldown == 0 and dist < 30.0) {
                self.shoot_cooldown = 1.2;
                return .{
                    .damage = if (self.kind == .dread_spire_walker) 45.0 else 18.0,
                    .aim_dir = dir,
                };
            }
        }
        return null;
    }
};

pub const DreadSpireNode = struct {
    position: V,
    corruption_radius: f32 = 45.0,
    fabricator_active: bool = true,
    spawn_timer: f32 = 0,

    pub fn update(self: *DreadSpireNode, dt: f32) bool {
        if (!self.fabricator_active) return false;
        self.spawn_timer += dt;
        if (self.spawn_timer >= 8.0) {
            self.spawn_timer = 0;
            return true; // Request spawn of an assault drone
        }
        return false;
    }
};

test "Hive unit combat, collar shatter rescue, and drone spawning" {
    var unit: HiveUnit = .{
        .active = true,
        .kind = .synthetic_trooper,
        .position = .{ 0, 0, 0 },
        .health = 200.0,
        .max_health = 200.0,
        .collar_intact = true,
    };

    // Ordinary hit
    const hit1 = unit.takeDamage(50.0, false);
    try std.testing.expect(!hit1.died and !hit1.freed);

    // Precise arrow or saber hit to collar when damaged: free the synthetic!
    const hit2 = unit.takeDamage(80.0, true);
    try std.testing.expect(hit2.freed);
    try std.testing.expect(!unit.collar_intact);

    // Test Dread Spire node base building & spawner
    var spire: DreadSpireNode = .{ .position = .{ 100, 0, 100 } };
    try std.testing.expect(!spire.update(5.0));
    try std.testing.expect(spire.update(4.0)); // Surpasses 8.0s, triggers spawn!
}
