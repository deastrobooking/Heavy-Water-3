//! Layouts for every GUI screen, drawn into a `Canvas` from game state each frame: the title
//! and pause menus, settings, controls, the HUD, character customization, the market shop,
//! the tinker's upgrades and wardrobe, and conversations. Drawing never changes state; each
//! clickable element records a hit whose id says which control and row it is.
const std = @import("std");
const Canvas = @import("Canvas.zig");
const Menu = @import("Menu.zig");
const Sandbox = @import("../game/Sandbox.zig");
const Profile = @import("../game/Profile.zig");
const Creator = @import("../game/Creator.zig");
const Progress = @import("../game/Progress.zig");
const Dialogue = @import("../game/Dialogue.zig");
const Settings = @import("../game/Settings.zig");
const Bindings = @import("../game/Bindings.zig");
const Fabricator = @import("../game/Fabricator.zig");
const Collectibles = @import("../game/Collectibles.zig");
const QuestLog = @import("../game/QuestLog.zig");
const Market = @import("../city/Market.zig");
pub const Rect = Canvas.Rect;
const Color = Canvas.Color;

pub const ink: Color = .{ 0.86, 0.93, 0.94, 1 };
pub const dim: Color = .{ 0.52, 0.63, 0.67, 1 };
pub const accent: Color = .{ 0.24, 0.88, 0.82, 1 };
pub const gold: Color = .{ 0.98, 0.80, 0.35, 1 };
pub const bad: Color = .{ 0.95, 0.42, 0.38, 1 };
pub const good: Color = .{ 0.56, 0.92, 0.56, 1 };
const panel_fill: Color = .{ 0.025, 0.04, 0.055, 0.9 };
const shade: Color = .{ 0, 0.01, 0.02, 0.55 };
const row_height: f32 = 26;

/// What a hit is: the control kind in the high byte and its row in the low byte.
pub const Area = enum(u8) { fab_tab = 20, menu = 1, setting_left, setting_right, creator_field, creator_left, creator_right, creator_done, trade_row, trade_close, shop_row, shop_close, choice, talk_continue };
pub fn hitId(area: Area, row: usize) u16 {
    return @as(u16, @intFromEnum(area)) << 8 | @as(u16, @intCast(row));
}
pub fn hitArea(id: u16) Area {
    return @enumFromInt(id >> 8);
}
pub fn hitRow(id: u16) u8 {
    return @intCast(id & 0xff);
}

/// Per-frame values the application derives (clock, prompts, inspection text).
pub const Hud = struct {
    /// P1's view, in canvas units (split-screen shrinks it).
    view: Rect,
    clock: []const u8 = "",
    prompt: []const u8 = "",
    toast: []const u8 = "",
    inspect: []const []const u8 = &.{},
    /// Seconds since start, for blinking cursors.
    time: f32 = 0,
    seed: u64 = 0,
    /// Active guests' split views (P2–P4), each with its aimed prompt.
    guests: []const Guest = &.{},

    /// Flight marks on P1's view: the Kestrel's nose, and the missile lock (with progress).
    marks: []const Mark = &.{},
    /// P1's keys for class specials 1–3.
    special_keys: [3][]const u8 = .{ "Z", "C", "H" },

    pub const Guest = struct { index: u8, view: Rect, prompt: []const u8 = "" };
    pub const Mark = struct { x: f32, y: f32, kind: enum { nose, lock }, progress: f32 = 0 };
};

fn alpha(c: Color, a: f32) Color {
    return .{ c[0], c[1], c[2], c[3] * a };
}

/// Uppercase with underscores as spaces ("hair_style" → "HAIR STYLE").
fn pretty(buffer: []u8, name: []const u8) []const u8 {
    const n = @min(buffer.len, name.len);
    for (buffer[0..n], name[0..n]) |*o, ch| o.* = if (ch == '_') ' ' else std.ascii.toUpper(ch);
    return buffer[0..n];
}

fn panel(c: *Canvas, r: Rect, title: []const u8) void {
    c.rect(r, panel_fill);
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 2 }, accent);
    c.rect(.{ .x = r.x, .y = r.y + r.h - 1, .w = r.w, .h = 1 }, alpha(accent, 0.3));
    if (title.len > 0) c.text(r.x + 18, r.y + 16, title, 1.6, accent);
}

fn rowBack(c: *Canvas, r: Rect, selected: bool) void {
    if (!selected) return;
    c.rect(r, alpha(accent, 0.16));
    c.rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, accent);
}

fn button(c: *Canvas, r: Rect, label: []const u8, id: u16, hot: bool) void {
    c.rect(r, if (hot) alpha(accent, 0.3) else alpha(accent, 0.1));
    c.frame(r, 1, alpha(accent, 0.7));
    c.centered(r.x + r.w / 2, r.y + (r.h - Canvas.line_height) / 2, label, 1, ink);
    c.hit(r, id);
}

fn bar(c: *Canvas, r: Rect, fraction: f32, color: Color) void {
    c.rect(r, .{ 0, 0, 0, 0.5 });
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w * std.math.clamp(fraction, 0, 1), .h = r.h }, color);
}

/// Everything for this frame, in draw order: HUD, then panels, then menus on top.
pub fn draw(c: *Canvas, menu: *const Menu, sb: *const Sandbox, hud: Hud) void {
    if (menu.screen == .title or (menu.base == .title and menu.screen != .none)) return drawTitle(c, menu, hud);
    for (hud.guests) |g| drawGuest(c, sb, g);
    for (hud.marks) |mark| switch (mark.kind) {
        .nose => {
            c.frame(.{ .x = mark.x - 7, .y = mark.y - 7, .w = 14, .h = 14 }, 2, alpha(accent, 0.9));
            c.rect(.{ .x = mark.x - 1, .y = mark.y - 1, .w = 2, .h = 2 }, accent);
        },
        .lock => {
            const locked = mark.progress >= 1;
            const size: f32 = 34 - 14 * mark.progress;
            const color: Color = if (locked) bad else gold;
            c.frame(.{ .x = mark.x - size / 2, .y = mark.y - size / 2, .w = size, .h = size }, if (locked) 3 else 2, color);
            if (locked) c.centered(mark.x, mark.y + size / 2 + 6, "LOCK", 1, bad);
        },
    };
    const panels = sb.creator.open or sb.talk != null or sb.shop != null or sb.trading != null or menu.screen != .none;
    if (!sb.creator.open) drawHud(c, sb, hud, panels);
    if (sb.creator.open) drawCreator(c, sb, hud.view) else if (sb.talk) |session| drawTalk(c, sb, session, hud) else if (sb.shop) |shop| switch (shop.kind) {
        .upgrades => drawUpgrades(c, sb, shop.row, hud.view),
        .wardrobe => drawWardrobe(c, sb, shop.row, hud.view),
        .fabricate => drawFabricator(c, sb, shop, hud.view),
    } else if (sb.trading) |stall| drawShop(c, sb, stall, hud.view) else if (hud.inspect.len > 0) drawInspect(c, hud);
    switch (menu.screen) {
        .none, .title => {},
        else => {
            c.rect(.{ .x = 0, .y = 0, .w = c.width, .h = c.height }, shade);
            drawMenu(c, menu, sb);
        },
    }
}

