// Inverted-hull ink for characters (own module: Mach takes one entry point per stage). Each
// vertex is skinned like the lit pass, pushed out along its normal by the material's line width
// (pixels converted to metres at the vertex's depth, as toon.outlineWidth does) and pushed back
// away from the eye so the hull hides behind the body and only shows past its silhouette and
// where a nearer part overlaps a farther one. Both faces draw, so mesh winding does not matter.
@vertex fn vertex_hull(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(5) color: vec3<f32>,
    @location(8) joints: vec4<u32>,
    @location(9) weights: vec4<f32>,
    @location(10) kind: vec4<u32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(6) stretch: vec4<f32>,
    @location(7) rotation: vec4<f32>,
) -> VertexOut {
    let s = skin_blend(joints, weights, position, normal);
    let world = rotate(rotation, s.local * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    let n = normalize(rotate(rotation, s.bent / stretch.xyz));
    let m = 2u + kind.x * 6u;
    let line = cel.v[m + 4u];
    let flags = u32(cel.v[0].w);
    let clip0 = frame.view_projection * vec4<f32>(world, 1.0);
    // Viewport height in pixels and tan(fovy / 2) ride in the spare lanes of the frame uniform.
    let per_px = 2.0 * clip0.w * frame.light_color.w / max(frame.light_direction.w, 1.0);
    var px = line.w * cel.v[0].x;
    if (kind.y > 0u) {
        px = px * 0.6;
    }
    var width = clamp(px * per_px, cel.v[0].y, cel.v[0].z);
    if (px <= 0.0 || (flags & 1u) != 0u || tint.a < 0.0) {
        width = 0.0;
    }
    let away = normalize(world - frame.eye.xyz);
    let pushed = world + n * width + away * (width * 2.0);
    var out: VertexOut;
    out.clip = frame.view_projection * vec4<f32>(pushed, 1.0);
    out.normal = n;
    out.uv = vec2<f32>(0.0, 0.0);
    out.tint = vec4<f32>(tint.rgb * color * line.rgb, tint.a);
    out.world = world;
    return out;
}

@fragment fn frag_hull(in: VertexOut) -> @location(0) vec4<f32> {
    return vec4<f32>(hazed(in.tint.rgb, in.world, 0.0), 1.0);
}
