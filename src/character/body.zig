//! Skeleton + body generation from a CharacterSpec.
//!
//! The body is a set of overlapping lofted parts (torso, neck, head, arms,
//! hands, legs, feet). Each part's rings know where they sit along their bone
//! chain, so skin weights are computed analytically instead of auto-weighted.

const std = @import("std");
const m = @import("math.zig");
const curve = @import("curve.zig");
const mesh_mod = @import("mesh.zig");
const skel_mod = @import("skeleton.zig");
const loft_mod = @import("loft.zig");
const spec_mod = @import("spec.zig");

const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Vertex = mesh_mod.Vertex;
const SkinBlend = mesh_mod.SkinBlend;
const Region = mesh_mod.Region;
const Skeleton = skel_mod.Skeleton;
const Joint = skel_mod.Joint;
const Section = loft_mod.Section;
const CharacterSpec = spec_mod.CharacterSpec;
const Allocator = std.mem.Allocator;

/// Derived measurements shared by body, clothing and hair generators.
pub const Landmarks = struct {
    H: f32, // head height
    /// Body unit: height / 6.3. Torso and limb girths scale with this instead of
    /// head height, so big-headed (chibi) specs keep sane body proportions.
    B: f32,
    height: f32,
    chin_y: f32,
    shoulder_y: f32,
    crotch_y: f32,
    waist_y: f32,
    waist_half_width: f32,
    waist_half_depth: f32,
    hip_half_width: f32,
    head_half_width: f32,
    /// Scalp ellipsoid used to root hair (slightly larger than the skull).
    scalp_center: Vec3,
    scalp_radii: Vec3,
    /// Arm direction in rest pose for the left arm (+X side).
    arm_dir_l: Vec3,
    upper_arm_len: f32,
    forearm_len: f32,
    hand_len: f32,
    foot_len: f32,
};

pub fn computeLandmarks(spec: CharacterSpec) Landmarks {
    const b = spec.body;
    const h = b.height;
    const H = h / b.head_ratio;
    const B = h / 6.3;
    const f = b.femininity;
    const chin_y = h - H;
    const shoulder_y = chin_y - 0.36 * B;
    const crotch_y = b.leg_ratio * h;
    const span = shoulder_y - crotch_y;
    const head_half = 0.5 * b.head_width * H;
    const scalp_c = Vec3.init(0, chin_y + 0.60 * H, -0.04 * H);
    return .{
        .H = H,
        .B = B,
        .height = h,
        .chin_y = chin_y,
        .shoulder_y = shoulder_y,
        .crotch_y = crotch_y,
        .waist_y = crotch_y + 0.47 * span,
        .waist_half_width = m.lerp(0.48, 0.40, f) * b.waist_width * B,
        .waist_half_depth = 0.33 * B,
        .hip_half_width = m.lerp(0.55, 0.64, f) * b.hip_width * B,
        .head_half_width = head_half,
        .scalp_center = scalp_c,
        .scalp_radii = Vec3.init(head_half * 1.08, (h - scalp_c.y) * 1.05, 0.52 * H),
        .arm_dir_l = Vec3.init(@cos(b.arm_rest_angle), -@sin(b.arm_rest_angle), 0),
        .upper_arm_len = 0.172 * h,
        .forearm_len = 0.142 * h,
        .hand_len = 0.092 * h,
        .foot_len = 0.13 * h,
    };
}