// ---------------------------------------------------------------- title and menus

fn drawTitle(c: *Canvas, menu: *const Menu, hud: Hud) void {
    const w = @min(c.width * 0.46, 560);
    c.rect(.{ .x = 0, .y = 0, .w = w, .h = c.height }, .{ 0.01, 0.025, 0.035, 0.78 });
    c.rect(.{ .x = w, .y = 0, .w = 2, .h = c.height }, alpha(accent, 0.6));
    const x: f32 = 56;
    var y = c.height * 0.16;
    c.text(x, y, "HEAVY WATER", 5, ink);
    y += 62;
    c.text(x + 2, y, "THE CANOPY FRONTIER", 2, accent);
    y += 34;
    c.text(x + 2, y, "Explore the Rootdeep. Engineer the city. Grow the Arbors.", 1, dim);
    y = c.height * 0.44;
    if (menu.screen == .title) {
        for (Menu.title_items, 0..) |item, i| {
            const r: Rect = .{ .x = x - 14, .y = y, .w = w - x - 30, .h = 34 };
            const on = menu.enabled(i);
            rowBack(c, r, menu.row == i);
            c.text(r.x + 18, r.y + 10, item.label, 1.5, if (!on) alpha(dim, 0.5) else if (menu.row == i) accent else ink);
            if (on) c.hit(r, hitId(.menu, i));
            y += 40;
        }
    } else drawMenu(c, menu, null);
    // Load failures and other notices still need to reach the player here.
    if (hud.toast.len > 0) c.text(x, c.height - 70, hud.toast, 1.1, bad);
    c.text(x, c.height - 44, "ARROWS OR MOUSE  ENTER SELECT  ESC BACK", 1, dim);
    c.print(x, c.height - 26, 1, alpha(dim, 0.7), "SEED {d}  NATIVE ZIG  MACH", .{hud.seed});
}

fn menuRect(c: *const Canvas, width: f32, height: f32) Rect {
    return .{ .x = (c.width - width) / 2, .y = (c.height - height) / 2, .w = width, .h = height };
}

fn drawMenu(c: *Canvas, menu: *const Menu, sb: ?*const Sandbox) void {
    switch (menu.screen) {
        .pause, .confirm_quit => {
            const list = menu.items();
            const r = menuRect(c, 400, 92 + @as(f32, @floatFromInt(list.len)) * 36 + (if (sb != null) @as(f32, 34) else 0));
            panel(c, r, if (menu.screen == .pause) "PAUSED" else "QUIT HEAVY WATER?");
            var y = r.y + 54;
            for (list, 0..) |item, i| {
                const row: Rect = .{ .x = r.x + 12, .y = y, .w = r.w - 24, .h = 30 };
                const on = menu.enabled(i);
                rowBack(c, row, menu.row == i);
                c.text(row.x + 16, row.y + 9, item.label, 1.25, if (!on) alpha(dim, 0.5) else if (menu.row == i) accent else ink);
                if (on) c.hit(row, hitId(.menu, i));
                y += 36;
            }
            if (sb) |s| if (menu.screen == .pause) {
                c.print(r.x + 18, r.y + r.h - 28, 1, dim, "DAY {d}   SCRAP {d}   PARTS {d}   UNSAVED PROGRESS IS LOST ON QUIT", .{ s.market.day, s.wallet.scrap, s.wallet.parts });
            };
        },
        .settings => drawSettings(c, menu),
        .controls => drawControls(c, menu),
        .quest_log => if (sb) |s| drawQuestLog(c, menu, s),
        else => {},
    }
}

fn drawQuestLog(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const r = menuRect(c, 620, 370);
    panel(c, r, "THE HIVE CAMPAIGN");
    const objective = QuestLog.current(&sb.progress, &sb.enemies, &sb.skies);
    c.text(r.x + 24, r.y + 54, "NEXT OBJECTIVE", 1, dim);
    c.text(r.x + 24, r.y + 76, objective.title, 1.65, gold);
    var wrapped: [4][]const u8 = undefined;
    const lines = Canvas.wrap(objective.detail, 69, &wrapped);
    for (wrapped[0..lines], 0..) |line, i| c.text(r.x + 24, r.y + 106 + @as(f32, @floatFromInt(i)) * 17, line, 1, ink);

    const story = [_]struct { label: []const u8, flag: []const u8 }{
        .{ .label = "TAVI'S SCOUTING MARK", .flag = "tavi_scouted" },
        .{ .label = "INES'S SAP WARNING", .flag = "ines_sap_warned" },
        .{ .label = "BROOD CARRIER SIGHTED", .flag = "carrier_seen" },
        .{ .label = "MARO'S KESTREL BLUEPRINT", .flag = "kestrel_blueprint" },
    };
    var y = r.y + 188;
    for (story) |beat| {
        const complete = sb.progress.hasFlag(beat.flag);
        c.text(r.x + 24, y, if (complete) "[x]" else "[ ]", 1, if (complete) good else dim);
        c.text(r.x + 58, y, beat.label, 1, if (complete) dim else ink);
        y += 21;
    }
    c.print(r.x + 24, y + 3, 1, dim, "NESTS {d}   CARRIERS {d}", .{ objective.nests_left, objective.carriers_left });
    const back: Rect = .{ .x = r.x + r.w - 136, .y = r.y + r.h - 48, .w = 112, .h = 30 };
    button(c, back, "BACK", hitId(.menu, 0), menu.row == 0);
}

fn drawSettings(c: *Canvas, menu: *const Menu) void {
    const r = menuRect(c, 600, 100 + @as(f32, @floatFromInt(Menu.settings_rows)) * 34);
    panel(c, r, "SETTINGS");
    var y = r.y + 54;
    for (0..Settings.field_count) |i| {
        const field: Settings.Field = @enumFromInt(i);
        const row: Rect = .{ .x = r.x + 12, .y = y, .w = r.w - 24, .h = 28 };
        rowBack(c, row, menu.row == i);
        c.hit(row, hitId(.menu, i));
        c.text(row.x + 16, row.y + 9, Settings.label(field), 1.1, if (menu.row == i) accent else ink);
        var buffer: [24]u8 = undefined;
        const value = menu.settings.value(field, &buffer);
        const right = row.x + row.w - 16;
        const left_button: Rect = .{ .x = right - 190, .y = row.y + 3, .w = 22, .h = 22 };
        const right_button: Rect = .{ .x = right - 22, .y = row.y + 3, .w = 22, .h = 22 };
        button(c, left_button, "<", hitId(.setting_left, i), false);
        button(c, right_button, ">", hitId(.setting_right, i), false);
        c.centered(right - 95, row.y + 9, value, 1.1, ink);
        y += 34;
    }
    const back: Rect = .{ .x = r.x + 12, .y = y + 6, .w = r.w - 24, .h = 28 };
    rowBack(c, back, menu.row == Settings.field_count);
    c.text(back.x + 16, back.y + 9, "BACK", 1.1, if (menu.row == Settings.field_count) accent else ink);
    c.hit(back, hitId(.menu, Settings.field_count));
    c.text(r.x + 18, r.y + r.h - 22, "LEFT RIGHT CHANGE  SAVED AUTOMATICALLY", 1, dim);
}

