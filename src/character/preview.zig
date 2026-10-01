//! Toon preview renderer for a skinned Character, built on `raster` + `toon`.
//! This is the reference for what a GPU implementation should output:
//!   pass 1: cel-shaded surfaces (face uses the face-shadow map + SDF eyes)
//!   pass 2: inverted-hull outlines with constant screen-space width

const std = @import("std");
const m = @import("math.zig");
const mesh_mod = @import("mesh.zig");
const spec_mod = @import("spec.zig");
const toon = @import("toon.zig");
const raster = @import("raster.zig");
const character = @import("character.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Mat4 = m.Mat4;
const Rgb = spec_mod.Rgb;
const Allocator = std.mem.Allocator;

pub const View = struct {
    eye: Vec3,
    target: Vec3,
    fovy: f32 = m.radians(30),
    width: usize = 512,
    height: usize = 768,
    /// Supersampling factor for antialiasing.
    ss: usize = 2,
    /// Direction TOWARD the light.
    light: Vec3 = Vec3.init(0.45, 0.75, 0.55),
    outline_px: f32 = 1.6,
    bg_top: Rgb = Rgb.hex(0xf3eefc),
    bg_bottom: Rgb = Rgb.hex(0xd9e4f7),
    toon: toon.ToonParams = .{},
    expression: toon.Expression = .{},
};

/// Posed geometry: skinned positions/normals plus the head frame for face shading.
pub const Posed = struct {
    pos: []const Vec3,
    nrm: []const Vec3,
    head_fwd: Vec3,
    head_left: Vec3,
};

const SurfaceShader = struct {
    ch: *const character.Character,
    posed: Posed,
    view: *const View,
    light: Vec3,

    pub fn fragment(s: SurfaceShader, f: raster.Fragment) ?Rgb {
        const v = s.ch.mesh.vertices.items[f.vtx];
        const base = s.ch.palette.items[s.ch.color_index.items[f.vtx]];
        const vdir = s.view.eye.sub(f.world).normalize();
        var n = f.normal;
        if (n.dot(vdir) < 0 and v.material == .cloth_bottom) n = n.neg(); // thin cloth seen from inside
        const tp = s.view.toon;

        if (v.region == .face and f.uv.x >= 0 and f.uv.y >= 0) {
            const lit = toon.faceLit(f.uv, s.posed.head_fwd, s.posed.head_left, s.light, 0.02);
            var c = toon.shadeToon(base, n, s.light, vdir, lit, .{
                .threshold = -2, // n.l ignored on the face; the shadow map decides
                .softness = tp.softness,
                .shadow_tint = tp.shadow_tint,
                .deep_threshold = -3,
                .rim_width = 0,
                .rim_strength = 0,
            });
            const d = toon.faceDecal(f.uv, s.ch.spec.eyes, s.view.expression, @max(f.uv_aa * 1.5, 0.0025));
            if (d.alpha > 0) c = toon.mix(c, toon.scalec(d.color, m.lerp(0.9, 1.0, lit)), m.saturate(d.alpha));
            return c;
        }
        var c = toon.shadeToon(base, n, s.light, vdir, 1.0, tp);
        if (v.material == .hair) {
            const ring = toon.angelRing(f.uv, m.saturate(n.dot(vdir)), 0.32, 0.05);
            c = toon.mix(c, toon.addc(base, Rgb.init(0.30, 0.30, 0.36)), ring * 0.8);
        }
        return c;
    }
};

const OutlineShader = struct {
    ch: *const character.Character,
    pub fn fragment(s: OutlineShader, f: raster.Fragment) ?Rgb {
        const base = s.ch.palette.items[s.ch.color_index.items[f.vtx]];
        // tinted lines read softer than black: base * dark tint
        return toon.mulc(base, Rgb.init(0.30, 0.22, 0.30));
    }
};

const FloorShader = struct {
    center: Vec3,
    radius: f32,
    pub fn fragment(s: FloorShader, f: raster.Fragment) ?Rgb {
        const d = f.world.sub(s.center).length() / s.radius;
        const a = (1 - m.smoothstep(0.55, 1.0, d)) * 0.22;
        if (a <= 0.001) return null;
        return toon.mix(f.dst, Rgb.init(0.45, 0.42, 0.62), a);
    }
};

pub fn render(gpa: Allocator, ch: *const character.Character, posed: Posed, view: View) !raster.Image {
    const W = view.width * view.ss;
    const Hh = view.height * view.ss;
    var img = try raster.Image.init(gpa, W, Hh, view.bg_top);
    defer img.deinit(gpa);
    img.fillGradient(view.bg_top, view.bg_bottom);

    const aspect = @as(f32, @floatFromInt(W)) / @as(f32, @floatFromInt(Hh));
    const vmat = Mat4.lookAt(view.eye, view.target, Vec3.unit_y);
    const vp = Mat4.perspective(view.fovy, aspect, 0.05, 50).mul(vmat);

    const uvs = try gpa.alloc(Vec2, ch.mesh.vertices.items.len);
    defer gpa.free(uvs);
    for (ch.mesh.vertices.items, uvs) |v, *u| u.* = v.uv;

    // floor blob shadow
    {
        const c = Vec3.init(posed.pos[0].x * 0, 0.0005, 0);
        var disk_pos: [33]Vec3 = undefined;
        var disk_nrm: [33]Vec3 = undefined;
        var disk_uv: [33]Vec2 = undefined;
        var disk_idx: [96]u32 = undefined;
        disk_pos[0] = c;
        for (0..32) |i| {
            const a = @as(f32, @floatFromInt(i)) / 32.0 * m.tau;
            disk_pos[i + 1] = c.add(Vec3.init(@cos(a) * 0.32, 0, -@sin(a) * 0.22));
        }
        for (&disk_nrm) |*n| n.* = Vec3.unit_y;
        for (&disk_uv) |*u| u.* = .{};
        for (0..32) |i| {
            disk_idx[i * 3] = 0;
            disk_idx[i * 3 + 1] = @intCast(i + 1);
            disk_idx[i * 3 + 2] = @intCast((i + 1) % 32 + 1);
        }
        raster.drawTriangles(&img, vp, &disk_pos, &disk_nrm, &disk_uv, &disk_idx, .none, 0, FloorShader{ .center = c, .radius = 0.32 });
        @memset(img.depth, std.math.inf(f32));
    }

    // pass 1: surfaces
    const light = view.light.normalize();
    raster.drawTriangles(&img, vp, posed.pos, posed.nrm, uvs, ch.mesh.indices.items, .back, 0, SurfaceShader{
        .ch = ch,
        .posed = posed,
        .view = &view,
        .light = light,
    });

    // pass 2: inverted hull outlines
    const on = try gpa.alloc(Vec3, posed.pos.len);
    defer gpa.free(on);
    {
        var tmp: mesh_mod.Mesh = .{};
        // view the posed data through a temporary mesh (positions + normals)
        try tmp.vertices.ensureTotalCapacity(gpa, posed.pos.len);
        defer tmp.deinit(gpa);
        for (posed.pos, posed.nrm) |p, n| tmp.vertices.appendAssumeCapacity(.{ .pos = p, .normal = n });
        try mesh_mod.computeOutlineNormals(gpa, &tmp, on);
    }
    const hull = try gpa.alloc(Vec3, posed.pos.len);
    defer gpa.free(hull);
    for (posed.pos, on, ch.mesh.vertices.items, 0..) |p, n, v, i| {
        const depth = vmat.transformPoint(p).z * -1;
        var w = toon.outlineWidth(view.outline_px * @as(f32, @floatFromInt(view.ss)), depth, view.fovy, @floatFromInt(Hh), 0.0004, 0.006);
        if (v.region == .face) w *= 0.25; // keep the nose/cheek free of lines
        if (v.material == .hair) w *= 0.9;
        hull[i] = p.addScaled(n, w);
    }
    raster.drawTriangles(&img, vp, hull, on, uvs, ch.mesh.indices.items, .front, 0, OutlineShader{ .ch = ch });

    return img.downsample(gpa, view.ss);
}