// ---------------------------------------------------------------- skeleton
pub fn buildSkeleton(gpa: Allocator, spec: CharacterSpec, lm: Landmarks) !Skeleton {
    const b = spec.body;
    const H = lm.B;
    const f = b.femininity;
    var s: Skeleton = .{};
    errdefer s.deinit(gpa);

    const span = lm.shoulder_y - lm.crotch_y;
    const outer_half = m.lerp(0.88, 0.72, f) * b.shoulder_width * H;
    const hip_x = m.lerp(0.30, 0.36, f) * b.hip_width * H;
    const thigh_y = lm.crotch_y + 0.10 * H;
    const ankle_y = 0.045 * lm.height;
    const knee_y = ankle_y + (thigh_y - ankle_y) * 0.47;

    // Order MUST match the Joint enum.
    const root = try s.addBone(gpa, "root", skel_mod.no_parent, Vec3.zero);
    const hips = try s.addBone(gpa, "hips", @intCast(root), Vec3.init(0, lm.crotch_y + 0.22 * span, -0.02 * H));
    const spine = try s.addBone(gpa, "spine", @intCast(hips), Vec3.init(0, lm.crotch_y + 0.50 * span, -0.04 * H));
    const chest = try s.addBone(gpa, "chest", @intCast(spine), Vec3.init(0, lm.crotch_y + 0.76 * span, -0.04 * H));
    const neck = try s.addBone(gpa, "neck", @intCast(chest), Vec3.init(0, lm.chin_y - 0.22 * H, -0.08 * H));
    _ = try s.addBone(gpa, "head", @intCast(neck), Vec3.init(0, lm.chin_y + 0.12 * lm.H, -0.10 * lm.H));

    inline for (.{ 1.0, -1.0 }, .{ "_l", "_r" }) |side, suffix| {
        const d = Vec3.init(lm.arm_dir_l.x * side, lm.arm_dir_l.y, 0);
        const sh = try s.addBone(gpa, "shoulder" ++ suffix, @intCast(chest), Vec3.init(0.12 * H * side, lm.shoulder_y - 0.05 * H, -0.03 * H));
        const ua_pos = Vec3.init((outer_half - 0.16 * H) * side, lm.shoulder_y - 0.12 * H, -0.05 * H);
        const ua = try s.addBone(gpa, "upper_arm" ++ suffix, @intCast(sh), ua_pos);
        const el_pos = ua_pos.addScaled(d, lm.upper_arm_len);
        const la = try s.addBone(gpa, "lower_arm" ++ suffix, @intCast(ua), el_pos);
        _ = try s.addBone(gpa, "hand" ++ suffix, @intCast(la), el_pos.addScaled(d, lm.forearm_len));
    }
    inline for (.{ 1.0, -1.0 }, .{ "_l", "_r" }) |side, suffix| {
        const th = try s.addBone(gpa, "thigh" ++ suffix, @intCast(hips), Vec3.init(hip_x * side, thigh_y, 0));
        const sn = try s.addBone(gpa, "shin" ++ suffix, @intCast(th), Vec3.init(hip_x * 0.92 * side, knee_y, 0.01 * H));
        const ankle = Vec3.init(hip_x * 0.88 * side, ankle_y, -0.03 * H);
        const ft = try s.addBone(gpa, "foot" ++ suffix, @intCast(sn), ankle);
        _ = try s.addBone(gpa, "toe" ++ suffix, @intCast(ft), Vec3.init(ankle.x, 0.03 * H, ankle.z + 0.62 * lm.foot_len));
    }
    std.debug.assert(s.count() == skel_mod.humanoid_joint_count);
    return s;
}

// ---------------------------------------------------------------- helpers
/// Compact smooth bump: 1 at r=0, 0 at r>=1, C1 continuous.
inline fn bump(r2: f32) f32 {
    if (r2 >= 1) return 0;
    const k = 1 - r2;
    return k * k;
}

fn sideIndex(comptime j_l: Joint, comptime j_r: Joint, side: f32) u16 {
    return if (side > 0) j_l.idx() else j_r.idx();
}