fn drawControls(c: *Canvas, menu: *const Menu) void {
    const rows: f32 = @floatFromInt(Menu.controls_column);
    const r = menuRect(c, 780, 170 + rows * 21);
    panel(c, r, "CONTROLS");
    const b = menu.settings.bindings;
    for (0..Bindings.count) |i| {
        const column: f32 = @floatFromInt(i / Menu.controls_column);
        const x = r.x + 12 + column * 380;
        const y = r.y + 50 + @as(f32, @floatFromInt(i % Menu.controls_column)) * 21;
        const row: Rect = .{ .x = x, .y = y, .w = 368, .h = 19 };
        const selected = menu.row == i;
        rowBack(c, row, selected);
        c.hit(row, hitId(.menu, i));
        c.text(row.x + 12, row.y + 5, Bindings.label(@enumFromInt(i)), 0.9, if (selected) accent else ink);
        var buffer: [24]u8 = undefined;
        const name = if (selected and menu.capturing) (if (@mod(menu.seconds, 1.0) < 0.6) "PRESS A KEY" else "") else Bindings.keyName(b.keys[i], &buffer);
        c.text(row.x + row.w - 12 - Canvas.textWidth(name, 0.9), row.y + 5, name, 0.9, gold);
    }
    var note: [96]u8 = undefined;
    const message = if (menu.capturing)
        "PRESS THE NEW KEY  ESC CANCELS  ENTER IS RESERVED FOR MENUS"
    else if (menu.swapped) |a|
        std.fmt.bufPrint(&note, "{s} TOOK THE OLD KEY", .{Bindings.label(a)}) catch ""
    else
        "ENTER REBIND  LEFT RIGHT COLUMN  SAVED WHEN YOU LEAVE";
    c.text(r.x + 24, r.y + r.h - 90, message, 1, if (menu.swapped != null and !menu.capturing) gold else dim);
    c.text(r.x + 24, r.y + r.h - 68, "PAD: STICKS MOVE/LOOK  A JUMP  X USE  B ROLL/BACK  MENU PAUSES (P1) OR JOINS", 0.9, dim);
    const reset: Rect = .{ .x = r.x + r.w - 290, .y = r.y + r.h - 40, .w = 150, .h = 26 };
    const back: Rect = .{ .x = r.x + r.w - 130, .y = r.y + r.h - 40, .w = 110, .h = 26 };
    button(c, reset, "RESET KEYS", hitId(.menu, Menu.controls_reset), menu.row == Menu.controls_reset);
    button(c, back, "BACK", hitId(.menu, Menu.controls_back), menu.row == Menu.controls_back);
}

// ---------------------------------------------------------------- HUD

fn drawHud(c: *Canvas, sb: *const Sandbox, hud: Hud, panels: bool) void {
    const v = hud.view;
    // Vitals, bottom left (hidden under conversation and shop panels).
    if (sb.seated == null and !panels) {
        vitals(c, v, sb.player, sb.profile, sb.combat.vitals[0]);
        specials(c, v, sb, 0, sb.profile, hud.special_keys);
        if (sb.tools.tool == .weapon) weaponLine(c, v, sb, 0);
    }
    // Wallet and clock, top right.
    {
        var buffer: [48]u8 = undefined;
        const scrap = std.fmt.bufPrint(&buffer, "{d} SCRAP", .{sb.wallet.scrap}) catch "";
        const w: f32 = 290;
        const r: Rect = .{ .x = v.x + v.w - w - 20, .y = v.y + 20, .w = w, .h = 72 };
        c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
        c.text(r.x + 14, r.y + 10, scrap, 1.3, gold);
        c.print(r.x + 14, r.y + 32, 1, ink, "{d} PARTS   {d} KITS", .{ sb.wallet.parts, kits(sb.wallet) });
        inventoryLine(c, sb, r.x + 14, r.y + 50, 1);
        c.text(r.x + w - 14 - Canvas.textWidth(hud.clock, 1), r.y + 12, hud.clock, 1, dim);
    }
    if (panels) return;
    // Interaction prompt and toast, bottom centre.
    prompt(c, v, hud.prompt, accent);
    if (hud.toast.len > 0) c.centered(v.x + v.w / 2, v.y + v.h - 150, hud.toast, 1.2, accent);
}

/// Name, motion, fuel and stamina in the bottom-left corner of a view.
fn vitals(c: *Canvas, v: Rect, p: @import("../game/Player.zig"), profile: Profile, health: @import("../game/Combat.zig").Vitals) void {
    const r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 110, .w = 250, .h = 90 };
    // Hurt: the view's edges flush red.
    if (health.hurt > 0) {
        const a = health.hurt * 0.9;
        c.rect(.{ .x = v.x, .y = v.y, .w = v.w, .h = 10 }, .{ 0.9, 0.05, 0.05, a });
        c.rect(.{ .x = v.x, .y = v.y + v.h - 10, .w = v.w, .h = 10 }, .{ 0.9, 0.05, 0.05, a });
        c.rect(.{ .x = v.x, .y = v.y, .w = 10, .h = v.h }, .{ 0.9, 0.05, 0.05, a });
        c.rect(.{ .x = v.x + v.w - 10, .y = v.y, .w = 10, .h = v.h }, .{ 0.9, 0.05, 0.05, a });
    }
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    c.rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, Profile.accent_colors[profile.accent]);
    var name_buffer: [32]u8 = undefined;
    c.text(r.x + 14, r.y + 10, profile.name(), 1.2, ink);
    const motion = if (p.mode == .fly) "FLY" else @tagName(p.motion);
    c.text(r.x + 14 + Canvas.textWidth(profile.name(), 1.2) + 12, r.y + 12, pretty(&name_buffer, motion), 1, dim);
    c.text(r.x + 14, r.y + 32, "HEALTH", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 32, .w = 166, .h = 8 }, health.health / health.max, .{ 0.95, 0.32, 0.32, 1 });
    // An overshield shows as a bright band over the health bar.
    if (health.shield > 0) c.rect(.{ .x = r.x + 66, .y = r.y + 29, .w = 166 * @min(1, health.shield / 80), .h = 3 }, .{ 0.45, 0.9, 1, 1 });
    c.text(r.x + 14, r.y + 50, "FUEL", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 50, .w = 166, .h = 8 }, p.fuel / p.suit.fuel_max, accent);
    c.text(r.x + 14, r.y + 68, "STAMINA", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 68, .w = 166, .h = 8 }, p.stamina / 100, good);
}

