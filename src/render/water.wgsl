// Rivers and waterfalls: the fragment stage for the chunk mesh's water ribbons, spliced after
// scene.wgsl's `vertex_main` and drawn blended after everything opaque.
// - Ripples scroll downstream (rivers flow east, +x) as two layers of moving noise; their
//   gradient bends the normal.
// - Colour runs from deep teal to the baked shallow colour; a Fresnel term mixes in the sky,
//   and the sun's reflection is a hard cel highlight.
// - Foam lines the banks (the ribbon's uv.y runs 0 to 1 across it) and streaks down the falls,
//   which are told apart by their sideways normal.
fn ripples(p: vec2<f32>, t: f32) -> f32 {
    return vnoise(p * 0.55 + vec2<f32>(-t * 0.9, t * 0.12)) + 0.5 * vnoise(p * 1.7 + vec2<f32>(-t * 1.8, -t * 0.3));
}

@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    let t = frame.params.x;
    let w = in.world;
    let geo = normalize(in.normal);
    let fall = 1.0 - smoothstep(0.3, 0.6, geo.y);
    let d = distance(w, frame.eye.xyz);
    let near = 1.0 - smoothstep(40.0, 160.0, d);

    let h = ripples(w.xz, t);
    let e = 0.15;
    let gx = (ripples(w.xz + vec2<f32>(e, 0.0), t) - h) / e;
    let gz = (ripples(w.xz + vec2<f32>(0.0, e), t) - h) / e;
    let flat_n = normalize(vec3<f32>(-gx * 0.18 * near, 1.0, -gz * 0.18 * near));
    let n = normalize(mix(flat_n, geo, fall));

    let view = normalize(frame.eye.xyz - w);
    let ndv = max(dot(n, view), 0.0);
    let k = 1.0 - ndv;
    let k2 = k * k;
    let fresnel = 0.04 + 0.96 * k2 * k2 * k;
    let deep = vec3<f32>(0.04, 0.27, 0.36);
    let body = mix(deep, in.tint.rgb, 0.45 + 0.35 * h);
    var color = lit(body, n, w);
    let mirror = reflected(view * -1.0, n);
    // The sky it mirrors, kept bluer than the haze so distant water stays water-coloured.
    let sky = mix(frame.ambient_sky.rgb * 1.2, frame.ambient_sky.rgb * 1.5 + frame.light_color.rgb * 0.1, clamp(mirror.y, 0.0, 1.0));
    color = mix(color, sky, clamp(fresnel * (1.0 - fall), 0.0, 0.5));
    // The sun's glint, as a hard toon highlight.
    let sun = dot(mirror, frame.light_direction.xyz);
    color = color + frame.light_color.rgb * smoothstep(0.965, 0.975, sun) * 0.9 * (1.0 - fall);
    // Broad, slow caustic flecks keep the moving water legible without high-frequency shimmer.
    let caustic = smoothstep(0.72, 0.94, vnoise(w.xz * 0.12 + vec2<f32>(-t * 0.16, t * 0.11)) + 0.35 * vnoise(w.xz * 0.31 + vec2<f32>(t * 0.2, -t * 0.13)));
    color = color + vec3<f32>(0.18, 0.56, 0.62) * caustic * (1.0 - fall) * (1.0 - fresnel * 0.55);

    // Foam: along the banks, broken up and drifting with the current.
    let edge = min(in.uv.y, 1.0 - in.uv.y);
    let churn = vnoise(w.xz * 1.1 + vec2<f32>(-t * 1.3, 0.0));
    let bank = 1.0 - smoothstep(0.04, 0.1 + 0.08 * churn, edge);
    // Falls: bright streaks racing downward.
    let streak = vnoise(vec2<f32>(w.z * 2.4, w.y * 0.45 + t * 3.2));
    let curtain = fall * (0.45 + 0.55 * smoothstep(0.35, 0.7, streak));
    let foam = clamp(max(bank * 0.85, curtain), 0.0, 1.0);
    let white = vec3<f32>(0.92, 0.97, 1.0) * (frame.ambient_sky.rgb * 0.6 + frame.light_color.rgb * (0.35 + 0.5 * band(geo)));
    color = mix(color, white, foam);

    let alpha = clamp(0.72 + 0.25 * fresnel + 0.25 * foam, 0.0, 0.96);
    return vec4<f32>(hazed(color, w, 0.0), alpha);
}
