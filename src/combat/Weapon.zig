//! Weapons, upgrades, elemental cores, and combat actions for Heavy Water.
//! Inspired by Zero (Mega Man X/Zero), energy blasters, energy bows with warp-strike,
//! protective shields, homing tracking missiles, and giant energy blasts.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const V = Physics.Vec3;
const R = Physics.Rotation;

pub const Element = enum(u8) {
    kinetic = 0,
    solar_lumen = 1,
    cryo_deuterium = 2,
    rootsong = 3,

    pub fn color(self: Element) [4]f32 {
        return switch (self) {
            .kinetic => .{ 0.95, 0.95, 0.95, 1.0 },
            .solar_lumen => .{ 1.0, 0.75, 0.2, 1.0 },
            .cryo_deuterium => .{ 0.2, 0.85, 1.0, 1.0 },
            .rootsong => .{ 0.3, 0.95, 0.4, 1.0 },
        };
    }
};

pub const WeaponKind = enum(u8) {
    beam_saber,
    blaster,
    energy_bow,
    tracking_missile,
    protective_shield,
    giant_blast,
    /// Energy firearms (`Firearms.zig`).
    sniper_rifle,
    machine_gun,
    heavy_rifle,
    energy_bazooka,
};

/// Base damage by `WeaponKind` tag order. Keep weapon power edits in this table.
pub const tuning = .{
    .base_damage = [_]f32{ 45, 22, 65, 80, 0, 180, 140, 9, 55, 160 },
    .damage_per_level = 0.25,
    .plasma_edge_multiplier = 1.5,
    .quantum_warp_multiplier = 1.3,
};

pub const CoreUpgrade = enum(u8) {
    none = 0,
    plasma_edge, // Increases saber slash reach and damage
    accelerator, // Cuts blaster charge time by 40%
    quantum_warp, // Bow warp strike deals 3x critical damage and refreshes dash
    hydra_swarm, // Missile launcher fires 4 micro-missiles instead of 2
    aegis_reflector, // Shield parry reflects projectiles back at attackers
    overdrive_core, // Giant blast beam width and duration doubled
};

pub const WeaponSlot = struct {
    kind: WeaponKind = .beam_saber,
    element: Element = .kinetic,
    core: CoreUpgrade = .none,
    level: u8 = 1,
    damage_mult: f32 = 1.0,
    cooldown_mult: f32 = 1.0,

    pub fn baseDamage(self: WeaponSlot) f32 {
        const lvl_bonus = 1.0 + @as(f32, @floatFromInt(self.level - 1)) * tuning.damage_per_level;
        const base = tuning.base_damage[@intFromEnum(self.kind)];
        const core_mult: f32 = if (self.core == .plasma_edge and self.kind == .beam_saber) tuning.plasma_edge_multiplier else if (self.core == .quantum_warp and self.kind == .energy_bow) tuning.quantum_warp_multiplier else 1.0;
        return base * lvl_bonus * self.damage_mult * core_mult;
    }
};

pub const SlashResult = struct { damage: f32, radius: f32, combo: u8 };