/// Energy and the class's three specials (key, name, cooldown), beside the vitals.
fn specials(c: *Canvas, v: Rect, sb: *const Sandbox, player: u8, profile: Profile, keys: [3][]const u8) void {
    const Specials = @import("../game/Specials.zig");
    const s = sb.specials.players[player];
    const w: f32 = @min(230, v.w - 290);
    if (w < 150) return;
    const r: Rect = .{ .x = v.x + 280, .y = v.y + v.h - 110, .w = w, .h = 90 };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    const lumen = Profile.accent_colors[profile.accent];
    c.text(r.x + 12, r.y + 10, if (profile.class == .synthetic) "POWERS" else "TECH", 0.9, lumen);
    bar(c, .{ .x = r.x + 70, .y = r.y + 11, .w = r.w - 82, .h = 7 }, s.energy / Specials.max_energy, lumen);
    for (Specials.kit(profile.class), 0..) |kind, i| {
        const about = Specials.info(kind);
        const y = r.y + 30 + @as(f32, @floatFromInt(i)) * 19;
        const ready = s.cooldowns[i] == 0 and s.energy >= about.cost;
        c.rect(.{ .x = r.x + 10, .y = y - 2, .w = 20, .h = 15 }, if (ready) alpha(lumen, 0.35) else .{ 1, 1, 1, 0.08 });
        c.centered(r.x + 20, y + 2, keys[i], 0.8, ink);
        c.text(r.x + 38, y + 2, about.label, 0.85, if (ready) ink else dim);
        // The cooldown drains away to the right.
        if (s.cooldowns[i] > 0) c.rect(.{ .x = r.x + 38, .y = y + 12, .w = (r.w - 50) * s.cooldowns[i] / about.cooldown, .h = 2 }, alpha(lumen, 0.7));
    }
}

/// The selected weapon and its charge, above the vitals (weapon tool only).
fn weaponLine(c: *Canvas, v: Rect, sb: *const Sandbox, player: u8) void {
    const r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 142, .w = 250, .h = 26 };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    var buffer: [24]u8 = undefined;
    const arsenal = &sb.combat.arsenals[player];
    const name = if (arsenal.active) |w| pretty(&buffer, @tagName(w)) else "NO WEAPON";
    c.text(r.x + 14, r.y + 9, name, 1, gold);
    bar(c, .{ .x = r.x + 160, .y = r.y + 10, .w = 76, .h = 6 }, arsenal.charge(), gold);
}

fn prompt(c: *Canvas, v: Rect, text: []const u8, tint: Color) void {
    if (text.len == 0) return;
    const cx = v.x + v.w / 2;
    const w = Canvas.textWidth(text, 1.1) + 36;
    const r: Rect = .{ .x = cx - w / 2, .y = v.y + v.h - 120, .w = w, .h = 28 };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.72 });
    c.frame(r, 1, alpha(tint, 0.5));
    c.centered(cx, r.y + 9, text, 1.1, ink);
}

/// A guest's split view: vitals, the aimed prompt, and a compact stall panel while trading
/// (the party shares P1's wallet, shown in P1's view).
fn drawGuest(c: *Canvas, sb: *const Sandbox, guest: Hud.Guest) void {
    const g = &sb.guests[guest.index];
    const v = guest.view;
    const tint = Profile.accent_colors[g.profile.accent];
    vitals(c, v, g.player, g.profile, sb.combat.vitals[guest.index + 1]);
    specials(c, v, sb, guest.index + 1, g.profile, .{ "UP", "DN", "R3+UP" });
    if (sb.progress.weapons != 0) weaponLine(c, v, sb, guest.index + 1);
    const stall = g.trading orelse return prompt(c, v, guest.prompt, tint);
    const w = @min(v.w - 40, 460);
    const h = 84 + @as(f32, Sandbox.trade_rows) * 26;
    const r: Rect = .{ .x = v.x + v.w - w - 20, .y = v.y + 20, .w = w, .h = h };
    c.rect(r, panel_fill);
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 2 }, tint);
    var title: [48]u8 = undefined;
    var upper: [48]u8 = undefined;
    c.text(r.x + 14, r.y + 12, pretty(&upper, std.fmt.bufPrint(&title, "{s}'S STALL", .{keeperName(sb, stall)}) catch ""), 1.2, tint);
    c.print(r.x + w - 200, r.y + 14, 1, gold, "{d} SCRAP  {d} PARTS", .{ sb.wallet.scrap, sb.wallet.parts });
    var y = r.y + 38;
    for (0..Sandbox.trade_rows) |i| {
        const row: Rect = .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = 22 };
        rowBack(c, row, g.trade_row == i);
        var line: Sandbox.TradeLine = .{};
        sb.tradeRow(stall, @intCast(i), false, &line);
        var shown: [96]u8 = undefined;
        c.text(row.x + 8, row.y + 7, pretty(&shown, std.mem.trimStart(u8, line.slice(), " ")), 0.9, if (g.trade_row == i) tint else ink);
        y += 26;
    }
    c.text(r.x + 14, r.y + r.h - 22, "D-PAD CHOOSE  X TRADE  B CLOSE", 0.9, dim);
}

fn kits(w: Market.Wallet) u32 {
    var n: u32 = 0;
    for (w.kits) |k| n += k;
    return n;
}

fn drawInspect(c: *Canvas, hud: Hud) void {
    const v = hud.view;
    const h = 40 + @as(f32, @floatFromInt(hud.inspect.len)) * 16;
    const r: Rect = .{ .x = v.x + v.w - 540, .y = v.y + 96, .w = 520, .h = h };
    panel(c, r, "");
    for (hud.inspect, 0..) |line, i| c.text(r.x + 16, r.y + 16 + @as(f32, @floatFromInt(i)) * 16, line, 1, if (i == 0) accent else ink);
}

// ---------------------------------------------------------------- customization

const sections = [_]struct { title: []const u8, first: Profile.Field }{
    .{ .title = "IDENTITY", .first = .name },
    .{ .title = "BODY", .first = .height },
    .{ .title = "HAIR", .first = .hair_style },
    .{ .title = "GEAR", .first = .outfit },
};

fn swatch(field: Profile.Field, p: Profile) ?Color {
    return switch (field) {
        .skin => Profile.skin_tones[p.skin],
        .hair_color => Profile.hair_colors[p.hair_color],
        .outfit => Profile.outfit_colors[p.outfit],
        .accent => Profile.accent_colors[p.accent],
        else => null,
    };
}

