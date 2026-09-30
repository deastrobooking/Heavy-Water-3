// Silhouette outlines from depth discontinuities, blended over the lit frame. Depth is reversed
// and infinite (depth = near / z), so view distance is near / depth; the sky (depth 0) counts as
// very far, which outlines shapes against the sky.
@group(0) @binding(0) var depth_texture: texture_depth_2d;

const near: f32 = 0.1;
const ink: vec3<f32> = vec3<f32>(0.09, 0.07, 0.06);

fn view_distance(p: vec2<i32>) -> f32 {
    let d = textureLoad(depth_texture, p, 0);
    return near / max(d, 0.00000005);
}

@vertex fn vertex_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let x = f32((index << 1u) & 2u);
    let y = f32(index & 2u);
    return vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
}

// Written for Mach's WGSL compiler: no integer clamp, no dynamic array indexing.
fn neighbor(c: vec2<i32>, dx: i32, dy: i32, size: vec2<i32>) -> f32 {
    var x = c.x + dx;
    var y = c.y + dy;
    if (x < 0) { x = 0; }
    if (y < 0) { y = 0; }
    if (x > size.x - 1) { x = size.x - 1; }
    if (y > size.y - 1) { y = size.y - 1; }
    return view_distance(vec2<i32>(x, y));
}

@fragment fn frag_main(@builtin(position) position: vec4<f32>) -> @location(0) vec4<f32> {
    let dims = textureDimensions(depth_texture);
    let size = vec2<i32>(i32(dims.x), i32(dims.y));
    let c = vec2<i32>(i32(position.x), i32(position.y));
    let center = view_distance(c);
    let farthest = max(max(neighbor(c, 1, 0, size), neighbor(c, -1, 0, size)), max(neighbor(c, 0, 1, size), neighbor(c, 0, -1, size)));
    // Only the nearer side of an edge draws, so lines stay one pixel wide on the silhouette.
    let jump = (max(farthest, center) - center) / center;
    let strength = smoothstep(0.06, 0.2, jump) * (1.0 - smoothstep(500.0, 1800.0, center));
    return vec4<f32>(ink, strength * 0.85);
}