// ---------------------------------------------------------------- torso
const TorsoCtx = struct {
    y0: f32,
    y1: f32,
    ts: [7]f32,
    a: [7]f32,
    b: [7]f32,
    z: [7]f32,
    n: [7]f32,
    H: f32,
    bust: f32,
    bust_y: f32,
    bust_x: f32,
    butt_y: f32,
    hip_half: f32,
    crotch_y: f32,
    waist_y: f32,
    chest_lo_y: f32,
    pivots: [4]f32,

    pub fn section(c: *const TorsoCtx, t: f32) Section {
        return .{
            .a = curve.spline1D(&c.ts, &c.a, t),
            .b = curve.spline1D(&c.ts, &c.b, t),
            .n = curve.spline1D(&c.ts, &c.n, t),
            .offset = .{ .y = curve.spline1D(&c.ts, &c.z, t) },
        };
    }
    pub fn displace(c: *const TorsoCtx, _: f32, _: f32, p: Vec3, _: curve.Frame) Vec3 {
        var out = p;
        // Bust: two compact bumps on the front, pushed forward and slightly up/out.
        if (c.bust > 0 and p.z > 0) {
            inline for (.{ 1.0, -1.0 }) |sd| {
                const dx = (p.x - c.bust_x * sd) / (0.36 * c.H);
                const dy = (p.y - c.bust_y) / (0.34 * c.H);
                const w = bump(dx * dx + dy * dy);
                out = out.add(Vec3.init(0.012 * c.H * sd, 0.02 * c.H, 0.22 * c.H).scale(w * c.bust));
            }
        }
        // Glutes: soft bumps on the back.
        if (p.z < 0) {
            inline for (.{ 1.0, -1.0 }) |sd| {
                const dx = (p.x - 0.30 * c.hip_half * sd) / (0.42 * c.H);
                const dy = (p.y - c.butt_y) / (0.36 * c.H);
                out.z -= 0.07 * c.H * bump(dx * dx + dy * dy);
            }
        }
        return out;
    }
    pub fn skin(c: *const TorsoCtx, _: f32, p: Vec3) SkinBlend {
        const pv = c.pivots[0];
        if (p.y < pv) {
            // Lower pelvis shares weight with the thigh on its side so the
            // crotch/hip area follows leg raises.
            const toward_leg = m.smoothstep(pv, c.crotch_y, p.y) * m.smoothstep(0.1 * c.hip_half, 0.7 * c.hip_half, @abs(p.x));
            const thigh: u16 = if (p.x > 0) Joint.thigh_l.idx() else Joint.thigh_r.idx();
            return .{ .a = Joint.hips.idx(), .b = thigh, .wb = 0.55 * toward_leg };
        }
        const joints = [_]u16{ Joint.hips.idx(), Joint.spine.idx(), Joint.chest.idx(), Joint.neck.idx() };
        return loft_mod.chainSkin(&joints, &c.pivots, p.y, 0.14 * c.H);
    }
    pub fn finish(c: *const TorsoCtx, v: *Vertex, _: f32, _: f32) void {
        v.region = if (v.pos.y < c.waist_y - 0.15 * c.H) .hips else if (v.pos.y < c.chest_lo_y) .belly else .chest;
    }
};

fn buildTorso(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton) !void {
    const H = lm.B; // body unit
    const f = spec.body.femininity;
    const sw = spec.body.shoulder_width;
    const y0 = lm.crotch_y - 0.02 * H;
    const y1 = lm.shoulder_y + 0.10 * H;
    const span = lm.shoulder_y - lm.crotch_y;
    const T = struct {
        fn at(yy: f32, lo: f32, hi: f32) f32 {
            return (yy - lo) / (hi - lo);
        }
    }.at;
    const hip_y = lm.crotch_y + 0.15 * span;
    const chest_y = lm.crotch_y + 0.74 * span;
    const armpit_y = lm.crotch_y + 0.88 * span;
    const ctx: TorsoCtx = .{
        .y0 = y0,
        .y1 = y1,
        .ts = .{ 0, T(hip_y, y0, y1), T(lm.waist_y, y0, y1), T(chest_y, y0, y1), T(armpit_y, y0, y1), T(lm.shoulder_y, y0, y1), 1 },
        .a = .{
            0.36 * H,
            lm.hip_half_width,
            lm.waist_half_width,
            m.lerp(0.62, 0.50, f) * H,
            m.lerp(0.70, 0.56, f) * sw * H,
            m.lerp(0.58, 0.46, f) * sw * H,
            0.20 * H,
        },
        .b = .{ 0.30 * H, m.lerp(0.40, 0.42, f) * H, lm.waist_half_depth, m.lerp(0.42, 0.35, f) * H, 0.36 * H, 0.27 * H, 0.18 * H },
        .z = .{ 0.0, -0.03 * H, 0.0, 0.02 * H, 0.0, -0.03 * H, -0.06 * H },
        .n = .{ 2.2, 2.4, 2.2, 2.4, 2.6, 2.8, 2.0 },
        .H = H,
        .bust = spec.body.bust * f,
        .bust_y = chest_y - 0.05 * H,
        .bust_x = 0.27 * H,
        .butt_y = hip_y - 0.05 * H,
        .hip_half = lm.hip_half_width,
        .crotch_y = lm.crotch_y,
        .waist_y = lm.waist_y,
        .chest_lo_y = chest_y - 0.35 * H,
        .pivots = .{ skel.worldPos(.hips).y, skel.worldPos(.spine).y, skel.worldPos(.chest).y, skel.worldPos(.neck).y },
    };
    const rows = spec.res(30, 8);
    const pts = try gpa.alloc(Vec3, rows);
    defer gpa.free(pts);
    for (pts, 0..) |*p, i| p.* = Vec3.init(0, m.lerp(y0, y1, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rows - 1))), 0);
    _ = try loft_mod.loft(gpa, mesh, pts, .{
        .cols = spec.res(32, 8),
        .ref_normal = Vec3.unit_x.neg(),
        .region = .chest,
        .cap_start = .dome,
        .cap_end = .dome,
        .cap_length = 0.5,
    }, &ctx);
}