fn drawCreator(c: *Canvas, sb: *const Sandbox, v: Rect) void {
    const cr = &sb.creator;
    const fields = @typeInfo(Profile.Field).@"enum".fields;
    const h = 120 + @as(f32, @floatFromInt(fields.len)) * row_height + sections.len * 22;
    const r: Rect = .{ .x = v.x + 24, .y = v.y + @max(20, (v.h - h) / 2), .w = 460, .h = h };
    panel(c, r, if (cr.confirmed) "CUSTOMIZE RANGER" else "CREATE YOUR RANGER");
    var y = r.y + 46;
    inline for (fields, 0..) |f, i| {
        const field: Profile.Field = @enumFromInt(f.value);
        for (sections) |s| if (s.first == field) {
            c.text(r.x + 18, y + 8, s.title, 0.9, alpha(accent, 0.8));
            c.rect(.{ .x = r.x + 18 + Canvas.textWidth(s.title, 0.9) + 8, .y = y + 12, .w = r.w - 60 - Canvas.textWidth(s.title, 0.9), .h = 1 }, alpha(accent, 0.25));
            y += 22;
        };
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = row_height - 2 };
        const selected = cr.field == field;
        rowBack(c, row, selected);
        c.hit(row, hitId(.creator_field, i));
        var label_buffer: [24]u8 = undefined;
        c.text(row.x + 14, row.y + 8, pretty(&label_buffer, f.name), 1, if (selected) accent else dim);
        var buffer: [40]u8 = undefined;
        var value = cr.value(field, &buffer);
        var pretty_buffer: [40]u8 = undefined;
        if (field != .name) value = pretty(&pretty_buffer, value);
        const vx = row.x + 196;
        if (field != .name) {
            button(c, .{ .x = vx, .y = row.y + 2, .w = 20, .h = 20 }, "<", hitId(.creator_left, i), false);
            button(c, .{ .x = row.x + row.w - 28, .y = row.y + 2, .w = 20, .h = 20 }, ">", hitId(.creator_right, i), false);
        }
        var tx = vx + 30;
        if (swatch(field, cr.draft)) |color| {
            c.rect(.{ .x = tx, .y = row.y + 5, .w = 26, .h = 14 }, color);
            c.frame(.{ .x = tx, .y = row.y + 5, .w = 26, .h = 14 }, 1, .{ 1, 1, 1, 0.4 });
            tx += 34;
        }
        c.text(tx, row.y + 8, value, 1, ink);
        y += row_height;
    }
    const clothing_count = @typeInfo(Profile.Clothing).@"enum".fields.len;
    const all: u8 = @intCast((@as(u16, 1) << clothing_count) - 1);
    const locked = clothing_count - @popCount(cr.owned & all);
    if (locked > 0) c.print(r.x + 18, y + 8, 0.9, gold, "{d} ARMOR SUITS LOCKED: BUY THEM FROM MARO, SOUTH MARKET", .{locked});
    const done: Rect = .{ .x = r.x + r.w - 140, .y = r.y + r.h - 40, .w = 120, .h = 28 };
    button(c, done, "DONE", hitId(.creator_done, 0), false);
    c.text(r.x + 18, r.y + r.h - 30, if (cr.confirmed) "TYPE NAME  ENTER DONE  ESC CANCEL" else "TYPE A NAME, THEN ENTER", 0.9, dim);
}

// ---------------------------------------------------------------- shop, upgrades, wardrobe

pub fn keeperName(sb: *const Sandbox, stall: usize) []const u8 {
    var buffer: [16]u8 = undefined;
    const id = std.fmt.bufPrint(&buffer, "keeper_{d}", .{stall}) catch return "";
    const index = sb.dialogue.find(id) orelse return "";
    const conv = sb.dialogue.parsed.value.conversations[index];
    const s = sb.dialogue.speakerIndex(conv.speaker) orelse return "";
    return sb.dialogue.parsed.value.speakers[s].name;
}

fn walletLine(c: *Canvas, sb: *const Sandbox, x: f32, y: f32) void {
    c.print(x, y, 1.1, gold, "{d} SCRAP", .{sb.wallet.scrap});
    c.print(x + 140, y, 1.1, ink, "{d} PARTS", .{sb.wallet.parts});
}

/// A shop panel on the right of the view, or on the left when the character is on show.
fn shopFrame(c: *Canvas, v: Rect, rows: usize, title: []const u8, close_id: u16, left: bool) Rect {
    const h = 150 + @as(f32, @floatFromInt(rows)) * 34 + (if (left) @as(f32, 18) else 0);
    const w = @min(@as(f32, if (left) 470 else 640), v.w - 40);
    const r: Rect = .{ .x = if (left) v.x + 24 else v.x + v.w - w - 24, .y = v.y + @max(20, (v.h - h) / 2), .w = w, .h = h };
    panel(c, r, title);
    button(c, .{ .x = r.x + r.w - 40, .y = r.y + 12, .w = 26, .h = 24 }, "X", close_id, false);
    return r;
}

fn drawShop(c: *Canvas, sb: *const Sandbox, stall: u8, v: Rect) void {
    var title_buffer: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buffer, "{s}'S STALL  MARKET {d}", .{ keeperName(sb, stall), Market.stall_plazas[stall] }) catch "MARKET";
    var upper: [48]u8 = undefined;
    const r = shopFrame(c, v, Sandbox.trade_rows, pretty(&upper, title), hitId(.trade_close, 0), false);
    walletLine(c, sb, r.x + 18, r.y + 46);
    c.print(r.x + r.w - 220, r.y + 46, 1, dim, "DAY {d}  RESTOCKS AT DAWN", .{sb.market.day});
    var y = r.y + 76;
    for (0..Sandbox.trade_rows) |i| {
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        const selected = sb.trade_row == i;
        rowBack(c, row, selected);
        c.hit(row, hitId(.trade_row, i));
        if (i == 0) {
            const price = sb.market.partPrice(stall);
            c.text(row.x + 14, row.y + 10, "SELL SALVAGED PARTS", 1.1, if (sb.wallet.parts == 0) dim else ink);
            c.print(row.x + row.w - 260, row.y + 10, 1, if (sb.wallet.parts == 0) dim else gold, "{d} X {d} = +{d} SCRAP", .{ sb.wallet.parts, price, sb.wallet.parts * price });
        } else {
            const ware: Market.Ware = @enumFromInt(i - 1);
            const stock = sb.market.stalls[stall].stock[i - 1];
            const price = sb.market.price(stall, ware);
            var name_buffer: [32]u8 = undefined;
            var buffer: [40]u8 = undefined;
            const name = std.fmt.bufPrint(&buffer, "{s} KIT", .{ware_names[i - 1]}) catch "";
            c.text(row.x + 14, row.y + 10, pretty(&name_buffer, name), 1.1, if (stock == 0) dim else ink);
            c.print(row.x + row.w - 260, row.y + 10, 1, if (stock == 0) dim else if (price > sb.wallet.scrap) bad else gold, "{d} SCRAP", .{price});
            if (stock == 0) c.text(row.x + row.w - 150, row.y + 10, "SOLD OUT", 1, bad) else c.print(row.x + row.w - 150, row.y + 10, 1, dim, "STOCK {d}", .{stock});
            c.print(row.x + row.w - 64, row.y + 10, 1, dim, "HAVE {d}", .{sb.wallet.kits[i - 1]});
        }
        y += 34;
    }
    const about = if (sb.trade_row == 0) "Salvage glowing relics with right click; every stall buys parts." else ware_about[sb.trade_row - 1];
    c.text(r.x + 18, r.y + r.h - 50, about, 1, dim);
    c.text(r.x + 18, r.y + r.h - 28, "ENTER BUY / SELL  ESC CLOSE  KITS PLACE WITH THE BUILD TOOL (2)", 0.9, alpha(dim, 0.8));
}

