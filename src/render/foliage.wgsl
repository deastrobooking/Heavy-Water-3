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
    out.tint = vec4<f32>(tint.rgb * color, tint.a);
    out.world = world;
    return out;
}

