struct SkyOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex fn vertex_main(@builtin(vertex_index) index: u32) -> SkyOut {
    let x = f32((index << 1u) & 2u);
    let y = f32(index & 2u);
    var out: SkyOut;
    out.clip = vec4<f32>(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.999, 1.0);
    out.uv = vec2<f32>(x, y);
    return out;
}

@fragment fn frag_main(in: SkyOut) -> @location(0) vec4<f32> {
    let ndc = vec2<f32>(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    let yaw = frame.camera.x;
    let pitch = frame.camera.y;
    let cp = cos(pitch);
    let sp = sin(pitch);
    let sy = sin(yaw);
    let cy = cos(yaw);
    let forward = vec3<f32>(sy * cp, sp, cy * cp);
    let right = vec3<f32>(cy, 0.0, -sy);
    let up = vec3<f32>(-sy * sp, cp, -cy * sp);
    let ray = normalize(forward + right * ndc.x * frame.camera.z * frame.camera.w + up * ndc.y * frame.camera.w);

    let horizon_t = smoothstep(-0.22, 0.72, ray.y);
    let base = mix(frame.horizon.rgb, frame.sky_zenith.rgb, horizon_t);
    let cloud_bands = sin(ray.x * 19.0 + ray.z * 13.0 + frame.params.x * 0.001) * 0.5
        + sin(ray.x * 37.0 - ray.z * 23.0 - frame.params.x * 0.0007) * 0.25;
    let cloud_shape = smoothstep(0.05, 0.58, cloud_bands + ray.y * 0.25) * frame.weather.y;
    let overcast = mix(vec3<f32>(0.28, 0.34, 0.42), vec3<f32>(0.53, 0.58, 0.62), max(ray.y, 0.0));
    var color = mix(base, overcast, cloud_shape * 0.34);

    let celestial = normalize(frame.light_direction.xyz);
    let alignment = dot(ray, celestial);
    let night = frame.horizon.a;
    let sun_core = smoothstep(0.99915, 0.99955, alignment);
    let sun_halo = smoothstep(0.9975, 0.9994, alignment);
    let moon_core = smoothstep(0.99955, 0.99982, alignment);
    let moon_halo = smoothstep(0.9985, 0.9997, alignment);
    let above_ground = 1.0 - frame.weather.z;
    color += vec3<f32>(1.0, 0.73, 0.38) * sun_halo * (1.0 - night) * above_ground * 0.22;
    color = mix(color, vec3<f32>(1.0, 0.91, 0.68), sun_core * (1.0 - night) * above_ground);
    color += vec3<f32>(0.35, 0.53, 0.95) * moon_halo * night * above_ground * 0.18;
    color = mix(color, vec3<f32>(0.76, 0.84, 1.0), moon_core * night * above_ground);

    // Rain is drawn as a consistent cool veil; individual streaks are composited at display resolution.
    color = mix(color, color * vec3<f32>(0.72, 0.82, 0.94), frame.weather.x * 0.24);
    if (frame.weather.w < 0.0) {
        let cell = floor(ray * 720.0);
        let hash = fract(sin(dot(cell, vec3<f32>(12.9898, 78.233, 37.719))) * 43758.5453);
        let stars = step(0.99955, hash);
        let twinkle = 0.65 + 0.35 * sin(frame.params.x * 2.4 + hash * 700.0);
        color += vec3<f32>(0.58, 0.74, 1.0) * stars * twinkle;
    }
    return vec4<f32>(color, 1.0);
}
