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

    // Antarctica is a dedicated 160 km region centered on (0, -420 km). Its broad blend
    // feather hides the regional terrain boundary while giving the whole landing a glacial read.
    let antarctic_x = 1.0 - smoothstep(76000.0, 80000.0, abs(w.x));
    let antarctic_z = 1.0 - smoothstep(76000.0, 80000.0, abs(w.z + 420000.0));
    let antarctic = antarctic_x * antarctic_z;

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

    // World-space albedo repeats every 256 m (an exact divisor of wrap's 1024 m period),
    // with lower frequency ice strata and snow veils to keep the macro terrain readable.
    let glacier = textureSample(surface_texture, surface_sampler, wrap(w.xz / 256.0)).rgb;
    let ice_strata = vnoise(w.xz * 0.018 + vec2<f32>(w.y * 0.006, -w.y * 0.004));
    let snow_veil = smoothstep(0.37, 0.68, vnoise(w.xz * 0.09 + vec2<f32>(4.0, 29.0)));
    let glacial_ground = glacier * (0.82 + ice_strata * 0.24) * mix(vec3<f32>(0.68, 0.85, 1.0), vec3<f32>(1.0), snow_veil * 0.42);
    color = mix(color, glacial_ground, antarctic);

    var shaded = lit(color, n, w);
    let light = band(n) * sunlight(w, n);
    // Snow shadows go blue rather than grey.
    shaded = shaded + vec3<f32>(-0.03, 0.01, 0.07) * snow * (1.0 - light);
    shaded = shaded + vec3<f32>(-0.015, 0.025, 0.11) * antarctic * (1.0 - light);
    // Glints: a few hashed cells catch the sun toward the eye.
    let cell = floor(wrap(w.xz) * 3.0);
    let view = normalize(frame.eye.xyz - w);
    let mirror = reflected(view * -1.0, n);
    let toward = smoothstep(0.55, 0.9, dot(mirror, frame.light_direction.xyz));
    let glint = step(0.975, hash2(cell)) * toward * snow * near * light;
    shaded = shaded + frame.light_color.rgb * glint * 0.9;
    let ice_reflection = smoothstep(0.78, 0.98, dot(mirror, frame.light_direction.xyz));
    let ice_glint = ice_reflection * ice_reflection * antarctic * (0.28 + 0.72 * near) * light;
    shaded = shaded + vec3<f32>(0.46, 0.78, 1.0) * ice_glint * 0.42;

    // Sparse ground spores appear as small mint pools around grassy, level ground. The 0.5
    // cells-per-metre grid tiles exactly across wrap()'s 1024 m period, preventing seams.
    let bio_grid = wrap(w.xz) * 0.5;
    let bio_cell = floor(bio_grid);
    let bio_local = fract(bio_grid);
    let bio_center = vec2<f32>(hash2(bio_cell + vec2<f32>(31.0, 7.0)), hash2(bio_cell + vec2<f32>(83.0, 19.0)));
    let bio_sparse = step(0.79, hash2(bio_cell + vec2<f32>(127.0, 43.0)));
    let bio_spot = 1.0 - smoothstep(0.025, 0.095, length(bio_local - bio_center));
    let green_cover = smoothstep(0.025, 0.16, base.g - base.r);
    let bio_ground = bio_spot * bio_sparse * green_cover * (1.0 - steep) * (1.0 - snow) * near * frame.horizon.a;
    let bio_pulse = 0.82 + 0.18 * sin(frame.params.x * 1.1 + hash2(bio_cell) * 6.28);
    shaded = shaded + vec3<f32>(0.10, 0.72, 0.48) * bio_ground * bio_pulse * 0.75;
    return vec4<f32>(hazed(shaded, w, 0.0), 1.0);
}