// ---------------------------------------------------------------- neck
const NeckCtx = struct {
    r: f32,
    pivots: [3]f32,
    H: f32,
    pub fn section(c: *const NeckCtx, t: f32) Section {
        return .{ .a = c.r * m.lerp(1.15, 0.95, t), .b = c.r * m.lerp(1.05, 0.95, t) };
    }
    pub fn skin(c: *const NeckCtx, _: f32, p: Vec3) SkinBlend {
        const j = [_]u16{ Joint.chest.idx(), Joint.neck.idx(), Joint.head.idx() };
        return loft_mod.chainSkin(&j, &c.pivots, p.y, 0.10 * c.H);
    }
};

fn buildNeck(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton) !void {
    const H = lm.B; // body unit
    const pts = [_]Vec3{
        Vec3.init(0, lm.shoulder_y - 0.10 * H, -0.06 * H),
        Vec3.init(0, lm.chin_y - 0.10 * H, -0.08 * H),
        Vec3.init(0, lm.chin_y + 0.30 * lm.H, -0.12 * lm.H),
    };
    const line = try loft_mod.resamplePolyline(gpa, &pts, spec.res(8, 4));
    defer gpa.free(line);
    const ctx: NeckCtx = .{
        .r = m.lerp(0.17, 0.13, spec.body.femininity) * H,
        .pivots = .{ skel.worldPos(.chest).y, skel.worldPos(.neck).y, skel.worldPos(.head).y },
        .H = H,
    };
    _ = try loft_mod.loft(gpa, mesh, line, .{ .cols = spec.res(16, 6), .ref_normal = Vec3.unit_x.neg(), .region = .neck }, &ctx);
}

// ---------------------------------------------------------------- head
const HeadCtx = struct {
    chin_y: f32,
    H: f32,
    half: f32,
    us: [7]f32,
    a: [7]f32,
    b: [7]f32,
    z: [7]f32,
    y0: f32,
    y1: f32,

    pub fn uOf(c: *const HeadCtx, t: f32) f32 {
        return (m.lerp(c.y0, c.y1, t) - c.chin_y) / c.H;
    }
    pub fn section(c: *const HeadCtx, t: f32) Section {
        const u = c.uOf(t);
        return .{
            .a = curve.spline1D(&c.us, &c.a, u),
            .b = curve.spline1D(&c.us, &c.b, u),
            .n = 2.1,
            .offset = .{ .y = curve.spline1D(&c.us, &c.z, u) },
        };
    }
    pub fn displace(c: *const HeadCtx, _: f32, _: f32, p: Vec3, fr: curve.Frame) Vec3 {
        var out = p;
        const u = (p.y - c.chin_y) / c.H;
        const center_z = fr.origin.z + curve.spline1D(&c.us, &c.z, m.clamp(u, 0, 1));
        const fwd = p.z - center_z;
        if (fwd > 0) {
            // Flatten the face plane: anime faces read as a flat mask with a soft profile.
            const front = m.saturate(fwd / (0.45 * c.H));
            const lat = m.saturate(1 - @abs(p.x) / c.half);
            const band = m.smoothstep(0.12, 0.30, u) * (1 - m.smoothstep(0.62, 0.80, u));
            out.z -= fwd * 0.18 * front * front * lat * band;
            // Tiny nose: a narrow ridge ending in a small tip.
            const nx = p.x / (0.05 * c.H);
            const ny = (u - 0.36) / 0.08;
            out.z += 0.045 * c.H * bump(nx * nx + ny * ny) * front;
        }
        return out;
    }
    pub fn skin(_: *const HeadCtx, _: f32, _: Vec3) SkinBlend {
        return .{ .a = Joint.head.idx() };
    }
    pub fn finish(c: *const HeadCtx, v: *Vertex, _: f32, _: f32) void {
        const u = (v.pos.y - c.chin_y) / c.H;
        // planar face UV: x across face, y chin(0) -> crown(1)
        const fu = 0.5 + v.pos.x / (2.0 * c.half);
        const center_z = curve.spline1D(&c.us, &c.z, m.clamp(u, 0, 1));
        const is_face = v.pos.z - center_z > 0.18 * c.H and u > -0.05 and u < 0.80;
        v.region = if (is_face) .face else .head;
        // Non-face verts get UVs outside [0,1] so face decals (eyes) never land on them.
        v.uv = if (is_face) .{ .x = fu, .y = u } else .{ .x = -1, .y = -1 };
    }
};