pub const BeamSaber = struct {
    pub const max_combo = 3;
    combo_step: u8 = 0,
    combo_window: f32 = 0,
    charge_time: f32 = 0,
    is_charging: bool = false,
    slash_active: f32 = 0,
    dash_slash: bool = false,
    spin_slash: bool = false,

    pub fn update(self: *BeamSaber, dt: f32) void {
        self.combo_window = @max(0, self.combo_window - dt);
        if (self.combo_window == 0) self.combo_step = 0;
        self.slash_active = @max(0, self.slash_active - dt);
        if (self.slash_active == 0) {
            self.dash_slash = false;
            self.spin_slash = false;
        }
        if (self.is_charging) {
            self.charge_time = @min(2.0, self.charge_time + dt);
        }
    }

    /// Slash attack (Zero style). Returns damage dealt and slash radius.
    pub fn slash(self: *BeamSaber, is_dashing: bool, is_airborne: bool, slot: WeaponSlot) SlashResult {
        self.slash_active = 0.25;
        self.dash_slash = is_dashing;
        self.spin_slash = is_airborne;

        if (self.charge_time >= 1.2) {
            // Level 2 full charge slash: massive wave
            self.charge_time = 0;
            self.is_charging = false;
            self.combo_step = 0;
            return .{ .damage = slot.baseDamage() * 3.2, .radius = 5.0, .combo = 4 };
        }

        self.charge_time = 0;
        self.is_charging = false;

        if (is_dashing) {
            self.combo_step = 0;
            return .{ .damage = slot.baseDamage() * 1.8, .radius = 3.6, .combo = 10 };
        }
        if (is_airborne) {
            self.combo_step = 0;
            return .{ .damage = slot.baseDamage() * 1.6, .radius = 3.2, .combo = 11 };
        }

        self.combo_step = (self.combo_step % max_combo) + 1;
        self.combo_window = 0.85;

        const multiplier: f32 = switch (self.combo_step) {
            1 => 1.0,
            2 => 1.35,
            3 => 2.2, // Final heavy finisher
            else => 1.0,
        };
        const radius: f32 = if (self.combo_step == 3) 3.5 else 2.6;
        return .{ .damage = slot.baseDamage() * multiplier, .radius = radius, .combo = self.combo_step };
    }
};

pub const ShotResult = struct { damage: f32, speed: f32, size: f32, level: u8 };

pub const Blaster = struct {
    charge_level: u8 = 0,
    charge_time: f32 = 0,
    is_charging: bool = false,
    heat: f32 = 0,
    cooldown: f32 = 0,

    pub fn update(self: *Blaster, dt: f32, slot: WeaponSlot) void {
        self.cooldown = @max(0, self.cooldown - dt);
        self.heat = @max(0, self.heat - 35.0 * dt);
        if (self.is_charging) {
            const charge_rate = if (slot.core == .accelerator) @as(f32, 1.8) else 1.0;
            self.charge_time += dt * charge_rate;
            if (self.charge_time >= 1.6) {
                self.charge_level = 3; // Buster Level 3 (Giant Plasma)
            } else if (self.charge_time >= 0.8) {
                self.charge_level = 2; // Buster Level 2 (Medium Burst)
            } else if (self.charge_time >= 0.3) {
                self.charge_level = 1;
            } else {
                self.charge_level = 0;
            }
        }
    }

    pub fn releaseShot(self: *Blaster, slot: WeaponSlot) ?ShotResult {
        if (self.cooldown > 0 or self.heat >= 100.0) return null;
        const lvl = self.charge_level;
        const result: ShotResult = switch (lvl) {
            0 => .{ .damage = slot.baseDamage(), .speed = 65.0, .size = 0.25, .level = 0 },
            1 => .{ .damage = slot.baseDamage() * 1.6, .speed = 75.0, .size = 0.45, .level = 1 },
            2 => .{ .damage = slot.baseDamage() * 2.8, .speed = 85.0, .size = 0.8, .level = 2 },
            3 => .{ .damage = slot.baseDamage() * 4.8, .speed = 95.0, .size = 1.4, .level = 3 },
            else => .{ .damage = slot.baseDamage(), .speed = 65.0, .size = 0.25, .level = 0 },
        };
        self.heat += if (lvl == 3) 40.0 else if (lvl == 2) 25.0 else 10.0;
        self.cooldown = if (lvl == 3) 0.4 else 0.12;
        self.charge_time = 0;
        self.charge_level = 0;
        self.is_charging = false;
        return result;
    }
};

