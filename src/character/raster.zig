//! Minimal software rasterizer for previews, thumbnails and tests.
//! Perspective-correct attributes, z-buffer, back/front-face culling, and an
//! inverted-hull outline pass — the same pipeline a GPU renderer would use,
//! so what you see here is what the shaders should produce.

const std = @import("std");
const m = @import("math.zig");
const spec_mod = @import("spec.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Vec4 = m.Vec4;
const Mat4 = m.Mat4;
const Rgb = spec_mod.Rgb;
const Allocator = std.mem.Allocator;

pub const Image = struct {
    w: usize,
    h: usize,
    color: []Rgb,
    depth: []f32,

    pub fn init(gpa: Allocator, w: usize, h: usize, clear: Rgb) !Image {
        const c = try gpa.alloc(Rgb, w * h);
        @memset(c, clear);
        const d = try gpa.alloc(f32, w * h);
        @memset(d, std.math.inf(f32));
        return .{ .w = w, .h = h, .color = c, .depth = d };
    }
    pub fn deinit(img: *Image, gpa: Allocator) void {
        gpa.free(img.color);
        gpa.free(img.depth);
    }
    /// Vertical gradient background.
    pub fn fillGradient(img: *Image, top: Rgb, bottom: Rgb) void {
        for (0..img.h) |y| {
            const t = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(img.h - 1));
            const c: Rgb = .{ .r = m.lerp(top.r, bottom.r, t), .g = m.lerp(top.g, bottom.g, t), .b = m.lerp(top.b, bottom.b, t) };
            @memset(img.color[y * img.w ..][0..img.w], c);
        }
    }
    /// Box-filter downsample by an integer factor (supersampling AA).
    pub fn downsample(img: *const Image, gpa: Allocator, factor: usize) !Image {
        var out = try Image.init(gpa, img.w / factor, img.h / factor, Rgb.init(0, 0, 0));
        const inv = 1.0 / @as(f32, @floatFromInt(factor * factor));
        for (0..out.h) |y| for (0..out.w) |x| {
            var acc = Rgb.init(0, 0, 0);
            for (0..factor) |dy| for (0..factor) |dx| {
                const c = img.color[(y * factor + dy) * img.w + x * factor + dx];
                acc = .{ .r = acc.r + c.r, .g = acc.g + c.g, .b = acc.b + c.b };
            };
            out.color[y * out.w + x] = .{ .r = acc.r * inv, .g = acc.g * inv, .b = acc.b * inv };
        };
        return out;
    }
    /// PNG encoder (8-bit RGB, zlib "stored" blocks — no compression library
    /// needed, so this stays pure Zig and dependency-free).
    pub fn writePng(img: *const Image, gpa: Allocator, out: *std.ArrayList(u8)) !void {
        // raw scanlines with filter byte 0
        var raw: std.ArrayList(u8) = .empty;
        defer raw.deinit(gpa);
        try raw.ensureTotalCapacity(gpa, img.h * (img.w * 3 + 1));
        for (0..img.h) |y| {
            raw.appendAssumeCapacity(0);
            for (img.color[y * img.w ..][0..img.w]) |c| {
                raw.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.r) * 255)));
                raw.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.g) * 255)));
                raw.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.b) * 255)));
            }
        }
        // zlib stream of stored deflate blocks
        var z: std.ArrayList(u8) = .empty;
        defer z.deinit(gpa);
        try z.appendSlice(gpa, &.{ 0x78, 0x01 });
        var off: usize = 0;
        while (true) {
            const n = @min(raw.items.len - off, 65535);
            const final: u8 = if (off + n == raw.items.len) 1 else 0;
            const len: u16 = @intCast(n);
            try z.append(gpa, final);
            try z.appendSlice(gpa, &std.mem.toBytes(std.mem.nativeToLittle(u16, len)));
            try z.appendSlice(gpa, &std.mem.toBytes(std.mem.nativeToLittle(u16, ~len)));
            try z.appendSlice(gpa, raw.items[off..][0..n]);
            off += n;
            if (final == 1) break;
        }
        try z.appendSlice(gpa, &std.mem.toBytes(std.mem.nativeToBig(u32, std.hash.Adler32.hash(raw.items))));

        try out.appendSlice(gpa, &.{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });
        var ihdr: [13]u8 = undefined;
        std.mem.writeInt(u32, ihdr[0..4], @intCast(img.w), .big);
        std.mem.writeInt(u32, ihdr[4..8], @intCast(img.h), .big);
        ihdr[8] = 8; // bit depth
        ihdr[9] = 2; // truecolor RGB
        ihdr[10] = 0;
        ihdr[11] = 0;
        ihdr[12] = 0;
        try pngChunk(gpa, out, "IHDR", &ihdr);
        try pngChunk(gpa, out, "IDAT", z.items);
        try pngChunk(gpa, out, "IEND", &.{});
    }

    /// Binary PPM (P6), sRGB-ish (no conversion; colors are authored in display space).
    pub fn writePpm(img: *const Image, gpa: Allocator, out: *std.ArrayList(u8)) !void {
        try out.print(gpa, "P6\n{d} {d}\n255\n", .{ img.w, img.h });
        try out.ensureUnusedCapacity(gpa, img.w * img.h * 3);
        for (img.color) |c| {
            out.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.r) * 255)));
            out.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.g) * 255)));
            out.appendAssumeCapacity(@intFromFloat(@round(m.saturate(c.b) * 255)));
        }
    }
};