fn headContext(spec: CharacterSpec, lm: Landmarks) HeadCtx {
    const H = lm.H;
    const half = lm.head_half_width;
    const jaw = spec.body.jaw_sharpness;
    return .{
        .chin_y = lm.chin_y,
        .H = H,
        .half = half,
        .us = .{ 0.08, 0.22, 0.36, 0.50, 0.62, 0.72, 0.80 },
        .a = .{ m.lerp(0.16, 0.10, jaw) * H, half * m.lerp(0.74, 0.56, jaw), half * 0.92, half, half * 1.02, half, half * 0.9 },
        .b = .{ 0.09 * H, 0.32 * H, 0.42 * H, 0.46 * H, 0.48 * H, 0.48 * H, 0.45 * H },
        .z = .{ 0.20 * H, 0.10 * H, 0.04 * H, 0.0, -0.02 * H, -0.03 * H, -0.04 * H },
        .y0 = lm.chin_y + 0.08 * H,
        .y1 = lm.chin_y + 0.72 * H,
    };
}

fn buildHead(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks) !void {
    const ctx = headContext(spec, lm);
    const y0 = ctx.y0;
    const y1 = ctx.y1;
    // Face features are baked from this UV field into game vertex colors. Keep the facial
    // silhouette smooth and the UV grid dense enough for eyes and mouth to survive at distance.
    const rows = spec.res(96, 48);
    const pts = try gpa.alloc(Vec3, rows);
    defer gpa.free(pts);
    for (pts, 0..) |*p, i| p.* = Vec3.init(0, m.lerp(y0, y1, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rows - 1))), 0);
    const top = ctx.section(1);
    _ = try loft_mod.loft(gpa, mesh, pts, .{
        .cols = spec.res(144, 64),
        .ref_normal = Vec3.unit_x.neg(),
        .region = .head,
        .cap_start = .dome,
        .cap_end = .dome,
        .cap_rings = spec.res(6, 3),
        .cap_length = (lm.height - y1) / @min(top.a, top.b),
    }, &ctx);
}

// ---------------------------------------------------------------- arms
const ArmCtx = struct {
    ts: [6]f32,
    r: [6]f32,
    len: f32,
    joints: [4]u16,
    pivots: [4]f32,
    elbow_s: f32,
    wrist_s: f32,
    side: f32,
    H: f32,
    pub fn section(c: *const ArmCtx, t: f32) Section {
        const r = curve.spline1D(&c.ts, &c.r, t);
        return .{ .a = r, .b = r * 0.9 };
    }
    pub fn skin(c: *const ArmCtx, t: f32, _: Vec3) SkinBlend {
        return loft_mod.chainSkin(&c.joints, &c.pivots, t * c.len, 0.09 * c.H);
    }
    pub fn finish(c: *const ArmCtx, v: *Vertex, t: f32, _: f32) void {
        const s = t * c.len;
        v.region = if (s < c.elbow_s) (if (c.side > 0) .upper_arm_l else .upper_arm_r) else if (s < c.wrist_s) (if (c.side > 0) .lower_arm_l else .lower_arm_r) else (if (c.side > 0) .hand_l else .hand_r);
    }
};

fn buildArm(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton, side: f32) !void {
    const H = lm.B; // body unit
    const lt = spec.body.limb_thickness * m.lerp(1.12, 1.0, spec.body.femininity);
    const sh = skel.worldPos(if (side > 0) .shoulder_l else .shoulder_r);
    const ua = skel.worldPos(if (side > 0) .upper_arm_l else .upper_arm_r);
    const el = skel.worldPos(if (side > 0) .lower_arm_l else .lower_arm_r);
    const wr = skel.worldPos(if (side > 0) .hand_l else .hand_r);
    const d = el.sub(ua).normalize();
    const start = ua.addScaled(d, -0.10 * H).add(Vec3.init(0, 0.03 * H, 0));
    const end = wr.addScaled(d, 0.04 * H);
    const poly = [_]Vec3{ start, ua, el, end };
    const len = curve.polylineLength(&poly);
    const s_ua = start.distance(ua);
    const s_el = s_ua + ua.distance(el);
    const s_wr = s_el + el.distance(wr);
    const t_ua = s_ua / len;
    const t_el = s_el / len;
    const ctx: ArmCtx = .{
        .ts = .{ 0, t_ua + 0.04, t_ua + 0.4 * (t_el - t_ua), t_el, t_el + 0.25 * (1 - t_el), 1 },
        .r = .{ 0.17 * H * lt, 0.20 * H * lt, 0.16 * H * lt, 0.12 * H * lt, 0.135 * H * lt, 0.085 * H * lt },
        .len = len,
        .joints = .{
            sideIndex(.shoulder_l, .shoulder_r, side),
            sideIndex(.upper_arm_l, .upper_arm_r, side),
            sideIndex(.lower_arm_l, .lower_arm_r, side),
            sideIndex(.hand_l, .hand_r, side),
        },
        .pivots = .{ s_ua - sh.distance(ua), s_ua, s_el, s_wr },
        .elbow_s = s_el,
        .wrist_s = s_wr,
        .side = side,
        .H = H,
    };
    const line = try loft_mod.resamplePolyline(gpa, &poly, spec.res(26, 8));
    defer gpa.free(line);
    _ = try loft_mod.loft(gpa, mesh, line, .{
        .cols = spec.res(18, 6),
        .ref_normal = Vec3.unit_z,
        .region = if (side > 0) .upper_arm_l else .upper_arm_r,
    }, &ctx);
}