const ware_names = [Market.ware_count][]const u8{ "proximity gate", "street lamp", "signal relay" };
const ware_about = [Market.ware_count][]const u8{
    "A gate that opens for anyone standing near either side.",
    "A lamp that lights when someone walks near it.",
    "Repeats bus channel 1 onto channel 2, with an indicator.",
};

fn pips(c: *Canvas, x: f32, y: f32, level: u8) void {
    for (0..Progress.max_level) |i| {
        const r: Rect = .{ .x = x + @as(f32, @floatFromInt(i)) * 16, .y = y, .w = 12, .h = 12 };
        if (i < level) c.rect(r, accent) else c.frame(r, 1, alpha(accent, 0.6));
    }
}

fn costText(buffer: []u8, cost: Progress.Cost) []const u8 {
    if (cost.parts == 0) return std.fmt.bufPrint(buffer, "{d} SCRAP", .{cost.scrap}) catch "";
    return std.fmt.bufPrint(buffer, "{d} SCRAP + {d} PARTS", .{ cost.scrap, cost.parts }) catch "";
}

fn affordable(w: Market.Wallet, cost: Progress.Cost) bool {
    return w.scrap >= cost.scrap and w.parts >= cost.parts;
}

fn drawUpgrades(c: *Canvas, sb: *const Sandbox, selected: u8, v: Rect) void {
    const r = shopFrame(c, v, Progress.upgrade_count + 1, "SUIT UPGRADES  MARO, TINKER", hitId(.shop_close, 0), false);
    walletLine(c, sb, r.x + 18, r.y + 46);
    var y = r.y + 76;
    for (0..Progress.upgrade_count) |i| {
        const u: Progress.Upgrade = @enumFromInt(i);
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        rowBack(c, row, selected == i);
        c.hit(row, hitId(.shop_row, i));
        c.text(row.x + 14, row.y + 10, Progress.info[i].name, 1.1, if (selected == i) accent else ink);
        pips(c, row.x + 230, row.y + 9, sb.progress.level(u));
        var buffer: [40]u8 = undefined;
        if (sb.progress.level(u) >= Progress.max_level) {
            c.text(row.x + row.w - 200, row.y + 10, "FULLY TUNED", 1, good);
        } else {
            const cost = sb.progress.cost(u);
            c.text(row.x + row.w - 200, row.y + 10, costText(&buffer, cost), 1, if (affordable(sb.wallet, cost)) gold else bad);
        }
        y += 34;
    }
    const s = sb.progress.suit();
    c.print(r.x + 18, y + 10, 1, dim, "FUEL {d:.0}  BURN {d:.0}%  SPRINT {d:.1} M/S  GRAPPLE {d:.0} M  PARTS/RELIC {d}", .{ s.fuel_max, s.burn * 100, s.sprint, s.grapple_range, sb.progress.partsPerSalvage() });
    c.text(r.x + 18, r.y + r.h - 50, Progress.info[@min(selected, Progress.upgrade_count - 1)].summary, 1, ink);
    c.text(r.x + 18, r.y + r.h - 28, "ENTER INSTALL NEXT LEVEL  ESC CLOSE  UPGRADES APPLY TO THE WHOLE PARTY", 0.9, alpha(dim, 0.8));
}

const suit_about = [_][]const u8{
    "A sealed base layer: light, quiet, nothing to snag on a branch.",
    "An open field jacket over the undersuit. A ranger classic.",
    "Exo rig: segmented limb plates for climbers who like their elbows.",
    "Hardsuit: white shrine-foundry plate, cuirass to greaves.",
    "Vanguard: the heavy dark set. Maro does not sell it to just anyone.",
};

fn drawWardrobe(c: *Canvas, sb: *const Sandbox, selected: u8, v: Rect) void {
    // On the left: the wardrobe camera faces the character, centre-right.
    const r = shopFrame(c, v, Sandbox.wardrobe_rows, "SUIT WARDROBE  MARO, TINKER", hitId(.shop_close, 0), true);
    walletLine(c, sb, r.x + 18, r.y + 46);
    var y = r.y + 76;
    inline for (@typeInfo(Profile.Clothing).@"enum".fields, 0..) |f, i| {
        const clothing: Profile.Clothing = @enumFromInt(f.value);
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        rowBack(c, row, selected == i);
        c.hit(row, hitId(.shop_row, i));
        var name_buffer: [24]u8 = undefined;
        c.text(row.x + 14, row.y + 10, pretty(&name_buffer, f.name), 1.1, if (selected == i) accent else ink);
        var buffer: [40]u8 = undefined;
        if (sb.profile.clothing == clothing) {
            c.text(row.x + row.w - 200, row.y + 10, "WEARING", 1, good);
        } else if (sb.progress.owns(clothing)) {
            c.text(row.x + row.w - 200, row.y + 10, "OWNED", 1, ink);
        } else {
            const cost = Progress.suitPrice(clothing);
            c.text(row.x + row.w - 200, row.y + 10, costText(&buffer, cost), 1, if (affordable(sb.wallet, cost)) gold else bad);
        }
        y += 34;
    }
    var lines: [3][]const u8 = undefined;
    const columns: usize = @intFromFloat((r.w - 36) / Canvas.char_width);
    const count = Canvas.wrap(suit_about[@min(selected, suit_about.len - 1)], columns, &lines);
    for (lines[0..count], 0..) |line, i| c.text(r.x + 18, r.y + r.h - 68 + @as(f32, @floatFromInt(i)) * 16, line, 1, ink);
    c.text(r.x + 18, r.y + r.h - 28, "ENTER BUY / WEAR  ESC CLOSE  F4 COLORS", 0.9, alpha(dim, 0.8));
}