fn pngChunk(gpa: Allocator, out: *std.ArrayList(u8), kind: *const [4]u8, data: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(data.len), .big);
    try out.appendSlice(gpa, &len);
    try out.appendSlice(gpa, kind);
    try out.appendSlice(gpa, data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    var c: [4]u8 = undefined;
    std.mem.writeInt(u32, &c, crc.final(), .big);
    try out.appendSlice(gpa, &c);
}

/// Copy `src` into `dst` at (x, y), clipped.
pub fn blit(dst: *Image, src: *const Image, x: usize, y: usize) void {
    for (0..src.h) |sy| {
        const dy = y + sy;
        if (dy >= dst.h) break;
        const n = @min(src.w, dst.w -| x);
        @memcpy(dst.color[dy * dst.w + x ..][0..n], src.color[sy * src.w ..][0..n]);
    }
}

pub const Cull = enum { back, front, none };

/// Interpolated per-pixel inputs handed to the fragment callback.
pub const Fragment = struct {
    world: Vec3,
    normal: Vec3,
    uv: Vec2,
    /// Flat (provoking-vertex) attributes.
    tri: u32,
    vtx: u32,
    /// Screen-space UV derivative estimate (for SDF antialiasing).
    uv_aa: f32,
    /// Current framebuffer color (for blending effects like blob shadows).
    dst: Rgb,
};

