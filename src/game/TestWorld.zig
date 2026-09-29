const World = @import("../world/World.zig");
const Seed = @import("../procedural/Seed.zig");
const Noise = @import("../procedural/Noise.zig");
const Material = @import("../render/Material.zig");

pub fn populate(world: *World, seed: u64) !void {
    world.objects.lock();
    defer world.objects.unlock();
    for (0..World.max_objects) |i| {
        const h = Seed.mix(seed +% i);
        const x = Seed.unit(h) * 118 - 59;
        const z = Seed.unit(Seed.mix(h)) * 118 - 59;
        _ = try world.objects.new(.{
            .transform = .{ .position = .{ x, Noise.height(seed, x, z) - 0.15, z }, .scale = 0.45 + Seed.unit(Seed.mix(h +% 1)) * 1.4 },
            .tint = if (i % 11 == 0) Material.accent else Material.relic,
        });
    }
}