fn inventoryLine(c: *Canvas, sb: *const Sandbox, x: f32, y: f32, scale: f32) void {
    var cx = x;
    for (0..Collectibles.kind_count) |k| {
        const kind: Collectibles.Kind = @enumFromInt(k);
        const t = Collectibles.tint(kind);
        c.rect(.{ .x = cx, .y = y + 1, .w = 8 * scale, .h = 8 * scale }, .{ t[0], t[1], t[2], 1 });
        var buffer: [24]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{sb.progress.count(kind)}) catch "";
        c.text(cx + 12 * scale, y + 1, text, scale, ink);
        cx += 12 * scale + Canvas.textWidth(text, scale) + 16;
    }
}

fn drawFabricator(c: *Canvas, sb: *const Sandbox, shop: Sandbox.Shop, v: Rect) void {
    var list: [Fabricator.recipes.len]u8 = undefined;
    const rows = Fabricator.onTab(@enumFromInt(shop.tab), &list);
    const r = shopFrame(c, v, rows.len + 1, "FABRICATOR", hitId(.shop_close, 0), false);
    // Tabs.
    var tx = r.x + 18;
    for (0..Fabricator.tab_count) |t| {
        var buffer: [16]u8 = undefined;
        const label = pretty(&buffer, @tagName(@as(Fabricator.Tab, @enumFromInt(t))));
        const w = Canvas.textWidth(label, 1) + 24;
        const tab: Rect = .{ .x = tx, .y = r.y + 44, .w = w, .h = 22 };
        c.rect(tab, if (shop.tab == t) alpha(accent, 0.3) else alpha(accent, 0.08));
        c.text(tab.x + 12, tab.y + 6, label, 1, if (shop.tab == t) accent else dim);
        c.hit(tab, hitId(.fab_tab, t));
        tx += w + 8;
    }
    inventoryLine(c, sb, r.x + r.w - 300, r.y + 50, 1);
    var y = r.y + 76;
    for (rows, 0..) |index, i| {
        const recipe = Fabricator.recipes[index];
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        rowBack(c, row, shop.row == i);
        c.hit(row, hitId(.shop_row, i));
        var buffer: [24]u8 = undefined;
        c.text(row.x + 14, row.y + 10, Fabricator.name(recipe.output, &buffer), 1.1, if (shop.row == i) accent else ink);
        if (Fabricator.status(&sb.progress, recipe.output)) |status| {
            const state_color = if (std.mem.eql(u8, status, "FABRICATE KESTREL FIRST")) bad else good;
            c.text(row.x + row.w - 250, row.y + 10, status, 1, state_color);
        } else if (Fabricator.progressCost(&sb.progress, recipe.output)) |cost| {
            var text_buffer: [40]u8 = undefined;
            c.text(row.x + row.w - 250, row.y + 10, costText(&text_buffer, cost), 1, if (affordable(sb.wallet, cost)) gold else bad);
        } else {
            // Cost chips, red where short.
            var cx = row.x + row.w - 250;
            const parts = [_]struct { kind: ?Collectibles.Kind, amount: u32 }{
                .{ .kind = .lumen_shard, .amount = recipe.cost.lumen },
                .{ .kind = .rotor_core, .amount = recipe.cost.rotor },
                .{ .kind = .hive_alloy, .amount = recipe.cost.alloy },
                .{ .kind = null, .amount = recipe.cost.scrap },
            };
            for (parts) |p| if (p.amount > 0) {
                const have = if (p.kind) |k| sb.progress.count(k) else sb.wallet.scrap;
                var text: [16]u8 = undefined;
                const label = if (p.kind == null) std.fmt.bufPrint(&text, "{d} SCRAP", .{p.amount}) catch "" else std.fmt.bufPrint(&text, "{d}", .{p.amount}) catch "";
                if (p.kind) |k| {
                    const t = Collectibles.tint(k);
                    c.rect(.{ .x = cx, .y = row.y + 10, .w = 9, .h = 9 }, .{ t[0], t[1], t[2], 1 });
                    cx += 13;
                }
                c.text(cx, row.y + 10, label, 1, if (have >= p.amount) gold else bad);
                cx += Canvas.textWidth(label, 1) + 14;
            };
        }
        y += 34;
    }
    const selected = Fabricator.recipes[rows[@min(shop.row, rows.len - 1)]];
    c.text(r.x + 18, r.y + r.h - 50, selected.about, 1, ink);
    c.text(r.x + 18, r.y + r.h - 28, if (@as(Fabricator.Tab, @enumFromInt(shop.tab)) == .aircraft) "LEFT RIGHT TAB  ENTER INSTALL / SELECT  ESC CLOSE" else "LEFT RIGHT TAB  ENTER FABRICATE  ESC CLOSE  FIND PICKUPS IN THE WORLD", 0.9, alpha(dim, 0.8));
}

// ---------------------------------------------------------------- conversations

fn drawTalk(c: *Canvas, sb: *const Sandbox, session: Dialogue.Session, hud: Hud) void {
    const v = hud.view;
    const d = &sb.dialogue;
    const node = d.node(session);
    const speaker = d.speaker(session);
    const scale: f32 = 1.3;
    const w = @min(v.w - 48, 980);
    const columns: usize = @intFromFloat(@max(20, (w - 48) / (Canvas.char_width * scale)));
    var lines: [10][]const u8 = undefined;
    const line_count = Canvas.wrap(node.text, columns, &lines);
    var visible: [Dialogue.max_choices]u8 = undefined;
    const revealed = d.revealed(session);
    const choices = if (revealed) d.visibleChoices(session, &sb.progress, &visible) else 0;
    const h = 44 + @as(f32, @floatFromInt(line_count)) * 18 + @as(f32, @floatFromInt(choices)) * 26 + 34;
    const r: Rect = .{ .x = v.x + (v.w - w) / 2, .y = v.y + v.h - h - 28, .w = w, .h = h };
    c.rect(r, panel_fill);
    const tint = Profile.accent_colors[@min(speaker.accent, Profile.accent_colors.len - 1)];
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 2 }, tint);
    // Name plate.
    var name_buffer: [32]u8 = undefined;
    var role_buffer: [48]u8 = undefined;
    const name = pretty(&name_buffer, speaker.name);
    const plate: Rect = .{ .x = r.x + 18, .y = r.y - 26, .w = Canvas.textWidth(name, 1.4) + 28, .h = 28 };
    c.rect(plate, panel_fill);
    c.rect(.{ .x = plate.x, .y = plate.y, .w = plate.w, .h = 2 }, tint);
    c.text(plate.x + 14, plate.y + 8, name, 1.4, tint);
    c.text(plate.x + plate.w + 12, plate.y + 10, pretty(&role_buffer, speaker.role), 1, dim);
    // Text, revealed character by character without reflowing.
    const shown: usize = @intFromFloat(@min(session.reveal, @as(f32, @floatFromInt(node.text.len))));
    var y = r.y + 22;
    for (lines[0..line_count]) |line| {
        const offset = @intFromPtr(line.ptr) - @intFromPtr(node.text.ptr);
        const count = std.math.clamp(@as(isize, @intCast(shown)) - @as(isize, @intCast(offset)), 0, @as(isize, @intCast(line.len)));
        c.text(r.x + 24, y, line[0..@intCast(count)], scale, ink);
        y += 18;
    }
    y += 10;
    if (choices > 0) {
        for (visible[0..choices], 0..) |choice_index, i| {
            const ch = node.choices[choice_index];
            const row: Rect = .{ .x = r.x + 14, .y = y, .w = r.w - 28, .h = 24 };
            const selected = session.choice == i;
            rowBack(c, row, selected);
            c.hit(row, hitId(.choice, i));
            var buffer: [96]u8 = undefined;
            const marker = switch (ch.action) {
                .trade => "  [TRADE]",
                .upgrades => "  [UPGRADES]",
                .wardrobe => "  [ARMOR]",
                .none => "",
            };
            c.text(row.x + 14, row.y + 7, std.fmt.bufPrint(&buffer, "{d}. {s}{s}", .{ i + 1, ch.text, marker }) catch ch.text, 1.1, if (selected) accent else ink);
            y += 26;
        }
    } else {
        // Blinking continue marker.
        const on = @mod(hud.time, 1.0) < 0.6;
        const label = if (revealed) "CONTINUE" else "...";
        if (on or !revealed) c.text(r.x + r.w - 24 - Canvas.textWidth(label, 1), r.y + r.h - 24, label, 1, tint);
        c.hit(r, hitId(.talk_continue, 0));
    }
    c.text(r.x + 24, r.y + r.h - 24, if (choices > 0) "UP DOWN CHOOSE  ENTER SAY  ESC LEAVE" else "ENTER OR CLICK  ESC LEAVE", 0.9, alpha(dim, 0.8));
}

