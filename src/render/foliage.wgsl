// Plants and trees: the vertex stage for scattered flora, spliced into scene.wgsl in place of
// `vertex_main` (the fragment stage is shared). Each plant bends in the wind: the offset grows
// with the square of the height above its root, so roots stay planted, and a trunk drawn with
// the same instance bends exactly as its canopy does. Every plant gets its own phase from its
// position, and slow gusts roll across the field.
@vertex fn vertex_foliage(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(5) color: vec3<f32>,
    @location(6) stretch: vec4<f32>,
    @location(7) rotation: vec4<f32>,
) -> VertexOut {
    var out: VertexOut;
    let t = frame.params.x;
    let root = wrap(translation_scale.xz);
    let phase = dot(root, vec2<f32>(0.13, 0.17));
    let gust = 0.55 + 0.45 * sin(t * 0.41 + root.x * 0.012 + root.y * 0.009);
    let h = max(position.y, 0.0);
    let swing = sin(t * 1.7 + phase) + 0.35 * sin(t * 4.1 + phase * 2.3 + position.x * 3.0);
    // About 8 cm at the tip of a grass tuft, about 35 cm at the crown of a tree.
    let reach = min(0.12, 0.35 / max(translation_scale.w, 0.01));
    let bend = h * h * reach * frame.params.y * gust * swing;
    let local = position + vec3<f32>(frame.params.z * bend, -abs(bend) * 0.15, frame.params.w * bend);
    let world = rotate(rotation, local * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    out.normal = rotate(rotation, normal / stretch.xyz);
    out.uv = uv;
    // Tiny light-bearing flecks sit on leaf surfaces, with the crown and blade tips carrying
    // more of them than stems. Their tint comes from each plant's own pigments, so redwood,
    // moonbell, sunspear and ordinary green foliage keep distinct night colors.
    let radial = length(position.xz);
    let tree = step(4.0, translation_scale.w);
    let crown = mix(smoothstep(0.035, 0.12, radial) * smoothstep(0.24, 0.52, position.y),
        smoothstep(0.035, 0.10, radial) * smoothstep(0.04, 0.20, position.y), tree);
    let fleck_hash = hash2(floor(position.xz * 43.0 + root * 0.73) + vec2<f32>(floor(position.y * 29.0), 13.0));
    let flecks = smoothstep(0.52, 0.78, fleck_hash);
    let pulse = 0.82 + 0.18 * sin(t * 1.25 + phase * 1.7 + fleck_hash * 6.28);
    let bio = crown * flecks * pulse * frame.horizon.a * 0.82;
    let leaf_color = tint.rgb * color;
    out.tint = vec4<f32>(leaf_color * (1.0 + bio * 0.48), tint.a + bio);
    out.world = world;
    return out;
}