// ---------------------------------------------------------------- hands
const SimpleCtx = struct {
    a0: f32,
    a1: f32,
    b0: f32,
    b1: f32,
    n: f32 = 2.0,
    joint: u16,
    pub fn section(c: *const SimpleCtx, t: f32) Section {
        const k = m.smoothstep(0, 1, t);
        return .{ .a = m.lerp(c.a0, c.a1, k), .b = m.lerp(c.b0, c.b1, k), .n = c.n };
    }
    pub fn skin(c: *const SimpleCtx, _: f32, _: Vec3) SkinBlend {
        return .{ .a = c.joint };
    }
};

fn buildHand(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton, side: f32) !void {
    const H = lm.B; // body unit
    const wr = skel.worldPos(if (side > 0) .hand_l else .hand_r);
    const el = skel.worldPos(if (side > 0) .lower_arm_l else .lower_arm_r);
    const d = wr.sub(el).normalize();
    const across = Vec3.unit_z; // thumb side is forward in rest pose
    const palm_n = d.cross(Vec3.unit_z).scale(side).normalize(); // faces the thigh
    const joint = sideIndex(.hand_l, .hand_r, side);
    const region: Region = if (side > 0) .hand_l else .hand_r;
    const palm_len = 0.50 * lm.hand_len;
    const cols = spec.res(14, 6);

    // palm
    {
        const pts = [_]Vec3{ wr.addScaled(d, -0.02 * H), wr.addScaled(d, 0.5 * palm_len), wr.addScaled(d, palm_len) };
        const ctx: SimpleCtx = .{ .a0 = 0.11 * H, .a1 = 0.15 * H, .b0 = 0.06 * H, .b1 = 0.045 * H, .n = 2.6, .joint = joint };
        _ = try loft_mod.loft(gpa, mesh, &pts, .{ .cols = cols, .ref_normal = across, .region = region, .cap_start = .dome, .cap_end = .dome, .cap_length = 0.6 }, &ctx);
    }
    // fingers: index..pinky, slight natural curl toward the palm
    const offs = [_]f32{ 0.10, 0.035, -0.035, -0.10 };
    const lens = [_]f32{ 0.44, 0.48, 0.45, 0.36 };
    for (offs, lens) |o, l| {
        const fl = l * lm.hand_len;
        const base = wr.addScaled(d, palm_len * 0.92).addScaled(across, o * H);
        const mid = base.addScaled(d, fl * 0.5).addScaled(palm_n, fl * 0.10);
        const tip = mid.addScaled(d.scale(0.75).add(palm_n.scale(0.6)).normalize(), fl * 0.5);
        const pts = try curveThrough(gpa, &.{ base, mid, tip }, 6);
        defer gpa.free(pts);
        const ctx: SimpleCtx = .{ .a0 = 0.032 * H, .a1 = 0.026 * H, .b0 = 0.028 * H, .b1 = 0.023 * H, .joint = joint };
        _ = try loft_mod.loft(gpa, mesh, pts, .{ .cols = spec.res(8, 5), .ref_normal = across, .region = region, .cap_end = .dome, .cap_rings = 2 }, &ctx);
    }
    // thumb
    {
        const base = wr.addScaled(d, 0.15 * palm_len).addScaled(across, 0.10 * H).addScaled(palm_n, 0.02 * H);
        const dir = d.scale(0.55).add(across.scale(0.55)).add(palm_n.scale(0.45)).normalize();
        const tl = 0.36 * lm.hand_len;
        const mid = base.addScaled(dir, tl * 0.5);
        const tip = mid.addScaled(dir.add(palm_n.scale(0.3)).normalize(), tl * 0.5);
        const pts = try curveThrough(gpa, &.{ base, mid, tip }, 6);
        defer gpa.free(pts);
        const ctx: SimpleCtx = .{ .a0 = 0.045 * H, .a1 = 0.03 * H, .b0 = 0.04 * H, .b1 = 0.027 * H, .joint = joint };
        _ = try loft_mod.loft(gpa, mesh, pts, .{ .cols = spec.res(8, 5), .ref_normal = across, .region = region, .cap_start = .dome, .cap_end = .dome, .cap_rings = 2 }, &ctx);
    }
}