fn expectInside(c: *const Canvas) !void {
    try std.testing.expect(c.len < Canvas.capacity and c.hit_len < Canvas.hit_capacity);
    for (c.commands[0..c.len]) |cmd| {
        const w = if (cmd.kind == .text) Canvas.textWidth(cmd.text[0..cmd.len], cmd.cell / 2) else cmd.w;
        try std.testing.expect(cmd.x >= 0 and cmd.y >= 0 and cmd.x + w <= c.width + 0.5 and cmd.y <= c.height);
    }
}

test "every screen lays out inside the window and records hits" {
    const Catalog = @import("../asset/Catalog.zig");
    const Camera = @import("../world/Camera.zig");
    var catalog: Catalog = undefined;
    var camera: Camera = .{};
    var sb: Sandbox = undefined;
    try Sandbox.testSandbox(&sb, &catalog, &camera);
    defer catalog.deinit(std.testing.allocator);
    defer sb.deinit();
    const view: Rect = .{ .x = 0, .y = 0, .w = 1280, .h = 720 };
    const hud: Hud = .{ .view = view, .clock = "DAY 0  08:00", .prompt = "MARKET STALL 1  CLICK TALK", .toast = "SAVED" };
    var c: Canvas = .{};
    var m: Menu = .{};
    const Case = struct { screen: Menu.Screen, base: Menu.Screen };
    for ([_]Case{ .{ .screen = .title, .base = .title }, .{ .screen = .settings, .base = .title }, .{ .screen = .none, .base = .none }, .{ .screen = .pause, .base = .pause }, .{ .screen = .settings, .base = .pause }, .{ .screen = .controls, .base = .pause }, .{ .screen = .quest_log, .base = .pause }, .{ .screen = .confirm_quit, .base = .pause } }) |case| {
        m.open(case.base);
        m.screen = case.screen;
        c.reset(1280, 720);
        draw(&c, &m, &sb, hud);
        try expectInside(&c);
        if (case.screen != .none) try std.testing.expect(c.hit_len > 0);
    }
    m.open(.none);
    // Panels: customization, every conversation node, the stall, upgrades and the wardrobe.
    sb.creator.begin(sb.profile);
    sb.creator.owned = Progress.free_suits;
    c.reset(1280, 720);
    draw(&c, &m, &sb, hud);
    try expectInside(&c);
    try std.testing.expect(c.hit_len >= @typeInfo(Profile.Field).@"enum".fields.len);
    sb.creator.open = false;
    for (sb.dialogue.parsed.value.conversations, 0..) |conv, ci| for (0..conv.nodes.len) |ni| {
        sb.talk = .{ .conversation = @intCast(ci), .node = @intCast(ni), .reveal = 999, .partner = .{ .keeper = 0 } };
        c.reset(1280, 720);
        draw(&c, &m, &sb, hud);
        try expectInside(&c);
    };
    sb.talk = null;
    sb.trading = 0;
    c.reset(1280, 720);
    draw(&c, &m, &sb, hud);
    try expectInside(&c);
    try std.testing.expectEqual(@as(?u16, hitId(.trade_close, 0)), blk: {
        for (c.hits[0..c.hit_len]) |h| if (hitArea(h.id) == .trade_close) break :blk h.id;
        break :blk null;
    });
    sb.trading = null;
    for ([_]@TypeOf(@as(Sandbox.Shop, undefined).kind){ .upgrades, .wardrobe }) |kind| {
        sb.shop = .{ .kind = kind };
        c.reset(1280, 720);
        draw(&c, &m, &sb, hud);
        try expectInside(&c);
    }
    sb.shop = .{ .kind = .fabricate, .tab = @intFromEnum(Fabricator.Tab.aircraft) };
    c.reset(1280, 720);
    draw(&c, &m, &sb, hud);
    try expectInside(&c);
    try std.testing.expect(c.hit_len >= 8);
    // Four-player split screen: three guest views, one trading.
    sb.shop = null;
    for (0..3) |i| sb.joinGuest(i);
    sb.guests[1].trading = 0;
    var guests: [3]Hud.Guest = undefined;
    for (&guests, 0..) |*g, i| {
        const r = @import("../render/Layout.zig").viewRect(i + 1, 4);
        g.* = .{ .index = @intCast(i), .view = .{ .x = r.x * 1280, .y = r.y * 720, .w = r.w * 1280, .h = r.h * 720 }, .prompt = "MARO'S STALL  X TRADE" };
    }
    var split = hud;
    split.view = .{ .x = 0, .y = 0, .w = 640, .h = 360 };
    split.guests = &guests;
    c.reset(1280, 720);
    draw(&c, &m, &sb, split);
    try expectInside(&c);
    const id = hitId(.choice, 3);
    try std.testing.expectEqual(Area.choice, hitArea(id));
    try std.testing.expectEqual(@as(u8, 3), hitRow(id));
}