/// Draw an indexed triangle list.
///   `pos`/`nrm`/`uv` are per-vertex world-space attributes.
///   `shader` provides `fn fragment(self, Fragment) ?Rgb` (null = discard).
pub fn drawTriangles(
    img: *Image,
    view_proj: Mat4,
    pos: []const Vec3,
    nrm: []const Vec3,
    uvs: []const Vec2,
    indices: []const u32,
    cull: Cull,
    depth_bias: f32,
    shader: anytype,
) void {
    const wf: f32 = @floatFromInt(img.w);
    const hf: f32 = @floatFromInt(img.h);
    var tri: usize = 0;
    while (tri + 2 < indices.len) : (tri += 3) {
        const ids = [3]u32{ indices[tri], indices[tri + 1], indices[tri + 2] };
        var sx: [3]f32 = undefined;
        var sy: [3]f32 = undefined;
        var sz: [3]f32 = undefined;
        var iw: [3]f32 = undefined;
        var behind = false;
        for (ids, 0..) |id, k| {
            const c = view_proj.transformVec4(Vec4.init(pos[id].x, pos[id].y, pos[id].z, 1));
            if (c.w <= 1e-4) {
                behind = true;
                break;
            }
            iw[k] = 1.0 / c.w;
            sx[k] = (c.x * iw[k] * 0.5 + 0.5) * wf;
            sy[k] = (1 - (c.y * iw[k] * 0.5 + 0.5)) * hf;
            sz[k] = c.z * iw[k];
        }
        if (behind) continue;
        const area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
        if (@abs(area) < 1e-9) continue;
        // screen y is flipped, so CCW-in-world front faces have negative area here
        const front = area < 0;
        switch (cull) {
            .back => if (!front) continue,
            .front => if (front) continue,
            .none => {},
        }
        const minx: usize = @intFromFloat(m.clamp(@floor(@min(sx[0], @min(sx[1], sx[2]))), 0, wf - 1));
        const maxx: usize = @intFromFloat(m.clamp(@ceil(@max(sx[0], @max(sx[1], sx[2]))), 0, wf - 1));
        const miny: usize = @intFromFloat(m.clamp(@floor(@min(sy[0], @min(sy[1], sy[2]))), 0, hf - 1));
        const maxy: usize = @intFromFloat(m.clamp(@ceil(@max(sy[0], @max(sy[1], sy[2]))), 0, hf - 1));
        if (maxx < minx or maxy < miny) continue;
        // UV footprint per pixel (crude but stable): uv span / screen span
        const uv_span = @max(uvs[ids[0]].sub(uvs[ids[1]]).length(), uvs[ids[0]].sub(uvs[ids[2]]).length());
        const px_span = @max(@sqrt(@abs(area)), 1.0);
        const uv_aa = uv_span / px_span;
        const inv_area = 1.0 / area;

        var y = miny;
        while (y <= maxy) : (y += 1) {
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            var x = minx;
            while (x <= maxx) : (x += 1) {
                const px = @as(f32, @floatFromInt(x)) + 0.5;
                var b0 = ((sx[1] - px) * (sy[2] - py) - (sx[2] - px) * (sy[1] - py)) * inv_area;
                var b1 = ((sx[2] - px) * (sy[0] - py) - (sx[0] - px) * (sy[2] - py)) * inv_area;
                var b2 = 1 - b0 - b1;
                if (b0 < 0 or b1 < 0 or b2 < 0) continue;
                const z = b0 * sz[0] + b1 * sz[1] + b2 * sz[2] + depth_bias;
                const di = y * img.w + x;
                if (z >= img.depth[di]) continue;
                // perspective-correct weights
                b0 *= iw[0];
                b1 *= iw[1];
                b2 *= iw[2];
                const s = 1.0 / (b0 + b1 + b2);
                b0 *= s;
                b1 *= s;
                b2 *= s;
                const frag: Fragment = .{
                    .world = pos[ids[0]].scale(b0).add(pos[ids[1]].scale(b1)).add(pos[ids[2]].scale(b2)),
                    .normal = nrm[ids[0]].scale(b0).add(nrm[ids[1]].scale(b1)).add(nrm[ids[2]].scale(b2)).normalize(),
                    .uv = uvs[ids[0]].scale(b0).add(uvs[ids[1]].scale(b1)).add(uvs[ids[2]].scale(b2)),
                    .tri = @intCast(tri / 3),
                    .vtx = ids[0],
                    .uv_aa = uv_aa,
                    .dst = img.color[di],
                };
                if (shader.fragment(frag)) |c| {
                    img.depth[di] = z;
                    img.color[di] = c;
                }
            }
        }
    }
}

test "rasterize a front-facing triangle" {
    const gpa = std.testing.allocator;
    var img = try Image.init(gpa, 32, 32, Rgb.init(0, 0, 0));
    defer img.deinit(gpa);
    const vp = Mat4.perspective(1.0, 1.0, 0.1, 10).mul(Mat4.lookAt(Vec3.init(0, 0, 3), Vec3.zero, Vec3.unit_y));
    const pos = [_]Vec3{ Vec3.init(-1, -1, 0), Vec3.init(1, -1, 0), Vec3.init(0, 1, 0) };
    const nrm = [_]Vec3{ Vec3.unit_z, Vec3.unit_z, Vec3.unit_z };
    const uvs = [_]Vec2{ .{}, .{}, .{} };
    const idx = [_]u32{ 0, 1, 2 };
    const S = struct {
        fn fragment(_: @This(), _: Fragment) ?Rgb {
            return Rgb.init(1, 1, 1);
        }
    };
    drawTriangles(&img, vp, &pos, &nrm, &uvs, &idx, .back, 0, S{});
    try std.testing.expectEqual(@as(f32, 1), img.color[16 * 32 + 16].r);
    // reversed winding is culled
    var img2 = try Image.init(gpa, 32, 32, Rgb.init(0, 0, 0));
    defer img2.deinit(gpa);
    const idx2 = [_]u32{ 0, 2, 1 };
    drawTriangles(&img2, vp, &pos, &nrm, &uvs, &idx2, .back, 0, S{});
    try std.testing.expectEqual(@as(f32, 0), img2.color[16 * 32 + 16].r);
}
