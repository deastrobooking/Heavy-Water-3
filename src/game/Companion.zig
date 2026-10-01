//! Companion system: Freed Synthetic Humanoids and Cyber-Pets (Digimon/Pokemon style).
//! Allies gain experience, level up, assist in combat, and can be customized with elemental cores.
const std = @import("std");
const Physics = @import("../physics/Physics.zig");
const Weapon = @import("../combat/Weapon.zig");
const V = Physics.Vec3;
const R = Physics.Rotation;

pub const CompanionKind = enum(u8) {
    synthetic_humanoid, // Zero/Mega Man style robot freed from Hive override
    bio_synth_hound,    // High-mobility plasma hound pet
    chitin_falcon,      // Aerial support falcon with homing lumen darts
    root_golem,         // Heavy armored defender that generates shields
};

pub const CompanionState = enum(u8) {
    following,
    engaging,
    guarding,
    downed,
};

pub const Companion = struct {
    active: bool = false,
    kind: CompanionKind = .synthetic_humanoid,
    name: [24]u8 = @splat(0),
    name_len: u8 = 0,
    level: u16 = 1,
    xp: u32 = 0,
    xp_to_next: u32 = 100,
    health: f32 = 250.0,
    max_health: f32 = 250.0,
    state: CompanionState = .following,
    position: V = @splat(0),
    velocity: V = @splat(0),
    element: Weapon.Element = .solar_lumen,
    attack_cooldown: f32 = 0,
    collar_freed: bool = true,

    pub fn init(kind: CompanionKind, name_str: []const u8, pos: V, elem: Weapon.Element) Companion {
        var comp: Companion = .{
            .active = true,
            .kind = kind,
            .position = pos,
            .element = elem,
            .collar_freed = true,
        };
        const n = @min(name_str.len, 24);
        @memcpy(comp.name[0..n], name_str[0..n]);
        comp.name_len = @intCast(n);
        comp.applyLevelStats();
        return comp;
    }

    pub fn applyLevelStats(self: *Companion) void {
        const lvl_f = @as(f32, @floatFromInt(self.level));
        self.max_health = 200.0 + lvl_f * 50.0;
        self.health = self.max_health;
        self.xp_to_next = @as(u32, self.level) * 120;
    }

    pub fn gainXp(self: *Companion, amount: u32) bool {
        self.xp += amount;
        var leveled_up = false;
        while (self.xp >= self.xp_to_next) {
            self.xp -= self.xp_to_next;
            self.level += 1;
            self.applyLevelStats();
            leveled_up = true;
        }
        return leveled_up;
    }

    pub fn update(self: *Companion, player_pos: V, target_enemy_pos: ?V, dt: f32) ?struct { damage: f32, target: V, kind: CompanionKind } {
        if (!self.active or self.state == .downed) return null;
        self.attack_cooldown = @max(0, self.attack_cooldown - dt);

        const to_player = R.sub(player_pos, self.position);
        const dist_to_player = R.length(to_player);

        if (target_enemy_pos) |target| {
            const to_target = R.sub(target, self.position);
            const dist_to_target = R.length(to_target);

            if (dist_to_target < 22.0) {
                self.state = .engaging;
                // Attack if cooldown ready
                if (self.attack_cooldown == 0) {
                    self.attack_cooldown = if (self.kind == .synthetic_humanoid) 0.65 else 1.1;
                    const dmg: f32 = switch (self.kind) {
                        .synthetic_humanoid => 35.0 + @as(f32, @floatFromInt(self.level)) * 6.0,
                        .bio_synth_hound => 45.0 + @as(f32, @floatFromInt(self.level)) * 8.0,
                        .chitin_falcon => 28.0 + @as(f32, @floatFromInt(self.level)) * 5.0,
                        .root_golem => 60.0 + @as(f32, @floatFromInt(self.level)) * 10.0,
                    };
                    return .{ .damage = dmg, .target = target, .kind = self.kind };
                }
            }
        }

        // Return to player if too far
        if (dist_to_player > 5.0) {
            self.state = .following;
            const move_dir = R.normalize(to_player);
            const move_speed: f32 = if (dist_to_player > 18.0) 24.0 else 9.0;
            self.velocity = R.scale(move_dir, move_speed);
            self.position = R.add(self.position, R.scale(self.velocity, dt));
        } else {
            self.velocity = .{ 0, 0, 0 };
        }
        return null;
    }
};

test "companion recruitment, leveling up stats, and combat attack" {
    var pet = Companion.init(.bio_synth_hound, "GARU-7", .{ 10, 0, 10 }, .cryo_deuterium);
    try std.testing.expectEqual(@as(u16, 1), pet.level);
    try std.testing.expectEqual(@as(f32, 250.0), pet.max_health);

    // Level up by granting XP
    const leveled = pet.gainXp(150);
    try std.testing.expect(leveled);
    try std.testing.expectEqual(@as(u16, 2), pet.level);
    try std.testing.expectEqual(@as(f32, 300.0), pet.max_health);

    // Combat engagement
    const attack = pet.update(.{ 10, 0, 10 }, .{ 12, 0, 14 }, 0.1);
    try std.testing.expect(attack != null);
    try std.testing.expect(attack.?.damage > 50.0);
}
