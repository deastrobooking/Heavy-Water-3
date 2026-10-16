//! CPU preview of a vehicle recipe for review images: the same generator meshes the game draws,
//! shaded with the character toon ramp, from a few fixed views. Used by `asset-compiler
//! vehicle-preview`; it needs no window or GPU, so it also runs in tests.
const std = @import("std");
const raster = @import("../character/raster.zig");
const toon = @import("../character/toon.zig");
const m = @import("../character/math.zig");
const spec_mod = @import("../character/spec.zig");
const car = @import("../vehicle/car.zig");
const Designs = @import("../vehicle/Designs.zig");
const Rgb = spec_mod.Rgb;
const Vec3 = m.Vec3;

pub const View = struct {
    eye: Vec3,
    target: Vec3 = Vec3.init(0, 0.55, 0),
    fovy: f32 = m.radians(32),
    width: usize = 480,
    height: usize = 320,
    ss: usize = 2,
    light: Vec3 = Vec3.init(0.45, 0.8, 0.5),
};

/// The three review views, in sheet order: front three-quarter, side, top.
pub const sheet_views = [3]View{
    .{ .eye = Vec3.init(3.9, 1.9, 4.6) },
    .{ .eye = Vec3.init(6.4, 0.8, 0.0) },
    .{ .eye = Vec3.init(0.0, 7.4, 1.0), .target = Vec3.init(0, 0, 0) },
};

const Shader = struct {
    colors: []const [3]f32,
    eye: Vec3,
    light: Vec3,
    emissive: bool,

    pub fn fragment(s: Shader, f: raster.Fragment) ?Rgb {
        const c = s.colors[f.vtx];
        const base = Rgb.init(c[0], c[1], c[2]);
        if (s.emissive) return base;
        const view_dir = s.eye.sub(f.world).normalize();
        return toon.shadeToon(base, f.normal, s.light, view_dir, 1.0, .{});
    }
};

fn drawMesh(gpa: std.mem.Allocator, img: *raster.Image, vp: m.Mat4, source: *const @import("../character/mesh.zig").Mesh, palette: Designs.Palette, shader_view: View, emissive: bool) !void {
    const mesh = try Designs.renderMesh(gpa, source, palette);
    defer mesh.deinit(gpa);
    const pos = try gpa.alloc(Vec3, mesh.vertices.len);
    defer gpa.free(pos);
    const nrm = try gpa.alloc(Vec3, mesh.vertices.len);
    defer gpa.free(nrm);
    const uvs = try gpa.alloc(m.Vec2, mesh.vertices.len);
    defer gpa.free(uvs);
    const colors = try gpa.alloc([3]f32, mesh.vertices.len);
    defer gpa.free(colors);
    for (mesh.vertices, pos, nrm, uvs, colors) |v, *p, *n, *uv, *c| {
        p.* = Vec3.init(v.position[0], v.position[1], v.position[2]);
        n.* = Vec3.init(v.normal[0], v.normal[1], v.normal[2]);
        uv.* = .{};
        c.* = v.color;
    }
    raster.drawTriangles(img, vp, pos, nrm, uvs, mesh.indices, .none, 0, Shader{ .colors = colors, .eye = shader_view.eye, .light = shader_view.light.normalize(), .emissive = emissive });
}

pub fn render(gpa: std.mem.Allocator, parts: *const car.Parts, palette: Designs.Palette, view: View) !raster.Image {
    const w = view.width * view.ss;
    const h = view.height * view.ss;
    var img = try raster.Image.init(gpa, w, h, Rgb.hex(0xf3eefc));
    defer img.deinit(gpa);
    img.fillGradient(Rgb.hex(0xf3eefc), Rgb.hex(0xd9e4f7));
    const aspect = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
    const vp = m.Mat4.perspective(view.fovy, aspect, 0.05, 80).mul(m.Mat4.lookAt(view.eye, view.target, Vec3.unit_y));
    try drawMesh(gpa, &img, vp, &parts.body, palette, view, false);
    try drawMesh(gpa, &img, vp, &parts.lights, palette, view, true);
    // The rotor is stored once at the origin; the game draws a copy at each pivot.
    for (parts.pivots) |pivot| {
        var moved = try cloneAt(gpa, &parts.rotor, pivot);
        defer moved.deinit(gpa);
        try drawMesh(gpa, &img, vp, &moved, palette, view, false);
    }
    return img.downsample(gpa, view.ss);
}

fn cloneAt(gpa: std.mem.Allocator, source: *const @import("../character/mesh.zig").Mesh, offset: Vec3) !@import("../character/mesh.zig").Mesh {
    var out: @import("../character/mesh.zig").Mesh = .{};
    errdefer out.deinit(gpa);
    try out.vertices.appendSlice(gpa, source.vertices.items);
    try out.indices.appendSlice(gpa, source.indices.items);
    for (out.vertices.items) |*v| v.pos = v.pos.add(offset);
    return out;
}

/// Three views side by side in one image.
pub fn renderSheet(gpa: std.mem.Allocator, parts: *const car.Parts, palette: Designs.Palette) !raster.Image {
    const v = sheet_views[0];
    var sheet = try raster.Image.init(gpa, v.width * sheet_views.len, v.height, Rgb.hex(0xf3eefc));
    errdefer sheet.deinit(gpa);
    // Back the cameras off in proportion to the car's reach so a long or wide car stays in frame.
    var reach: f32 = 0;
    for (parts.body.vertices.items) |p| reach = @max(reach, @sqrt(p.pos.x * p.pos.x + p.pos.y * p.pos.y + p.pos.z * p.pos.z));
    const fit = @max(1.15, reach / 2.4);
    for (sheet_views, 0..) |base_view, i| {
        var view = base_view;
        view.eye = view.target.add(view.eye.sub(view.target).scale(fit));
        var one = try render(gpa, parts, palette, view);
        defer one.deinit(gpa);
        raster.blit(&sheet, &one, i * v.width, 0);
    }
    return sheet;
}

test "a preview sheet renders for a shipped design and is not blank" {
    const a = std.testing.allocator;
    var parts = try car.build(a, Designs.spec(.dart));
    defer parts.deinit(a);
    var sheet = try renderSheet(a, &parts, Designs.palette(.dart));
    defer sheet.deinit(a);
    try std.testing.expectEqual(@as(usize, 480 * 3), sheet.w);
    // The car must change pixels away from the background gradient in every view.
    var drawn: usize = 0;
    for (0..3) |view| {
        var changed = false;
        var y: usize = 0;
        while (y < 320 and !changed) : (y += 4) {
            var x: usize = 0;
            while (x < 480) : (x += 4) {
                const px = sheet.color[y * sheet.w + view * 480 + x];
                const bg = sheet.color[y * sheet.w + view * 480 + 0];
                if (px.r != bg.r or px.g != bg.g or px.b != bg.b) {
                    changed = true;
                    break;
                }
            }
        }
        if (changed) drawn += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), drawn);
}