fn curveThrough(gpa: Allocator, pts: []const Vec3, n: usize) ![]Vec3 {
    const out = try gpa.alloc(Vec3, n);
    curve.sampleCatmullRom(pts, out);
    return out;
}

// ---------------------------------------------------------------- legs
const LegCtx = struct {
    ts: [7]f32,
    r: [7]f32,
    calf_t: f32,
    knee_t: f32,
    len: f32,
    joints: [4]u16,
    pivots: [4]f32,
    side: f32,
    H: f32,
    pub fn section(c: *const LegCtx, t: f32) Section {
        const r = curve.spline1D(&c.ts, &c.r, t);
        // calves bulge backward, kneecaps forward
        const ct = (t - c.calf_t) / 0.12;
        const kt = (t - c.knee_t) / 0.05;
        const z = -0.035 * c.H * bump(ct * ct) + 0.015 * c.H * bump(kt * kt);
        return .{ .a = r, .b = r * 0.95, .n = 2.1, .offset = .{ .y = z } };
    }
    pub fn skin(c: *const LegCtx, t: f32, _: Vec3) SkinBlend {
        return loft_mod.chainSkin(&c.joints, &c.pivots, t * c.len, 0.10 * c.H);
    }
    pub fn finish(c: *const LegCtx, v: *Vertex, t: f32, _: f32) void {
        const s = t * c.len;
        const l = c.side > 0;
        v.region = if (s < c.pivots[2]) (if (l) .thigh_l else .thigh_r) else if (s < c.pivots[3]) (if (l) .shin_l else .shin_r) else (if (l) .foot_l else .foot_r);
    }
};

fn buildLeg(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton, side: f32) !void {
    const H = lm.B; // body unit
    const f = spec.body.femininity;
    const lt = spec.body.limb_thickness;
    const th = skel.worldPos(if (side > 0) .thigh_l else .thigh_r);
    const kn = skel.worldPos(if (side > 0) .shin_l else .shin_r);
    const an = skel.worldPos(if (side > 0) .foot_l else .foot_r);
    const start = th.add(Vec3.init(-0.04 * H * side, 0.24 * H, -0.02 * H));
    const end = an.add(Vec3.init(0, 0.02 * H, 0));
    const poly = [_]Vec3{ start, th, kn, end };
    const len = curve.polylineLength(&poly);
    const s_th = start.distance(th);
    const s_kn = s_th + th.distance(kn);
    const s_an = s_kn + kn.distance(an);
    const t_th = s_th / len;
    const t_kn = s_kn / len;
    const thigh = m.lerp(1.0, 1.12, f) * lt;
    const ctx: LegCtx = .{
        .ts = .{ 0, t_th, t_th + 0.35 * (t_kn - t_th), t_kn, t_kn + 0.30 * (1 - t_kn), 0.93, 1 },
        .r = .{ 0.30 * H * thigh, 0.31 * H * thigh, 0.25 * H * thigh, 0.16 * H * lt, 0.185 * H * lt, 0.105 * H * lt, 0.10 * H * lt },
        .calf_t = t_kn + 0.28 * (1 - t_kn),
        .knee_t = t_kn,
        .len = len,
        .joints = .{ Joint.hips.idx(), sideIndex(.thigh_l, .thigh_r, side), sideIndex(.shin_l, .shin_r, side), sideIndex(.foot_l, .foot_r, side) },
        .pivots = .{ 0, s_th, s_kn, s_an },
        .side = side,
        .H = H,
    };
    const line = try loft_mod.resamplePolyline(gpa, &poly, spec.res(32, 10));
    defer gpa.free(line);
    _ = try loft_mod.loft(gpa, mesh, line, .{ .cols = spec.res(20, 6), .ref_normal = Vec3.unit_x, .region = if (side > 0) .thigh_l else .thigh_r }, &ctx);
}

