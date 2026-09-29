const std = @import("std");
const Noise = @import("Noise.zig");
const Chunk = @import("Chunk.zig");

/// Distance between terrain vertices. Chunk grids align to even world coordinates.
pub const spacing: f32 = Chunk.extent / Chunk.cells;
pub const Surface = struct { height: f32, normal: [3]f32 };

/// Height and face normal of the rendered triangle under (x, z), matching Chunk.fill's
/// triangulation exactly, so collision and visible terrain agree to float precision.
pub fn surface(seed: u64, x: f32, z: f32) Surface {
    const gx = @floor(x / spacing);
    const gz = @floor(z / spacing);
    const u = x / spacing - gx;
    const v = z / spacing - gz;
    const x0 = gx * spacing;
    const z0 = gz * spacing;
    const h00 = Noise.height(seed, x0, z0);
    const h10 = Noise.height(seed, x0 + spacing, z0);
    const h01 = Noise.height(seed, x0, z0 + spacing);
    // Each cell splits along the (x+1, z) → (x, z+1) diagonal.
    if (u + v <= 1) {
        const dx = h10 - h00;
        const dz = h01 - h00;
        return .{ .height = h00 + dx * u + dz * v, .normal = normal(dx, dz) };
    }
    const h11 = Noise.height(seed, x0 + spacing, z0 + spacing);
    const dx = h11 - h01;
    const dz = h11 - h10;
    return .{ .height = h11 - dx * (1 - u) - dz * (1 - v), .normal = normal(dx, dz) };
}

fn normal(dx: f32, dz: f32) [3]f32 {
    const nx = -dx / spacing;
    const nz = -dz / spacing;
    const inv = 1 / @sqrt(nx * nx + 1 + nz * nz);
    return .{ nx * inv, inv, nz * inv };
}

test "surface matches rendered chunk vertices and triangle interiors, including negative chunks" {
    const mesh = try Chunk.generate(std.testing.allocator, 42, -2, 1);
    defer mesh.deinit(std.testing.allocator);
    for (mesh.vertices) |vertex| {
        try std.testing.expectApproxEqAbs(vertex.position[1], surface(42, vertex.position[0], vertex.position[2]).height, 0.0001);
    }
    var i: usize = 0;
    while (i < mesh.indices.len) : (i += 997 * 3) {
        const a = mesh.vertices[mesh.indices[i]].position;
        const b = mesh.vertices[mesh.indices[i + 1]].position;
        const c = mesh.vertices[mesh.indices[i + 2]].position;
        // Centroid lies strictly inside the triangle.
        const p = [3]f32{ (a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3, (a[2] + b[2] + c[2]) / 3 };
        const s = surface(42, p[0], p[2]);
        try std.testing.expectApproxEqAbs(p[1], s.height, 0.0001);
        try std.testing.expect(s.normal[1] > 0);
    }
}