pub const EnergyBow = struct {
    draw: f32 = 0,
    is_drawing: bool = false,
    warp_arrow_ready: bool = true,
    warp_cooldown: f32 = 0,

    pub fn update(self: *EnergyBow, dt: f32) void {
        self.warp_cooldown = @max(0, self.warp_cooldown - dt);
        if (self.is_drawing) {
            self.draw = @min(1.0, self.draw + dt * 2.2);
        }
    }

    pub fn release(self: *EnergyBow, as_warp: bool, slot: WeaponSlot) ?struct { damage: f32, speed: f32, is_warp: bool } {
        if (self.draw < 0.2) {
            self.draw = 0;
            self.is_drawing = false;
            return null;
        }
        const power = self.draw;
        const warp = as_warp and (self.warp_cooldown == 0);
        if (warp) self.warp_cooldown = 2.0;

        const base_dmg = slot.baseDamage() * (0.5 + power * 1.2);
        const dmg = if (warp) base_dmg * (if (slot.core == .quantum_warp) @as(f32, 2.5) else 1.8) else base_dmg;
        const spd = 40.0 + power * 50.0;

        self.draw = 0;
        self.is_drawing = false;
        return .{ .damage = dmg, .speed = spd, .is_warp = warp };
    }
};

pub const ProtectiveShield = struct {
    active: bool = false,
    health: f32 = 120.0,
    max_health: f32 = 120.0,
    parry_window: f32 = 0,
    cooldown: f32 = 0,

    pub fn raise(self: *ProtectiveShield) void {
        if (self.cooldown > 0 or self.health <= 0) return;
        self.active = true;
        self.parry_window = 0.22; // 220ms parry window
    }

    pub fn lower(self: *ProtectiveShield) void {
        self.active = false;
        self.parry_window = 0;
    }

    pub fn update(self: *ProtectiveShield, dt: f32) void {
        self.parry_window = @max(0, self.parry_window - dt);
        self.cooldown = @max(0, self.cooldown - dt);
        if (!self.active and self.cooldown == 0) {
            self.health = @min(self.max_health, self.health + 25.0 * dt);
        }
    }

    /// Absorb incoming damage. Returns true if parried, or leftover damage penetrating shield.
    pub fn absorb(self: *ProtectiveShield, incoming: f32, slot: WeaponSlot) struct { parried: bool, leftover: f32 } {
        if (!self.active) return .{ .parried = false, .leftover = incoming };
        if (self.parry_window > 0) {
            // Perfect parry! Deflect 100% of damage and optionally reflect
            const reflect = slot.core == .aegis_reflector;
            _ = reflect;
            return .{ .parried = true, .leftover = 0 };
        }
        if (self.health >= incoming) {
            self.health -= incoming;
            return .{ .parried = false, .leftover = 0 };
        } else {
            const leftover = incoming - self.health;
            self.health = 0;
            self.active = false;
            self.cooldown = 3.5; // Shield break penalty
            return .{ .parried = false, .leftover = leftover };
        }
    }
};

pub const GiantBlast = struct {
    firing: bool = false,
    duration: f32 = 0,
    max_duration: f32 = 1.4,
    charge: f32 = 0,
    ready: bool = true,
    cooldown: f32 = 0,

    pub fn startCharge(self: *GiantBlast) void {
        if (self.cooldown == 0) {
            self.charge = 0;
            self.ready = false;
        }
    }

    pub fn update(self: *GiantBlast, dt: f32, slot: WeaponSlot) void {
        self.cooldown = @max(0, self.cooldown - dt);
        if (self.firing) {
            self.duration = @max(0, self.duration - dt);
            if (self.duration == 0) {
                self.firing = false;
                self.cooldown = 4.0;
            }
        } else if (!self.ready and self.cooldown == 0) {
            self.charge = @min(2.0, self.charge + dt);
            if (self.charge >= 1.5) {
                self.ready = true;
            }
        }
        _ = slot;
    }

    pub fn fire(self: *GiantBlast, slot: WeaponSlot) ?struct { dps: f32, beam_width: f32, beam_length: f32 } {
        if (!self.ready or self.firing) return null;
        self.firing = true;
        const core_overdrive = slot.core == .overdrive_core;
        self.duration = if (core_overdrive) self.max_duration * 1.6 else self.max_duration;
        self.ready = false;
        self.charge = 0;
        const width: f32 = if (core_overdrive) 3.5 else 1.8;
        return .{
            .dps = slot.baseDamage() * 1.8,
            .beam_width = width,
            .beam_length = 80.0,
        };
    }
};