// ---------------------------------------------------------------- feet
const FootCtx = struct {
    ts: [5]f32,
    a: [5]f32,
    b: [5]f32,
    joints: [2]u16,
    pivots: [2]f32,
    len: f32,
    H: f32,
    pub fn section(c: *const FootCtx, t: f32) Section {
        return .{ .a = curve.spline1D(&c.ts, &c.a, t), .b = curve.spline1D(&c.ts, &c.b, t), .n = 2.7 };
    }
    pub fn skin(c: *const FootCtx, t: f32, _: Vec3) SkinBlend {
        return loft_mod.chainSkin(&c.joints, &c.pivots, t * c.len, 0.06 * c.H);
    }
};

fn buildFoot(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton, side: f32) !void {
    const H = lm.B; // body unit
    const an = skel.worldPos(if (side > 0) .foot_l else .foot_r);
    const toe = skel.worldPos(if (side > 0) .toe_l else .toe_r);
    const fl = lm.foot_len;
    const ctx_ts = [5]f32{ 0, 0.25, 0.55, 0.78, 1 };
    const ctx_a = [5]f32{ 0.11 * H, 0.14 * H, 0.155 * H, 0.15 * H, 0.10 * H };
    const ctx_b = [5]f32{ 0.10 * H, 0.15 * H, 0.10 * H, 0.07 * H, 0.055 * H };
    // centerline height follows the half-height so the sole sits on y=0
    const heel_z = an.z - 0.22 * fl;
    const rows = spec.res(14, 6);
    const pts = try gpa.alloc(Vec3, rows);
    defer gpa.free(pts);
    for (pts, 0..) |*p, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rows - 1));
        p.* = Vec3.init(an.x + side * 0.02 * H * t, curve.spline1D(&ctx_ts, &ctx_b, t) + 0.004, heel_z + t * fl);
    }
    const len = fl;
    const ctx: FootCtx = .{
        .ts = ctx_ts,
        .a = ctx_a,
        .b = ctx_b,
        .joints = .{ sideIndex(.foot_l, .foot_r, side), sideIndex(.toe_l, .toe_r, side) },
        .pivots = .{ 0, toe.z - heel_z },
        .len = len,
        .H = H,
    };
    _ = try loft_mod.loft(gpa, mesh, pts, .{
        .cols = spec.res(16, 6),
        .ref_normal = Vec3.unit_x,
        .region = if (side > 0) .foot_l else .foot_r,
        .cap_start = .dome,
        .cap_end = .dome,
        .cap_length = 0.5,
    }, &ctx);
}

// ---------------------------------------------------------------- public
/// Generate the full nude base body into `mesh`. Normals are computed.
pub fn buildBody(gpa: Allocator, mesh: *Mesh, spec: CharacterSpec, lm: Landmarks, skel: *const Skeleton) !void {
    try buildTorso(gpa, mesh, spec, lm, skel);
    try buildNeck(gpa, mesh, spec, lm, skel);
    try buildHead(gpa, mesh, spec, lm);
    for ([_]f32{ 1, -1 }) |side| {
        try buildArm(gpa, mesh, spec, lm, skel, side);
        try buildHand(gpa, mesh, spec, lm, skel, side);
        try buildLeg(gpa, mesh, spec, lm, skel, side);
        try buildFoot(gpa, mesh, spec, lm, skel, side);
    }
    mesh.computeNormals();
}

test "body builds, is skinned to valid joints, and fits the spec height" {
    const gpa = std.testing.allocator;
    const spec: CharacterSpec = .{};
    const lm = computeLandmarks(spec);
    var skel = try buildSkeleton(gpa, spec, lm);
    defer skel.deinit(gpa);
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    try buildBody(gpa, &mesh, spec, lm, &skel);
    try std.testing.expect(mesh.vertices.items.len > 3000);
    const bb = mesh.bounds();
    try std.testing.expectApproxEqAbs(spec.body.height, bb.max.y, 0.01);
    try std.testing.expect(bb.min.y > -0.01 and bb.min.y < 0.02);
    for (mesh.vertices.items) |v| {
        var sum: f32 = 0;
        for (v.joints, v.weights) |j, w| {
            try std.testing.expect(j < skel.count());
            sum += w;
        }
        try std.testing.expectApproxEqAbs(@as(f32, 1), sum, 1e-4);
    }
    // left/right symmetry of the generated shape
    try std.testing.expectApproxEqAbs(bb.max.x, -bb.min.x, 0.005);
}
