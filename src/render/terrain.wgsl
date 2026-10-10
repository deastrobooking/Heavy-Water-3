// Ground: the fragment stage for streamed terrain, spliced after scene.wgsl's `vertex_main`.
// The chunk mesh bakes the biome colour per vertex (Biome.terrainColor); this stage paints
// detail into it in world space, so it needs no textures and has no seams between chunks:
// - grass drifts between warm and cool patches, with lighter tufts close up;
// - steep faces show banded stone strata with dark cracks;
// - snow (read back from the bright, grey baked colour) lies on flat ground only, goes blue in
//   shadow and sparkles where the sun glints toward the eye.
@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    let n = normalize(in.normal);
    let w = in.world;
    let base = in.tint.rgb;
    let d = distance(w, frame.eye.xyz);
    // Fine detail fades out with distance before it can shimmer.
    let near = 1.0 - smoothstep(25.0, 110.0, d);

    let lum = dot(base, vec3<f32>(0.299, 0.587, 0.114));
    let chroma = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
    let snowy = smoothstep(0.6, 0.78, lum) * (1.0 - smoothstep(0.1, 0.22, chroma));
    let steep = 1.0 - smoothstep(0.6, 0.84, n.y);

    // Grass and earth: broad colour drift and close-up tufts.
    let broad = vnoise(w.xz * 0.035);
    let blotch = vnoise(w.xz * 0.21 + vec2<f32>(17.0, 3.0));
    let fine = vnoise(w.xz * 1.3);
    var ground = base * (0.88 + 0.2 * broad);
    ground = mix(ground, ground * vec3<f32>(1.1, 1.08, 0.78), smoothstep(0.66, 0.86, blotch) * 0.3);
    ground = ground * (1.0 + (fine - 0.5) * 0.22 * near);

    // Stone: wobbling horizontal strata, alternating tones, dark cracks along band edges. Bands
    // fade with distance before they can alias, and low banks (river cuts, hollows) stay earthy:
    // bare grey stone belongs to the heights.
    let alpine = smoothstep(8.0, 40.0, w.y);
    let far = 1.0 - smoothstep(60.0, 260.0, d);
    let strata = w.y * 0.4 + vnoise(w.xz * 0.04) * 2.5;
    let layer = fract(strata);
    // Every layer gets its own tone and thickness of crack, so the bands read as rock beds.
    let bed = hash2(vec2<f32>(floor(strata), 7.0));
    let tone = 1.0 + ((bed - 0.5) * 0.2 + (vnoise(w.xz * 0.5 + vec2<f32>(0.0, w.y)) - 0.5) * 0.16) * far;
    let crack = smoothstep(0.93 - 0.06 * bed, 0.98, layer) * near * step(0.35, bed);
    let rock = vec3<f32>(0.47, 0.48, 0.47) * tone * (1.0 - 0.32 * crack);
    let earth = base * vec3<f32>(0.82, 0.74, 0.62) * (1.0 + (tone - 1.0) * 0.5);
    var color = mix(ground, mix(earth, rock, 0.25 + 0.6 * alpine), steep);

    // Snow on the flats; rock shows through where it is too steep to hold.
    let snow = snowy * smoothstep(0.52, 0.74, n.y);
    color = mix(color, vec3<f32>(0.9, 0.94, 0.98) * (0.95 + 0.08 * broad), snow);

    var shaded = lit(color, n, w);
    let light = band(n);
    // Snow shadows go blue rather than grey.
    shaded = shaded + vec3<f32>(-0.03, 0.01, 0.07) * snow * (1.0 - light);
    // Glints: a few hashed cells catch the sun toward the eye.
    let cell = floor(wrap(w.xz) * 3.0);
    let view = normalize(frame.eye.xyz - w);
    let mirror = reflected(view * -1.0, n);
    let toward = smoothstep(0.55, 0.9, dot(mirror, frame.light_direction.xyz));
    let glint = step(0.975, hash2(cell)) * toward * snow * near * light;
    shaded = shaded + frame.light_color.rgb * glint * 0.9;
    return vec4<f32>(hazed(shaded, w, 0.0), 1.0);
}
