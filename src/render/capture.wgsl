// Copies the rendered frame into a CPU-readable buffer (Mach's Metal backend has no
// texture-to-buffer copy). One packed RGBA8 word per pixel, rows top to bottom.
@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var<storage, read_write> pixels: array<u32>;

@compute @workgroup_size(8, 8, 1) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let size = textureDimensions(source);
    if (id.x >= size.x || id.y >= size.y) {
        return;
    }
    let c = textureLoad(source, vec2<i32>(i32(id.x), i32(id.y)), 0);
    let r = u32(clamp(c.r, 0.0, 1.0) * 255.0 + 0.5);
    let g = u32(clamp(c.g, 0.0, 1.0) * 255.0 + 0.5);
    let b = u32(clamp(c.b, 0.0, 1.0) * 255.0 + 0.5);
    // Mach's WGSL parser does not accept shifts here; multiplication packs the same bits.
    pixels[id.y * size.x + id.x] = r + g * 256u + b * 65536u + 4278190080u;
}
