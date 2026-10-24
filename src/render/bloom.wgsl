// Compact 3x3 threshold bloom. The source is the finished 3D scene; outlines and HUD
// are composited afterward, so the glow never softens text or ink lines.
@group(0) @binding(0) var source_texture: texture_2d<f32>;
struct Rain { values: vec4<f32>, };
@group(0) @binding(1) var<uniform> rain: Rain;

@vertex fn vertex_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let x = f32((index << 1u) & 2u);
    let y = f32(index & 2u);
    return vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
}

fn bright(color: vec3<f32>) -> vec3<f32> {
    let luminance = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    return color * smoothstep(0.88, 1.0, luminance);
}

fn sample_bright(pixel: vec2<i32>, size: vec2<i32>, dx: i32, dy: i32) -> vec3<f32> {
    var p = pixel + vec2<i32>(dx, dy);
    if (p.x < 0) { p.x = 0; }
    if (p.y < 0) { p.y = 0; }
    if (p.x >= size.x) { p.x = size.x - 1; }
    if (p.y >= size.y) { p.y = size.y - 1; }
    return bright(textureLoad(source_texture, p, 0).rgb);
}

@fragment fn frag_main(@builtin(position) position: vec4<f32>) -> @location(0) vec4<f32> {
    let dims = textureDimensions(source_texture);
    let size = vec2<i32>(i32(dims.x), i32(dims.y));
    let pixel = vec2<i32>(i32(position.x), i32(position.y));
    let center = textureLoad(source_texture, pixel, 0).rgb;
    let glow = sample_bright(pixel, size, 1, 0) * 2.0
        + sample_bright(pixel, size, -1, 0) * 2.0
        + sample_bright(pixel, size, 0, 1) * 2.0
        + sample_bright(pixel, size, 0, -1) * 2.0
        + sample_bright(pixel, size, 1, 1)
        + sample_bright(pixel, size, 1, -1)
        + sample_bright(pixel, size, -1, 1)
        + sample_bright(pixel, size, -1, -1);
    let column = floor(position.x / 32.0);
    let seed = fract(sin(column * 127.1 + 17.7) * 43758.5453);
    let streak_x = abs(fract(position.x / 32.0 + position.y * 0.001) - seed * 0.78 - 0.10);
    let drift = rain.values.y * (0.7 + seed * 0.8);
    let streak_y = fract(position.y * 0.008 + drift + seed);
    let streak_length = smoothstep(0.04, 0.12, streak_y) * (1.0 - smoothstep(0.76, 0.86, streak_y));
    let streak = (1.0 - smoothstep(0.018, 0.045, streak_x)) * streak_length;
    let rain_glint = vec3<f32>(0.42, 0.62, 0.82) * streak * rain.values.x * 0.055;
    return vec4<f32>(center + glow * 0.022 + rain_glint, 1.0);
}
