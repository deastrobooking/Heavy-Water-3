//! Layouts for every GUI screen, drawn into a `Canvas` from game state each frame: the title
//! and pause menus, settings, controls, the HUD, character customization, the market shop,
//! the tinker's upgrades and wardrobe, and conversations. Drawing never changes state; each
//! clickable element records a hit whose id says which control and row it is.
const std = @import("std");
const enum_compat = @import("enum_compat");
const Canvas = @import("Canvas.zig");
const Menu = @import("Menu.zig");
const Sandbox = @import("../game/Sandbox.zig");
const Profile = @import("../game/Profile.zig");
const Creator = @import("../game/Creator.zig");
const Progress = @import("../game/Progress.zig");
const Dialogue = @import("../game/Dialogue.zig");
const Settings = @import("../game/Settings.zig");
const Bindings = @import("../game/Bindings.zig");
const PadBindings = @import("../engine/PadBindings.zig");
const Fabricator = @import("../game/Fabricator.zig");
const Hangar = @import("../game/Hangar.zig");
const Build = @import("../game/Build.zig");
const Collectibles = @import("../game/Collectibles.zig");
const QuestLog = @import("../game/QuestLog.zig");
const CityContent = @import("../game/CityContent.zig");
const FoundryCase = @import("../game/FoundryCase.zig");
const Heroes = @import("../game/Heroes.zig");
const Specials = @import("../game/Specials.zig");
const Pets = @import("../game/Pets.zig");
const Encounters = @import("../game/Encounters.zig");
const Arena = @import("../game/Arena.zig");
const SpaceBattle = @import("../game/SpaceBattle.zig");
const Market = @import("../city/Market.zig");
const District = @import("../procedural/District.zig");
const CityGeography = @import("../procedural/CityGeography.zig");
const ChunkKey = @import("../world/ChunkKey.zig");
const Region = @import("../world/Region.zig");
const TerrainSites = @import("../procedural/TerrainSites.zig");
const Enemies = @import("../game/Enemies.zig");
const EnemyDesign = @import("../game/EnemyDesign.zig");
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
pub const Area = enum(u8) { fab_tab = 64, menu = 1, setting_left, setting_right, creator_field, creator_left, creator_right, creator_tab, creator_done, creator_imported, enemy_forge, enemy_part, enemy_left, enemy_right, enemy_palette_left, enemy_palette_right, enemy_style_left, enemy_style_right, imported_import_glb, imported_filter, imported_part, imported_surface_left, imported_surface_right, imported_palette_left, imported_palette_right, imported_color, imported_paint, imported_toggle, imported_undo, imported_redo, imported_back, imported_save, mesh_tool, trade_row, trade_close, shop_row, shop_close, choice, talk_continue, platform_editor, planet_globe, music_previous, music_toggle, music_next, build_tab, imported_library_prev, imported_library_next, imported_library_delete };
pub fn hitId(area: Area, row: usize) u16 {
    // The row is one byte; lists longer than that pass `row & 0xff` and resolve it on click.
    std.debug.assert(row < 256);
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
    /// How far tall panels and menus are scrolled (canvas units), kept by the application.
    scroll: f32 = 0,
    /// P1's keys for class specials 1–3.
    special_keys: [3][]const u8 = .{ "Z", "C", "H" },
    music_available: bool = false,
    music_playing: bool = false,
    music_track: []const u8 = "",
    music_track_index: usize = 0,
    music_track_count: usize = 0,
    space_trial: bool = false,

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
    c.focus(r);
    c.rect(r, alpha(accent, 0.16));
    c.rect(.{ .x = r.x, .y = r.y, .w = 3, .h = r.h }, accent);
}

fn button(c: *Canvas, r: Rect, label: []const u8, id: u16, hot: bool) void {
    if (hot) c.focus(r);
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
    if (menu.screen == .title or (menu.base == .title and menu.screen != .none)) {
        c.beginScroll(hud.scroll);
        defer c.endScroll();
        return drawTitle(c, menu, sb, hud);
    }
    for (hud.guests) |g| drawGuest(c, sb, g);
    @import("BlockPalette.zig").drawAll(c, sb, hud.view, hud.guests);
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
    const panels = sb.creator.open or sb.talk != null or sb.shop != null or sb.trading != null or sb.tools.platform_editor_open or menu.screen != .none;
    if (!sb.creator.open) drawHud(c, menu, sb, hud, panels);
    // Panels and menus scroll as one when they are taller than the screen (larger interface
    // sizes); the HUD above never moves.
    c.beginScroll(hud.scroll);
    defer c.endScroll();
    if (sb.creator.open) {
        if (sb.creator.imported_open and sb.creator.vertex_tools) {
            @import("MeshToolsPanel.zig").draw(c, &sb.creator, hud.view);
        } else if (sb.creator.imported_open) {
            drawImportedComponents(c, &sb.creator, hud.view);
        } else if (sb.creator.enemy_design_open) {
            drawEnemyDesign(c, &sb.creator, hud.view);
        } else {
            drawCreator(c, sb, hud.view);
        }
    } else if (sb.tools.platform_editor_open) drawPlatformEditor(c, sb) else if (sb.talk) |session| drawTalk(c, sb, session, hud) else if (sb.shop) |shop| switch (shop.kind) {
        .upgrades => drawUpgrades(c, sb, shop.row, hud.view),
        .wardrobe => drawWardrobe(c, sb, shop.row, hud.view),
        .fabricate => drawFabricator(c, sb, shop, hud.view),
    } else if (sb.trading) |stall| drawShop(c, sb, stall, hud.view) else if (hud.inspect.len > 0) drawInspect(c, hud);
    switch (menu.screen) {
        .none, .title => {},
        else => {
            // The dimming stays put and is not part of what scrolls.
            c.endScroll();
            c.rect(.{ .x = 0, .y = 0, .w = c.width, .h = c.height }, shade);
            c.beginScroll(hud.scroll);
            drawMenu(c, menu, sb, hud);
        },
    }
}

// ---------------------------------------------------------------- title and menus

fn drawTitle(c: *Canvas, menu: *const Menu, sb: ?*const Sandbox, hud: Hud) void {
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
    y = c.height * 0.41;
    if (menu.screen == .title) {
        for (Menu.title_items, 0..) |item, i| {
            const r: Rect = .{ .x = x - 14, .y = y, .w = w - x - 30, .h = 34 };
            const on = menu.enabled(i);
            rowBack(c, r, menu.row == i);
            c.text(r.x + 18, r.y + 10, item.label, 1.5, if (!on) alpha(dim, 0.5) else if (menu.row == i) accent else ink);
            if (on) c.hit(r, hitId(.menu, i));
            y += 40;
        }
    } else drawMenu(c, menu, sb, hud);
    const music_width = @min(408, @max(220, c.width * 0.32));
    drawMusicPlayer(c, hud, .{ .x = c.width - music_width - 24, .y = c.height - 134, .w = music_width, .h = 84 }, music_width < 340);
    // Load failures and other notices still need to reach the player here.
    if (hud.toast.len > 0) c.text(x, c.height - 70, hud.toast, 1.1, bad);
    c.text(x, c.height - 44, "ARROWS OR MOUSE  ENTER SELECT  ESC BACK", 1, dim);
    c.print(x, c.height - 26, 1, alpha(dim, 0.7), "SEED {d}  NATIVE ZIG  MACH", .{hud.seed});
}

fn drawMusicPlayer(c: *Canvas, hud: Hud, r: Rect, compact: bool) void {
    c.rect(r, .{ 0.012, 0.026, 0.036, 0.9 });
    c.frame(r, 1, alpha(accent, 0.55));
    c.text(r.x + 10, r.y + 7, "ECOSYSTEM MUSIC", 0.8, accent);
    if (!hud.music_available) {
        c.text(r.x + 10, r.y + 28, "NO PACKAGED MP3 TRACKS", 0.9, dim);
        return;
    }
    const max_name: usize = if (compact) (if (r.w < 220) 18 else 30) else 31;
    var shortened: [31]u8 = undefined;
    const name = if (hud.music_track.len > max_name) blk: {
        const prefix_len = max_name - 3;
        @memcpy(shortened[0..prefix_len], hud.music_track[0..prefix_len]);
        @memcpy(shortened[prefix_len..max_name], "...");
        break :blk shortened[0..max_name];
    } else hud.music_track;
    c.text(r.x + 10, r.y + 29, name, if (compact) 0.78 else 0.95, ink);
    // Keep the track label on its own row; centering these buttons used to put their labels
    // directly over the song title on both the title card and the compact gameplay widget.
    const button_y = r.y + r.h - 28;
    const button_w: f32 = 32;
    const gap: f32 = 4;
    const right = r.x + r.w - 10;
    const next: Rect = .{ .x = right - button_w, .y = button_y, .w = button_w, .h = 28 };
    const play: Rect = .{ .x = next.x - gap - button_w, .y = button_y, .w = button_w, .h = 28 };
    const previous: Rect = .{ .x = play.x - gap - button_w, .y = button_y, .w = button_w, .h = 28 };
    button(c, previous, "<<", hitId(.music_previous, 0), false);
    button(c, play, if (hud.music_playing) "II" else ">", hitId(.music_toggle, 0), false);
    button(c, next, ">>", hitId(.music_next, 0), false);
}

fn menuRect(c: *const Canvas, width: f32, height: f32) Rect {
    return .{ .x = (c.width - width) / 2, .y = (c.height - height) / 2, .w = width, .h = height };
}

fn drawMenu(c: *Canvas, menu: *const Menu, sb: ?*const Sandbox, hud: Hud) void {
    switch (menu.screen) {
        .pause, .confirm_quit, .party, .player, .music => {
            const list = menu.items();
            // The party setup is wider: each seat shows its pad, its character and their scrap.
            const r = menuRect(c, if (menu.screen == .party) @min(560, c.width - 24) else 400, 92 + @as(f32, @floatFromInt(list.len)) * 34 + (if (sb != null) @as(f32, 34) else 0));
            panel(c, r, switch (menu.screen) {
                .party => "FOUR PLAYER SETUP",
                .player => "PLAYER MENU",
                .music => "ECOSYSTEM MUSIC PLAYER",
                .pause => "PAUSED",
                else => "QUIT HEAVY WATER?",
            });
            if (menu.screen == .player) c.print(r.x + 240, r.y + 20, 1, accent, "P{d}", .{menu.hero_player + 1});
            if (menu.screen == .music) {
                const track = if (hud.music_available) hud.music_track else "NO PACKAGED MP3 TRACKS";
                c.text(r.x + 18, r.y + 38, track, 0.9, if (hud.music_available) gold else dim);
            }
            var y = r.y + (if (menu.screen == .music) @as(f32, 70) else 54);
            for (list, 0..) |item, i| {
                const row: Rect = .{ .x = r.x + 12, .y = y, .w = r.w - 24, .h = 30 };
                const on = menu.enabled(i);
                rowBack(c, row, menu.row == i);
                const label = if (menu.screen == .party and menu.base == .title and item.command == .@"resume")
                    "START GAME"
                else if (menu.screen == .music and item.command == .music_toggle and hud.music_playing)
                    "PAUSE MUSIC"
                else if (menu.screen == .music and item.command == .music_toggle)
                    "PLAY MUSIC"
                else
                    item.label;
                c.text(row.x + 16, row.y + 9, label, if (menu.screen == .party) 1 else 1.25, if (!on) alpha(dim, 0.5) else if (menu.row == i) accent else ink);
                if (on) c.hit(row, hitId(.menu, i));
                if (menu.screen == .party and i < 4) {
                    var controller: usize = 0;
                    for (menu.controller_players, 0..) |p, index| if (p == i) {
                        controller = index + 1;
                    };
                    // Who sits there (name and their own scrap), then their pad on the right.
                    const joined = menu.players_present & (@as(u8, 1) << @intCast(i)) != 0;
                    if (sb) |team| if (team.known[i]) {
                        const who = if (team.own_profiles[i]) |*own| own else team.profileOf(i);
                        const name = who.name();
                        c.print(row.x + 105, row.y + 9, 1, if (joined) accent else dim, "{s}", .{name[0..@min(name.len, 12)]});
                        c.print(row.x + 250, row.y + 9, 1, if (joined) gold else dim, "{d} SCRAP", .{team.kits[i].wallet.scrap});
                    } else c.text(row.x + 105, row.y + 9, if (joined) "JOINED" else "EMPTY", 1, dim);
                    c.print(row.x + row.w - 120, row.y + 9, 1, if (joined) accent else dim, "PAD {d}{s} {s}", .{ controller, if (controller > 0 and menu.controllers_connected[controller - 1]) " ON" else " OFF", if (menu.hero_player == i) "<" else "" });
                }
                y += 34;
            }
            if (sb) |s| if (menu.screen == .pause) {
                c.print(r.x + 18, r.y + r.h - 28, 1, dim, "DAY {d}   SCRAP {d}   PARTS {d}   UNSAVED PROGRESS IS LOST ON QUIT", .{ s.market.day, s.kits[0].wallet.scrap, s.kits[0].wallet.parts });
            };
        },
        .world_map => if (sb) |s| drawWorldMap(c, menu, s),
        .solar_system => if (sb) |s| drawSolarSystem(c, menu, s),
        .fighter_designer => if (sb) |s| drawFighterDesigner(c, menu, s),
        .build => if (sb) |s| drawBuildMenu(c, menu, s),
        .settings => drawSettings(c, menu),
        .controls => drawControls(c, menu),
        .pad_controls => drawPadControls(c, menu),
        .quest_log => if (sb) |s| drawQuestLog(c, menu, s),
        .pets => if (sb) |s| drawPets(c, menu, s),
        .guide => drawGuide(c, menu),
        .heroes => if (sb) |s| drawHeroes(c, menu, s),
        .arena => drawArena(c, menu, sb),
        else => {},
    }
}

/// The solar route: the four sectors in order from the Sun with their progress and locks, the
/// mining run, the fighter designer and BACK. A sector opens when the one before it falls to
/// its level 5 midboss.
fn drawSolarSystem(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const SpaceLevels = @import("../game/SpaceLevels.zig");
    const Arsenal = @import("../game/SpaceArsenal.zig");
    const r = menuRect(c, @min(860, c.width - 24), @min(600, c.height - 24));
    panel(c, r, "SOLAR SYSTEM  SPACE BATTLES");
    c.text(r.x + 22, r.y + 44, "CLEAR A SECTOR'S LEVEL 5 MIDBOSS TO OPEN THE NEXT ON THE ROUTE", 0.92, dim);
    const map: Rect = .{ .x = r.x + 26, .y = r.y + 76, .w = 250, .h = r.h - 150 };
    c.rect(map, .{ 0.015, 0.04, 0.085, 0.9 });
    c.frame(map, 1, alpha(accent, 0.5));
    const sun: Rect = .{ .x = map.x + map.w / 2 - 20, .y = map.y + 14, .w = 40, .h = 40 };
    c.rect(sun, .{ 1, 0.67, 0.18, 1 });
    c.centered(sun.x + 20, sun.y + 14, "SUN", 0.8, .{ 0.12, 0.08, 0.02, 1 });
    const step = (map.h - 90) / 4;
    for (0..SpaceLevels.location_count) |i| {
        const loc: SpaceLevels.Location = @enumFromInt(i);
        const y = map.y + 74 + @as(f32, @floatFromInt(i)) * step;
        const open = SpaceLevels.unlocked(&sb.progress, loc);
        const done = SpaceLevels.cleared(&sb.progress, loc, SpaceLevels.boss_level);
        // The route line from the previous stop.
        c.rect(.{ .x = map.x + 40, .y = y - step + 22, .w = 2, .h = step - 22 }, if (open) alpha(accent, 0.7) else alpha(dim, 0.35));
        const node: Rect = .{ .x = map.x + 30, .y = y, .w = 22, .h = 22 };
        c.rect(node, if (menu.row == i) gold else if (done) good else if (open) accent else alpha(dim, 0.5));
        c.text(map.x + 64, y, SpaceLevels.name(loc), 0.88, if (!open) dim else if (menu.row == i) gold else ink);
        if (open) {
            c.print(map.x + 64, y + 18, 0.75, if (done) good else dim, "{d}/10{s}", .{ SpaceLevels.clearedCount(&sb.progress, loc), if (done) "  SECURED" else "" });
        } else c.text(map.x + 64, y + 18, "LOCKED", 0.75, dim);
    }
    const list_x = r.x + 300;
    var y = r.y + 76;
    for (Menu.solar_items, 0..) |item, i| {
        const row: Rect = .{ .x = list_x, .y = y, .w = r.w - 320, .h = 44 };
        rowBack(c, row, menu.row == i);
        const on = menu.enabled(i);
        const color = if (!on) alpha(dim, 0.55) else if (menu.row == i) accent else ink;
        c.text(row.x + 12, row.y + 6, item.label, 0.98, color);
        var line: [96]u8 = undefined;
        const detail: []const u8 = if (i < Menu.solar_sectors) blk: {
            const loc: SpaceLevels.Location = @enumFromInt(i);
            if (!SpaceLevels.unlocked(&sb.progress, loc)) break :blk std.fmt.bufPrint(&line, "LOCKED: CLEAR {s} LEVEL 5", .{SpaceLevels.name(@enumFromInt(i - 1))}) catch "";
            const next = SpaceLevels.nextLevel(&sb.progress, loc);
            const what: []const u8 = if (next == SpaceLevels.boss_level) "MOTHER SHIP BOSS" else if (next == SpaceLevels.gate_level) "BATTLESHIP MIDBOSS" else "THREE WAVES";
            const who: []const u8 = switch (SpaceLevels.faction(loc)) {
                .brood => "BROOD",
                .armada => "ROBOT ARMADA",
                .mixed => "BROOD AND ARMADA",
            };
            break :blk std.fmt.bufPrint(&line, "NEXT: LEVEL {d}/10, {s}  {s}", .{ next, what, who }) catch "";
        } else if (i == Menu.solar_mining) "SHOOT ORE ROCKS; THE ORE IS YOURS UNTIL DEPOSITED" else if (i == Menu.solar_landing) (if (on) "SELENE RELAY: LUNAR VEINS, A STARTER BASE AND A HIVE BURROW" else "OPENS WHEN LUNA ORBIT LEVEL 10 IS CLEARED") else if (i == Menu.solar_designer) blk: {
            const p = Arsenal.base(sb.progress.space_frame);
            break :blk std.fmt.bufPrint(&line, "FLYING: {s}, {s}", .{ p.name, p.role }) catch "";
        } else "";
        c.text(row.x + 12, row.y + 25, detail, 0.78, if (on) dim else alpha(dim, 0.55));
        c.hit(row, hitId(.menu, i));
        y += 50;
    }
    c.text(list_x + 4, r.y + r.h - 50, "WASD MOVE  MOUSE / RIGHT STICK AIM  CLICK GUNS", 0.8, dim);
    c.text(list_x + 4, r.y + r.h - 32, "HOLD RIGHT CLICK CHARGE  Z MISSILE  C BOMB  F RETURN", 0.8, dim);
}

/// The six native fighter frames side by side: what each is for, how it flies and what it
/// carries, with its unlock state. Choosing an owned frame equips it; the next one is unlocked
/// here through the fabricator's rules. Team upgrades apply to every frame.
fn drawFighterDesigner(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const Arsenal = @import("../game/SpaceArsenal.zig");
    const r = menuRect(c, @min(900, c.width - 24), @min(600, c.height - 24));
    panel(c, r, "FIGHTER DESIGNER");
    const levels = sb.progress.kestrel_levels;
    var y = r.y + 56;
    for (Menu.designer_items, 0..) |item, i| {
        const row: Rect = .{ .x = r.x + 20, .y = y, .w = 300, .h = 58 };
        rowBack(c, row, menu.row == i);
        const on = menu.enabled(i);
        c.text(row.x + 12, row.y + 8, item.label, 1, if (!on) alpha(dim, 0.55) else if (menu.row == i) accent else ink);
        if (i < Progress.space_frame_count) {
            const frame: Progress.SpaceFrame = @enumFromInt(i);
            var line: [64]u8 = undefined;
            const owned = sb.progress.ownsSpaceFrame(frame);
            const state: []const u8 = if (owned)
                (if (sb.progress.space_frame == frame) "EQUIPPED" else "OWNED: CHOOSE TO EQUIP")
            else if (@import("../game/Fabricator.zig").status(&sb.progress, &sb.kits[0], .{ .space_frame = frame })) |why|
                why
            else blk: {
                const cost = Progress.spaceFrameCost(frame);
                break :blk std.fmt.bufPrint(&line, "{d} SCRAP  {d} PARTS  {d} GOLD", .{ cost.scrap, cost.parts, cost.gold }) catch "";
            };
            c.text(row.x + 12, row.y + 30, state, 0.8, if (sb.progress.space_frame == frame) good else if (owned) dim else gold);
        }
        c.hit(row, hitId(.menu, i));
        y += if (i + 1 < Progress.space_frame_count) 64 else 52;
    }
    const shown: Progress.SpaceFrame = if (menu.row < Progress.space_frame_count) @enumFromInt(menu.row) else sb.progress.space_frame;
    const p = Arsenal.profile(shown, levels);
    const card: Rect = .{ .x = r.x + 340, .y = r.y + 56, .w = r.w - 360, .h = r.h - 76 };
    c.rect(card, .{ 0.015, 0.04, 0.085, 0.9 });
    c.frame(card, 1, alpha(accent, 0.5));
    c.text(card.x + 18, card.y + 14, p.name, 1.4, accent);
    c.text(card.x + 18, card.y + 42, p.role, 0.95, gold);
    var wrapped: [3][]const u8 = undefined;
    const lines = Canvas.wrap(p.about, 52, &wrapped);
    for (wrapped[0..lines], 0..) |line, k| c.text(card.x + 18, card.y + 66 + @as(f32, @floatFromInt(k)) * 17, line, 0.9, ink);
    const hull = Hangar.configFor(shown, levels).hull_max;
    const Stat = struct { label: []const u8, value: f32, max: f32 };
    const stats = [_]Stat{
        .{ .label = "TOP SPEED", .value = p.top, .max = 220 },
        .{ .label = "AGILITY", .value = p.accel, .max = 150 },
        .{ .label = "HULL", .value = hull, .max = 840 },
        .{ .label = "ENERGY GUNS", .value = p.gun_damage / p.gun_interval, .max = 200 },
        .{ .label = "CHARGE BLAST", .value = p.charge_damage / p.charge_time, .max = 300 },
        .{ .label = "TRACKING MISSILES", .value = @floatFromInt(p.missiles), .max = 14 },
        .{ .label = "ENERGY BOMBS", .value = @floatFromInt(p.bombs), .max = 4 },
    };
    var sy = card.y + 70 + @as(f32, @floatFromInt(lines)) * 17 + 8;
    for (stats) |s| {
        c.text(card.x + 18, sy, s.label, 0.82, dim);
        bar(c, .{ .x = card.x + 190, .y = sy + 3, .w = card.w - 290, .h = 10 }, s.value / s.max, accent);
        c.print(card.x + card.w - 86, sy, 0.82, ink, "{d:.0}", .{s.value});
        sy += 26;
    }
    c.print(card.x + 18, sy + 8, 0.8, dim, "TEAM UPGRADES  ENGINE {d}  RACK {d}  COOLING {d}  ARMOR {d}", .{ levels[@intFromEnum(Progress.KestrelUpgrade.engine)], levels[@intFromEnum(Progress.KestrelUpgrade.missile_rack)], levels[@intFromEnum(Progress.KestrelUpgrade.gun_cooling)], levels[@intFromEnum(Progress.KestrelUpgrade.armor)] });
    c.text(card.x + 18, sy + 28, "UPGRADES AND PAINT: FABRICATOR, AIRCRAFT TAB", 0.8, dim);
    if (menu.space_trial_active) c.text(card.x + 18, sy + 48, "LEAVE THE BATTLE TO CHANGE FRAMES", 0.8, bad);
}

/// A compact, Minecraft-style inventory: category tabs and a fixed four-by-four card grid.
/// The three pages are bounded independently, so even a full blueprint library never scrolls.
fn drawBuildMenu(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const width = @min(940, c.width - 32);
    const height = @min(620, c.height - 32);
    const r = menuRect(c, width, height);
    panel(c, r, "BUILD INVENTORY");
    c.text(r.x + r.w - 262, r.y + 21, "CHOOSE A PIECE TO PLACE", 0.9, dim);

    const labels = [_][]const u8{ "STRUCTURES", "KITS", "BLUEPRINTS" };
    const tab_gap: f32 = 8;
    const tab_width = (r.w - 40 - 2 * tab_gap) / 3;
    for (labels, 0..) |label, i| {
        const tab: Rect = .{ .x = r.x + 20 + @as(f32, @floatFromInt(i)) * (tab_width + tab_gap), .y = r.y + 50, .w = tab_width, .h = 36 };
        const active = menu.build_tab == i;
        const focused = active and menu.build_tabs_focus;
        c.rect(tab, if (active) alpha(accent, 0.24) else alpha(accent, 0.07));
        c.frame(tab, if (focused) 2 else 1, if (active) accent else alpha(accent, 0.45));
        if (focused) c.focus(tab);
        const count = Build.paletteCount(sb, @enumFromInt(i));
        var title: [48]u8 = undefined;
        const text = std.fmt.bufPrint(&title, "{s}  {d}", .{ label, count }) catch label;
        c.centered(tab.x + tab.w / 2, tab.y + 11, text, 0.95, if (active) ink else dim);
        c.hit(tab, hitId(.build_tab, i));
    }

    const grid_x = r.x + 20;
    const grid_y = r.y + 102;
    const gap_x: f32 = 8;
    const gap_y: f32 = 7;
    const card_w = (r.w - 40 - 3 * gap_x) / 4;
    const card_h = @min(82, (height - 102 - 79 - 22 - 3 * gap_y) / 4);
    const palette: Build.Palette = @enumFromInt(menu.build_tab);
    for (0..Menu.build_slots) |i| {
        const x = grid_x + @as(f32, @floatFromInt(i % Menu.build_columns)) * (card_w + gap_x);
        const y = grid_y + @as(f32, @floatFromInt(i / Menu.build_columns)) * (card_h + gap_y);
        const card: Rect = .{ .x = x, .y = y, .w = card_w, .h = card_h };
        const entry = Build.paletteEntry(sb, palette, i) orelse {
            c.rect(card, .{ 1, 1, 1, 0.025 });
            c.frame(card, 1, .{ 1, 1, 1, 0.04 });
            continue;
        };
        const selected = !menu.build_tabs_focus and menu.row == i;
        c.rect(card, if (selected) alpha(accent, 0.21) else .{ 1, 1, 1, 0.055 });
        c.frame(card, if (selected) 2 else 1, if (selected) accent else .{ 0.32, 0.48, 0.52, 0.45 });
        if (selected) {
            c.focus(card);
            c.hit(card, hitId(.menu, i));
        } else c.hit(card, hitId(.menu, i));

        const tint: Color = switch (palette) {
            .structures => .{ 0.36 + @as(f32, @floatFromInt(i % 3)) * 0.08, 0.51, 0.43, 1 },
            .kits => .{ 0.26, 0.57 + @as(f32, @floatFromInt(i % 3)) * 0.08, 0.69, 1 },
            .blueprints => .{ 0.54, 0.43 + @as(f32, @floatFromInt(i % 3)) * 0.08, 0.69, 1 },
        };
        const icon_size = @min(36, card_h * 0.45);
        const icon: Rect = .{ .x = card.x + (card.w - icon_size) / 2, .y = card.y + 5, .w = icon_size, .h = icon_size };
        c.rect(icon, tint);
        c.rect(.{ .x = icon.x + icon_size * 0.12, .y = icon.y + icon_size * 0.12, .w = icon_size * 0.72, .h = 3 }, alpha(ink, 0.35));
        c.rect(.{ .x = icon.x + icon_size - 5, .y = icon.y + icon_size * 0.28, .w = 3, .h = icon_size * 0.58 }, alpha(.{ 0, 0, 0, 1 }, 0.24));

        var name_buffer: [64]u8 = undefined;
        const name = pretty(&name_buffer, Build.entryName(sb, entry));
        const fit = @min(1, (card.w - 12) / @max(1, Canvas.textWidth(name, 1)));
        c.centered(card.x + card.w / 2, card.y + card_h - 18, name, fit, ink);
    }

    const count = Build.paletteCount(sb, palette);
    if (count == 0) {
        c.text(grid_x + 8, grid_y + 44, "NO SAVED BLUEPRINTS YET  —  CAPTURE A BUILD WITH P", 1, dim);
    } else if (!menu.build_tabs_focus and menu.row < count) {
        if (Build.paletteEntry(sb, palette, menu.row)) |entry| {
            var detail: [96]u8 = undefined;
            const name = Build.entryName(sb, entry);
            const description = if (entry == .item and entry.item == .platform)
                "SELECT TO SET DECK DIRECTION AND HEIGHT"
            else
                "SELECT TO EQUIP  •  AIM AND PLACE IN THE WORLD";
            c.print(grid_x + 2, r.y + height - 79, 0.92, gold, "{s}   {s}", .{ pretty(&detail, name), description });
        }
    }
    c.text(grid_x + 2, r.y + height - 43, "ARROWS / D-PAD MOVE  UP TO TABS  ENTER / A SELECT  ESC / B BACK", 0.88, dim);
}

/// Who a player is playing: their hero's name, or their own ranger's.
fn playing(sb: *const Sandbox, p: usize) ?[]const u8 {
    const profile = if (p == 0) &sb.profile else if (sb.guests[p - 1].active) &sb.guests[p - 1].profile else return null;
    return profile.name();
}

fn wherePlaceFound(home: Heroes.Home, hero: u8, buffer: []u8) []const u8 {
    return switch (home) {
        .starter => "WITH YOU FROM THE START",
        .city => "FIND THEM IN THE CITY",
        .wilds => "FIND THEM IN THE WILDS",
        .cave => "FIND THEM IN THE MOUNTAIN CAVES",
        .arena => std.fmt.bufPrint(buffer, "CLEAR ARENA WAVE {d}", .{Encounters.arenaWave(hero) orelse 0}) catch "",
    };
}

/// The roster: player tabs, a card per hero (locked ones say where to find them), and the
/// chosen card's details: who they are, their powers and passives.
fn drawHeroes(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    // Natural height: taller than a small or scaled-up window, the screen scrolls.
    const narrow = c.width - 40 < 1000;
    const r = menuRect(c, @min(c.width - 40, 1140), if (narrow) 760 else 700);
    panel(c, r, "HEROES");
    var count_buffer: [48]u8 = undefined;
    const joined = @popCount(sb.progress.heroes);
    c.text(r.x + 140, r.y + 20, std.fmt.bufPrint(&count_buffer, "{d} OF {d} WILDKIN JOINED", .{ joined, Heroes.count }) catch "", 1, gold);
    // Player tabs.
    // Tabs beside the title when there is room, else on their own row beneath it.
    const tab_w: f32 = if (narrow) (r.w - 24 - 3 * 8) / 4 else 160;
    var tx = if (narrow) r.x + 12 else r.x + r.w - 4 * 170 - 12;
    const tab_y = if (narrow) r.y + 44 else r.y + 12;
    for (0..Menu.heroes_tabs) |p| {
        const on = menu.enabled(p);
        const tab: Rect = .{ .x = tx, .y = tab_y, .w = tab_w, .h = 30 };
        c.rect(tab, if (menu.hero_player == p) alpha(accent, 0.32) else alpha(accent, 0.08));
        if (menu.row == p) {
            c.frame(tab, 1, accent);
            c.focus(tab);
        }
        var label: [40]u8 = undefined;
        const who = playing(sb, p) orelse "NOT JOINED";
        c.text(tab.x + 10, tab.y + 10, std.fmt.bufPrint(&label, "P{d} {s}", .{ p + 1, who }) catch "", 0.9, if (!on) alpha(dim, 0.5) else if (menu.hero_player == p) accent else ink);
        if (on) c.hit(tab, hitId(.menu, p));
        tx += tab_w + 8;
    }
    // Cards: your own ranger, then every Wildkin.
    const columns: usize = Menu.heroes_columns;
    const gap: f32 = 8;
    const card_w = (r.w - 24 - gap * @as(f32, @floatFromInt(columns - 1))) / @as(f32, @floatFromInt(columns));
    const card_h: f32 = 74;
    const top = if (narrow) r.y + 86 else r.y + 54;
    for (Menu.heroes_ranger..Menu.heroes_back) |row| {
        const k = row - Menu.heroes_ranger;
        const card: Rect = .{ .x = r.x + 12 + @as(f32, @floatFromInt(k % columns)) * (card_w + gap), .y = top + @as(f32, @floatFromInt(k / columns)) * (card_h + gap), .w = card_w, .h = card_h };
        const selected = menu.row == row;
        const unlocked = menu.enabled(row);
        c.rect(card, if (selected) alpha(accent, 0.22) else .{ 1, 1, 1, 0.05 });
        if (selected) {
            c.frame(card, 2, accent);
            c.focus(card);
        }
        c.hit(card, hitId(.menu, row));
        if (row == Menu.heroes_ranger) {
            const own = sb.own_profiles[menu.hero_player] orelse sb.profile;
            c.rect(.{ .x = card.x + 8, .y = card.y + 10, .w = 30, .h = 30 }, Profile.skin_tones[own.skin]);
            c.text(card.x + 46, card.y + 12, "YOUR RANGER", 0.95, ink);
            c.text(card.x + 46, card.y + 30, if (own.class == .synthetic) "SYNTHETIC" else "HUMAN", 0.8, dim);
            continue;
        }
        const index: u8 = @intCast(row - Menu.heroes_first);
        const h = Heroes.roster[index];
        // A badge in the hero's colours: coat, marking stripe, accent spark.
        const badge: Rect = .{ .x = card.x + 8, .y = card.y + 10, .w = 30, .h = 30 };
        const coat = Profile.coat_colors[h.coat];
        c.rect(badge, if (unlocked) coat else .{ coat[0] * 0.25, coat[1] * 0.25, coat[2] * 0.25, 1 });
        c.rect(.{ .x = badge.x, .y = badge.y + 18, .w = badge.w, .h = 6 }, if (unlocked) Profile.coat_colors[h.marking] else .{ 0.2, 0.2, 0.22, 1 });
        if (unlocked) c.rect(.{ .x = badge.x + 21, .y = badge.y + 4, .w = 5, .h = 5 }, Profile.accent_colors[h.accent]);
        // Long names shrink to fit the card.
        const label = if (unlocked) h.name else "? ? ?";
        const fit = @min(0.88, (card.w - 54) / @max(1, Canvas.textWidth(label, 1)));
        c.text(card.x + 46, card.y + 10, label, fit, if (unlocked) ink else dim);
        var species: [24]u8 = undefined;
        c.text(card.x + 46, card.y + 27, pretty(&species, @tagName(h.species)), 0.78, dim);
        if (@import("../character/Beasts.zig").winged(h.species)) c.text(card.x + card.w - 34, card.y + 27, "FLY", 0.7, gold);
        if (!unlocked) c.text(card.x + 8, card.y + 52, "LOCKED", 0.75, alpha(bad, 0.8));
    }
    // Details of the selected card.
    const rows_used = (Menu.heroes_back - Menu.heroes_ranger + columns - 1) / columns;
    const dy = top + @as(f32, @floatFromInt(rows_used)) * (card_h + gap) + 4;
    const detail: Rect = .{ .x = r.x + 12, .y = dy, .w = r.w - 24, .h = r.y + r.h - dy - 44 };
    c.rect(detail, .{ 1, 1, 1, 0.04 });
    if (menu.chosenHero()) |index| {
        const h = Heroes.roster[index];
        const unlocked = menu.enabled(menu.row);
        var title: [64]u8 = undefined;
        c.text(detail.x + 14, detail.y + 12, std.fmt.bufPrint(&title, "{s}  {s}", .{ h.name, h.title }) catch "", 1.3, gold);
        var role: [24]u8 = undefined;
        c.text(detail.x + 14, detail.y + 36, pretty(&role, @tagName(h.role)), 0.9, accent);
        var wrapped: [3][]const u8 = undefined;
        const lines = Canvas.wrap(h.blurb, 60, &wrapped);
        for (wrapped[0..lines], 0..) |line, i| c.text(detail.x + 14, detail.y + 56 + @as(f32, @floatFromInt(i)) * 16, line, 1, ink);
        var where: [40]u8 = undefined;
        if (!unlocked) c.text(detail.x + 14, detail.y + detail.h - 22, wherePlaceFound(h.home, index, &where), 1, gold);
        // Powers and passives on the right.
        const px = detail.x + detail.w * 0.55;
        const keys = [_][]const u8{ "Z", "C", "H" };
        for (h.powers, 0..) |kind, i| {
            const about = Specials.info(kind);
            const y = detail.y + 12 + @as(f32, @floatFromInt(i)) * 22;
            c.rect(.{ .x = px, .y = y - 2, .w = 18, .h = 15 }, alpha(Profile.accent_colors[h.accent], 0.35));
            c.centered(px + 9, y + 2, keys[i], 0.8, ink);
            c.text(px + 26, y + 2, about.label, 0.95, ink);
            var mech: [24]u8 = undefined;
            c.text(px + 230, y + 2, pretty(&mech, @tagName(about.mechanic)), 0.8, dim);
        }
        c.print(px, detail.y + 86, 0.85, dim, "HEALTH +{d:.0}   SABER x{d:.2}   SPEED x{d:.2}   ENERGY {d:.0}/S{s}", .{ h.health, h.melee, h.speed, h.regen, if (Heroes.winged(index)) "   WINGS" else "" });
    } else {
        c.text(detail.x + 14, detail.y + 12, "YOUR RANGER", 1.3, gold);
        c.text(detail.x + 14, detail.y + 38, "Go back to the character you made: tech or synthetic powers, by class.", 1, ink);
    }
    var hint: [80]u8 = undefined;
    c.text(r.x + 18, r.y + r.h - 28, std.fmt.bufPrint(&hint, "UP TO THE TABS TO PICK A PLAYER  ENTER PLAY AS  ESC BACK   (CHOOSING FOR P{d})", .{menu.hero_player + 1}) catch "", 0.9, dim);
    const back: Rect = .{ .x = r.x + r.w - 136, .y = r.y + r.h - 40, .w = 112, .h = 28 };
    button(c, back, "BACK", hitId(.menu, Menu.heroes_back), menu.row == Menu.heroes_back);
}

/// The Starbowl: what it is, the party, the best wave, and start / leave.
fn drawArena(c: *Canvas, menu: *const Menu, sb: ?*const Sandbox) void {
    const r = menuRect(c, 560, 440);
    panel(c, r, "BATTLE ARENAS");
    var wrapped: [4][]const u8 = undefined;
    const lines = Canvas.wrap("Drop into the Starbowl for Hive waves and Wildkin champions. The Solar System chart starts rising three-wave battles at Luna, Mars, the Asteroid Belt and Kuiper Belt; level 10 brings a Hive Mother Ship. The separate asteroid mining operation sends drone-harvested ore to the shared colony stockpile. Orbital flight: A/D strafe, W accelerate, Q/E rise, Shift boost, S brake, click / RT fire, F return.", 60, &wrapped);
    for (wrapped[0..lines], 0..) |line, i| c.text(r.x + 22, r.y + 52 + @as(f32, @floatFromInt(i)) * 17, line, 1, ink);
    var y = r.y + 52 + @as(f32, @floatFromInt(lines)) * 17 + 10;
    if (sb) |s| {
        c.print(r.x + 22, y, 1, gold, "BEST WAVE {d}", .{s.progress.arena_best});
        y += 22;
        for (0..4) |p| if (playing(s, p)) |who| {
            c.print(r.x + 22, y, 0.95, dim, "P{d}  {s}", .{ p + 1, who });
            y += 17;
        };
    }
    y = r.y + r.h - @as(f32, @floatFromInt(Menu.arena_items.len)) * 36 - 14;
    for (Menu.arena_items, 0..) |item, i| {
        const row: Rect = .{ .x = r.x + 12, .y = y, .w = r.w - 24, .h = 30 };
        const on = menu.enabled(i);
        rowBack(c, row, menu.row == i);
        if (i == 0) {
            const left: Rect = .{ .x = row.x + 8, .y = row.y + 2, .w = 30, .h = 26 };
            const right: Rect = .{ .x = row.x + row.w - 38, .y = row.y + 2, .w = 30, .h = 26 };
            button(c, left, "<", hitId(.setting_left, i), false);
            button(c, right, ">", hitId(.setting_right, i), false);
            c.centered(row.x + row.w / 2, row.y + 9, Arena.venueName(menu.arena_venue), 1.05, if (menu.row == i) accent else ink);
            c.hit(.{ .x = row.x + 40, .y = row.y, .w = row.w - 80, .h = row.h }, hitId(.menu, i));
        } else {
            c.text(row.x + 16, row.y + 9, item.label, 1.25, if (!on) alpha(dim, 0.5) else if (menu.row == i) accent else ink);
            if (on) c.hit(row, hitId(.menu, i));
        }
        y += 36;
    }
}

fn drawQuestLog(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const r = menuRect(c, 620, 500);
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
    // The city half: the three allies to expose, the boss, and the city's freedom.
    const detroit = &CityContent.detroit;
    y += 32;
    c.text(r.x + 24, y, if (detroit.draft) "LIBERATE DETROIT  (DRAFT CONTENT)" else "LIBERATE DETROIT", 1, alpha(accent, 0.85));
    y += 24;
    for (detroit.missions, 0..) |m, i| {
        const done = CityContent.exposed(detroit, &sb.progress, i);
        const begun = CityContent.started(detroit, &sb.progress, i);
        c.text(r.x + 24, y, if (done) "[x]" else "[ ]", 1, if (done) good else dim);
        c.text(r.x + 58, y, m.title, 1, if (done) dim else ink);
        if (!done and begun and i == 0) c.print(r.x + r.w - 130, y, 0.8, gold, "PAGES {d}/3", .{FoundryCase.count(&sb.progress)}) else if (!done and begun) c.text(r.x + r.w - 130, y, "IN PROGRESS", 0.8, gold);
        y += 21;
    }
    const boss_done = CityContent.bossDefeated(detroit, &sb.progress);
    c.text(r.x + 24, y, if (boss_done) "[x]" else "[ ]", 1, if (boss_done) good else dim);
    c.text(r.x + 58, y, detroit.boss.name, 1, if (boss_done) dim else ink);
    const back: Rect = .{ .x = r.x + r.w - 136, .y = r.y + r.h - 48, .w = 112, .h = 30 };
    button(c, back, "BACK", hitId(.menu, 0), menu.row == 0);
}

fn drawPets(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const r = menuRect(c, @min(660, c.width - 24), @min(520, c.height - 24));
    panel(c, r, "PETS & ROBOTS");
    const kit = &sb.kits[0];
    var y = r.y + 52;
    c.text(r.x + 24, y, "YOUR COMPANION", 0.9, dim);
    y += 22;
    if (kit.pet_active) |species| {
        c.print(r.x + 24, y, 1.2, gold, "{s}  {s}  LV {d}", .{ Pets.info(species).name, Pets.info(species).kind, kit.petLevel(species) });
        y += 24;
        if (sb.pets.out[0]) |pet| {
            c.print(r.x + 24, y, 0.88, ink, "HEALTH {d:.0}/{d:.0}", .{ pet.health, pet.max_health });
        } else c.text(r.x + 24, y, "WILL REJOIN BESIDE YOU WHEN PLAY RESUMES", 0.82, dim);
        y += 18;
        const xp = kit.pet_xp[@intFromEnum(species)];
        const level = kit.petLevel(species);
        if (level < Pets.max_level) {
            const start_xp = Pets.xpAtLevel(level);
            const earned = xp - start_xp;
            const needed = @as(u32, level) * 60;
            c.print(r.x + 24, y, 0.78, ink, "XP {d}/{d} TO LV {d}", .{ earned, needed, level + 1 });
            bar(c, .{ .x = r.x + 164, .y = y + 2, .w = 180, .h = 7 }, @as(f32, @floatFromInt(earned)) / @as(f32, @floatFromInt(needed)), gold);
        } else {
            c.text(r.x + 24, y, "MAX LEVEL 20", 0.78, gold);
        }
        y += 17;
        c.text(r.x + 24, y, Pets.milestone(level), 0.78, accent);
        y += 17;
        c.text(r.x + 24, y, Pets.nextMilestone(level), 0.78, dim);
    } else {
        c.text(r.x + 24, y, "NO ACTIVE COMPANION", 1, bad);
    }
    y += 36;
    c.text(r.x + 24, y, "WILDLIFE TO RESCUE", 0.9, dim);
    c.text(r.x + 342, y, "DISTANCE", 0.78, dim);
    y += 22;
    for (std.enums.values(Pets.Species), 0..) |species, i| {
        const row: Rect = .{ .x = r.x + 20, .y = y - 3, .w = r.w - 40, .h = 22 };
        const owned = kit.hasPet(species);
        if (i % 2 == 0) c.rect(row, .{ 1, 1, 1, 0.035 });
        c.text(row.x + 8, row.y + 5, Pets.info(species).name, 0.9, if (owned) good else ink);
        c.text(row.x + 112, row.y + 5, Pets.info(species).kind, 0.82, dim);
        if (owned) {
            c.text(row.x + row.w - 112, row.y + 5, "RESCUED", 0.82, good);
        } else if (sb.pets.placed) {
            const spot = sb.pets.spots[i].position;
            const dx = spot[0] - sb.player.feet[0];
            const dz = spot[2] - sb.player.feet[2];
            c.print(row.x + row.w - 112, row.y + 5, 0.82, gold, "{d:.0} M", .{@sqrt(dx * dx + dz * dz)});
        }
        y += 24;
    }
    y += 12;
    c.text(r.x + 24, y, "WEAKEN A WILD PET WITH TWO ENERGY-NET HITS, THEN INTERACT TO RESCUE IT.", 0.75, ink);
    y += 20;
    c.text(r.x + 24, y, if (kit.robot_built) "FIELD DROID: BUILT — FOLLOWS AND FIGHTS BESIDE YOUR ANIMAL." else "FIELD DROID: BUILD AT THE FABRICATOR — 2 ROTOR CORES, 8 HIVE ALLOY, 8 PARTS.", 0.75, if (kit.robot_built) good else accent);
    const track: Rect = .{ .x = r.x + 20, .y = r.y + r.h - 48, .w = 176, .h = 30 };
    const back: Rect = .{ .x = r.x + r.w - 136, .y = r.y + r.h - 48, .w = 112, .h = 30 };
    button(c, track, "TRACK WILDLIFE", hitId(.menu, 0), menu.row == 0);
    button(c, back, "BACK", hitId(.menu, 1), menu.row == 1);
}

/// HOW TO PLAY: page tabs across the top, the page's lines, and BACK.
fn drawGuide(c: *Canvas, menu: *const Menu) void {
    const Guide = @import("Guide.zig");
    const r = menuRect(c, @min(720, c.width - 24), 420);
    panel(c, r, "HOW TO PLAY");
    const tab_w = (r.w - 24) / @as(f32, @floatFromInt(Guide.page_count));
    for (Guide.pages, 0..) |page, i| {
        const tab: Rect = .{ .x = r.x + 12 + @as(f32, @floatFromInt(i)) * tab_w, .y = r.y + 46, .w = tab_w - 4, .h = 24 };
        const showing = menu.guide_page == i;
        rowBack(c, tab, showing or menu.row == i);
        c.hit(tab, hitId(.menu, i));
        const scale: f32 = 0.72;
        c.text(tab.x + (tab.w - Canvas.textWidth(page.title, scale)) / 2, tab.y + 8, page.title, scale, if (showing) accent else dim);
    }
    const page = Guide.pages[menu.guide_page];
    for (page.lines, 0..) |line, i| {
        const indented = line.len > 2 and line[0] == ' ';
        c.text(r.x + 24, r.y + 88 + @as(f32, @floatFromInt(i)) * 24, line, 0.82, if (indented) dim else ink);
    }
    c.text(r.x + 24, r.y + r.h - 34, "LEFT / RIGHT TURN THE PAGE   KEYS SHOWN ARE THE DEFAULTS (SEE CONTROLS)", 0.72, dim);
    const back: Rect = .{ .x = r.x + r.w - 124, .y = r.y + r.h - 42, .w = 104, .h = 28 };
    button(c, back, "BACK", hitId(.menu, Menu.guide_back), menu.row == Menu.guide_back);
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
    c.text(r.x + 18, r.y + r.h - 22, if (menu.settings.max_progression_test) "TEST MODE: WORLD AND RANGER SAVES DISABLED" else "LEFT RIGHT CHANGE  SAVED AUTOMATICALLY", 1, dim);
}

fn drawControls(c: *Canvas, menu: *const Menu) void {
    const rows: f32 = @floatFromInt(Menu.controls_column);
    // The key rows, then five lines of notes and the buttons below them.
    const r = menuRect(c, 780, 60 + rows * 21 + 150);
    panel(c, r, "CONTROLS");
    const keyboard_tab: Rect = .{ .x = r.x + r.w - 250, .y = r.y + 12, .w = 104, .h = 25 };
    const gamepad_tab: Rect = .{ .x = r.x + r.w - 138, .y = r.y + 12, .w = 120, .h = 25 };
    rowBack(c, keyboard_tab, true);
    c.text(keyboard_tab.x + 16, keyboard_tab.y + 8, "KEYBOARD", 0.9, accent);
    button(c, gamepad_tab, "GAMEPAD", hitId(.menu, Menu.controls_gamepad), false);
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
    c.text(r.x + 24, r.y + r.h - 146, message, 0.84, if (menu.swapped != null and !menu.capturing) gold else dim);
    c.text(r.x + 24, r.y + r.h - 126, "FLIGHT: V TOGGLE  SHIFT ACCELERATE  ALT BRAKE  SPACE UP  E/Q CLIMB / DESCEND", 0.8, dim);
    c.text(r.x + 24, r.y + r.h - 106, "KESTREL: MOUSE AIM  SHIFT BOOST  ALT BRAKE  CTRL ROLL  CLICK GUNS  HOLD/RELEASE RMB MISSILE  F EXIT", 0.76, dim);
    c.text(r.x + 24, r.y + r.h - 86, "COMBAT: CLICK ATTACK  RMB WEAPON FIRE / SABER GUARD  X DIVE KICK  Z/C/H SPECIALS", 0.76, dim);
    c.text(r.x + 24, r.y + r.h - 66, "BLOCKS: SHIFT+CLICK CORNERS FILL  SHIFT+TAB STYLE  SHIFT+T RESTYLE  SHIFT+P COPY  MORE IN HOW TO PLAY", 0.76, dim);
    const gamepad: Rect = .{ .x = r.x + 18, .y = r.y + r.h - 40, .w = 170, .h = 26 };
    button(c, gamepad, "GAMEPAD SETUP", hitId(.menu, Menu.controls_gamepad), menu.row == Menu.controls_gamepad);
    const reset: Rect = .{ .x = r.x + r.w - 290, .y = r.y + r.h - 40, .w = 150, .h = 26 };
    const back: Rect = .{ .x = r.x + r.w - 130, .y = r.y + r.h - 40, .w = 110, .h = 26 };
    button(c, reset, "RESET KEYS", hitId(.menu, Menu.controls_reset), menu.row == Menu.controls_reset);
    button(c, back, "BACK", hitId(.menu, Menu.controls_back), menu.row == Menu.controls_back);
}

fn drawPadControls(c: *Canvas, menu: *const Menu) void {
    const r = menuRect(c, 880, 650);
    panel(c, r, "CONTROLLER MAPPING");
    const keyboard_tab: Rect = .{ .x = r.x + r.w - 250, .y = r.y + 12, .w = 104, .h = 25 };
    const gamepad_tab: Rect = .{ .x = r.x + r.w - 138, .y = r.y + 12, .w = 120, .h = 25 };
    button(c, keyboard_tab, "KEYBOARD", hitId(.menu, Menu.pad_keyboard_tab), false);
    rowBack(c, gamepad_tab, true);
    c.text(gamepad_tab.x + 22, gamepad_tab.y + 8, "GAMEPAD", 0.9, accent);
    const mapping = menu.settings.pad_mapping;
    for (0..PadBindings.action_count) |i| {
        const column: f32 = @floatFromInt(i / Menu.pad_controls_column);
        const row: f32 = @floatFromInt(i % Menu.pad_controls_column);
        const item: Rect = .{ .x = r.x + 14 + column * 426, .y = r.y + 52 + row * 23, .w = 414, .h = 21 };
        const selected = menu.row == i;
        rowBack(c, item, selected);
        c.hit(item, hitId(.menu, i));
        c.text(item.x + 10, item.y + 6, PadBindings.actionName(@enumFromInt(i)), 0.9, if (selected) accent else ink);
        const action: PadBindings.Action = @enumFromInt(i);
        const value = if (menu.pad_capturing_action == action)
            (if (@mod(menu.seconds, 1) < 0.6) "PRESS PAD BUTTON" else "")
        else
            PadBindings.buttonName(mapping.button(action));
        c.text(item.x + item.w - 10 - Canvas.textWidth(value, 0.85), item.y + 6, value, 0.85, gold);
    }

    const axes_y = r.y + 52 + @as(f32, @floatFromInt(Menu.pad_controls_column)) * 23 + 10;
    for (0..PadBindings.axis_count) |i| {
        const row: Rect = .{ .x = r.x + 20 + @as(f32, @floatFromInt(i % 2)) * 270, .y = axes_y + @as(f32, @floatFromInt(i / 2)) * 24, .w = 258, .h = 22 };
        const item_row = Menu.pad_axis_start + i;
        rowBack(c, row, menu.row == item_row);
        c.hit(row, hitId(.menu, item_row));
        const logical = if (i < 2) (if (i == 0) "MOVE X" else "MOVE Y") else (if (i == 2) "LOOK X" else "LOOK Y");
        c.text(row.x + 9, row.y + 6, logical, 0.85, if (menu.row == item_row) accent else ink);
        var value_buffer: [48]u8 = undefined;
        const value = std.fmt.bufPrint(&value_buffer, "{s}{s}", .{ PadBindings.axisName(mapping.axes[i]), if (mapping.invert[i]) "  INV" else "" }) catch "";
        c.text(row.x + row.w - 8 - Canvas.textWidth(value, 0.75), row.y + 7, value, 0.75, gold);
    }

    const values_y = axes_y + 56;
    const deadzone_row: Rect = .{ .x = r.x + 20, .y = values_y, .w = 235, .h = 22 };
    rowBack(c, deadzone_row, menu.row == Menu.pad_deadzone);
    c.hit(deadzone_row, hitId(.menu, Menu.pad_deadzone));
    c.print(deadzone_row.x + 9, deadzone_row.y + 7, 0.85, if (menu.row == Menu.pad_deadzone) accent else ink, "STICK DEADZONE  {d:.2}", .{mapping.deadzone});
    const trigger_row: Rect = .{ .x = r.x + 266, .y = values_y, .w = 260, .h = 22 };
    rowBack(c, trigger_row, menu.row == Menu.pad_trigger_threshold);
    c.hit(trigger_row, hitId(.menu, Menu.pad_trigger_threshold));
    c.print(trigger_row.x + 9, trigger_row.y + 7, 0.85, if (menu.row == Menu.pad_trigger_threshold) accent else ink, "TRIGGER POINT  {d:.2}", .{mapping.trigger_threshold});
    const slot_row: Rect = .{ .x = r.x + 20, .y = values_y + 28, .w = 300, .h = 22 };
    rowBack(c, slot_row, menu.row == Menu.pad_preset_slot);
    c.hit(slot_row, hitId(.menu, Menu.pad_preset_slot));
    const preset_name = std.mem.sliceTo(&menu.pad_preset_label, 0);
    c.print(slot_row.x + 9, slot_row.y + 7, 0.85, if (menu.row == Menu.pad_preset_slot) accent else ink, "PRESET SLOT {d}  {s}", .{ menu.pad_preset_slot_index + 1, if (preset_name.len == 0) "(EMPTY OR CUSTOM)" else preset_name });
    // Below the presets, clear of the panel title it used to run into.
    c.text(r.x + 24, slot_row.y + 40, "STANDARD AND GENERIC HID GAMEPADS CAN BE REMAPPED; SETTINGS SAVE AUTOMATICALLY", 0.86, dim);

    c.text(r.x + 24, r.y + r.h - 138, "BUILD: HOLD LT + D-PAD LEFT TO START / STOP; RT PLACE  RB REMOVE; X CREATIVE FREE-BUILD", 0.78, dim);
    c.text(r.x + 24, r.y + r.h - 118, "CREATIVE BLOCKS: LT PLACE  RT REMOVE  D-PAD UP PIECE / LEFT-RIGHT MATERIAL / DOWN TURN", 0.78, dim);
    c.text(r.x + 24, r.y + r.h - 98, "MOVE / AIM: LEFT STICK / RIGHT STICK  LT BOOSTS  B DODGES ON FOOT / BRAKES IN FLIGHT", 0.82, dim);
    c.text(r.x + 24, r.y + r.h - 78, "FLIGHT: Y CYCLES / EXITS SUIT  A ASCENDS  D-PAD UP / DOWN CLIMBS / DESCENDS  X EXITS KESTREL", 0.78, dim);
    c.text(r.x + 24, r.y + r.h - 58, "COMBAT: RT FIRES  RB SABER / GUARD; IN KESTREL RT FIRES, RB LOCKS / RELEASES MISSILES", 0.78, dim);
    const y = r.y + r.h - 38;
    const export_button: Rect = .{ .x = r.x + r.w - 445, .y = y, .w = 104, .h = 25 };
    const import_button: Rect = .{ .x = r.x + r.w - 335, .y = y, .w = 104, .h = 25 };
    const reset_button: Rect = .{ .x = r.x + r.w - 225, .y = y, .w = 104, .h = 25 };
    const back_button: Rect = .{ .x = r.x + r.w - 115, .y = y, .w = 96, .h = 25 };
    button(c, export_button, "EXPORT", hitId(.menu, Menu.pad_export), menu.row == Menu.pad_export);
    button(c, import_button, "IMPORT", hitId(.menu, Menu.pad_import), menu.row == Menu.pad_import);
    button(c, reset_button, "RESET", hitId(.menu, Menu.pad_reset), menu.row == Menu.pad_reset);
    button(c, back_button, "BACK", hitId(.menu, Menu.pad_back), menu.row == Menu.pad_back);
}

// ---------------------------------------------------------------- HUD

/// Settlers and beds, food, the shared stockpile, P1's unbanked ore and the research in progress.
/// Hidden until the team has a colony or ore to bring to one.
fn colonyPanel(c: *Canvas, sb: *const Sandbox, r: Rect) void {
    const Colony = @import("../game/Colony.zig");
    const colony = &sb.mining.colony;
    const held = sb.kits[0].ore;
    var any = colony.settlers > 0 or (colony.hours > 0 and sb.outpost.len > 0);
    for (0..Colony.ore_count) |o| any = any or held[o] > 0 or colony.stockpile[o] > 0;
    if (!any) return;
    const in = @import("../game/Mining.zig").colonyInputs(sb);
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    c.print(r.x + 14, r.y + 10, 1, gold, "COLONY  {d}/{d} SETTLERS  FOOD {d}", .{ colony.settlers, colony.beds(in), colony.food });
    c.print(r.x + 14, r.y + 30, 1, ink, "IRON {d}  COPPER {d}  CRYSTAL {d}", .{ colony.stockpile[0], colony.stockpile[1], colony.stockpile[2] });
    if (held[0] + held[1] + held[2] > 0) c.print(r.x + r.w - 14 - 90, r.y + 30, 1, dim, "HELD {d}/{d}/{d}", .{ held[0], held[1], held[2] });
    if (colony.current()) |t| {
        const need = Colony.info(t);
        c.print(r.x + 14, r.y + 50, 1, if (in.research > 0) ink else dim, "RESEARCH {s} {d}/{d}", .{ need.name, @min(colony.research_points, need.points), need.points });
    } else c.text(r.x + 14, r.y + 50, "ALL RESEARCH DONE", 1, dim);
}

/// The orbital battle's HUD: mission and score across the top, the boss's health under it, and
/// the fighter's hull and four weapon systems bottom left.
fn spaceHud(c: *Canvas, v: Rect, sb: *const Sandbox) void {
    const SpaceLevels = @import("../game/SpaceLevels.zig");
    const Arsenal = @import("../game/SpaceArsenal.zig");
    const battle = &sb.space_battle;
    const w: f32 = @min(v.w - 32, 520);
    const banner: Rect = .{ .x = v.x + (v.w - w) / 2, .y = v.y + 18, .w = w, .h = 58 };
    c.rect(banner, .{ 0.015, 0.035, 0.07, 0.82 });
    c.frame(banner, 1.5, if (battle.warning or battle.hit_flash > 0) bad else alpha(accent, 0.8));
    if (battle.mining) {
        c.text(banner.x + 12, banner.y + 8, "ASTEROID MINING RUN", 1, accent);
        c.print(banner.x + 12, banner.y + 32, 0.92, ink, "THIS RUN  IRON {d}  COPPER {d}  CRYSTAL {d}   F RETURN", .{ battle.ore[0], battle.ore[1], battle.ore[2] });
    } else if (battle.result == .won) {
        c.print(banner.x + 12, banner.y + 8, 1, good, "{s} LEVEL {d} CLEAR  SCORE {d}", .{ SpaceLevels.name(battle.location), battle.level, battle.score });
        c.print(banner.x + 12, banner.y + 32, 0.92, ink, "+{d} SCRAP  +{d} XP FROM KILLS   H NEXT LEVEL   F RETURN", .{ battle.earned_scrap, battle.earned_xp });
    } else {
        c.print(banner.x + 12, banner.y + 8, 1, accent, "{s}  LEVEL {d}/10  WAVE {d}/3", .{ SpaceLevels.name(battle.location), battle.level, battle.wave });
        c.print(banner.x + 12, banner.y + 32, 0.92, if (battle.warning) bad else ink, "HOSTILES {d}  SCORE {d}  CHAIN X{d}{s}", .{ battle.liveEnemies(), battle.score, battle.chain, if (battle.warning) "  EDGE OF THE ARENA" else "" });
    }
    if (battle.heavy()) |boss| {
        const bw = w;
        const r: Rect = .{ .x = banner.x, .y = banner.y + banner.h + 6, .w = bw, .h = 12 };
        bar(c, r, boss.health / boss.max_health, bad);
        const label = if (boss.kind == .mother_ship) "MOTHER SHIP" else "BATTLESHIP";
        if (boss.kind == .mother_ship) {
            c.print(r.x, r.y + 16, 0.8, ink, "{s}  PHASE {d} OF 3", .{ label, boss.mode });
        } else c.text(r.x, r.y + 16, label, 0.8, ink);
    }
    const f = sb.hangar.fighter orelse return;
    const p = battle.profile;
    const wpn = battle.weapons;
    // Above the controls line at the bottom of the view.
    const panel_r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 236, .w = 300, .h = 148 };
    c.rect(panel_r, .{ 0.015, 0.035, 0.07, 0.82 });
    c.text(panel_r.x + 12, panel_r.y + 8, Arsenal.base(battle.frame).name, 1, accent);
    const rows = [_]struct { label: []const u8, value: f32, color: Color }{
        .{ .label = "HULL", .value = f.hull / f.hull_max, .color = if (f.hull < f.hull_max * 0.3) bad else good },
        .{ .label = if (wpn.overheated) "GUNS VENTING" else "GUN HEAT", .value = wpn.heat, .color = if (wpn.overheated) bad else gold },
        .{ .label = "CHARGE", .value = wpn.chargeShare(p), .color = if (wpn.chargeShare(p) >= Arsenal.min_charge) accent else dim },
    };
    for (rows, 0..) |row, k| {
        const y = panel_r.y + 32 + @as(f32, @floatFromInt(k)) * 20;
        c.text(panel_r.x + 12, y, row.label, 0.78, dim);
        bar(c, .{ .x = panel_r.x + 120, .y = y + 2, .w = 166, .h = 9 }, row.value, row.color);
    }
    c.print(panel_r.x + 12, panel_r.y + 96, 0.82, ink, "Z MISSILES {d}/{d}{s}", .{ wpn.missiles, p.missiles, if (battle.lock != null and wpn.missiles > 0) "  LOCKED" else "" });
    c.print(panel_r.x + 12, panel_r.y + 118, 0.82, ink, "C ENERGY BOMBS {d}/{d}", .{ wpn.bombs, p.bombs });
}

fn drawHud(c: *Canvas, menu: *const Menu, sb: *const Sandbox, hud: Hud, panels: bool) void {
    const v = hud.view;
    // Vitals, bottom left (hidden under conversation and shop panels).
    if (sb.seated == null and !panels and !hud.space_trial) {
        vitals(c, v, sb.player, sb.profile, sb.combat.vitals[0]);
        petStatus(c, v, sb, 0);
        specials(c, v, sb, 0, sb.profile, hud.special_keys);
        if (sb.tools.tool == .weapon) weaponLine(c, v, sb, 0);
    }
    // Wallet and colony clock, top right. Orbital missions use the same space for mission state.
    if (!sb.hangar.space_mode) {
        var buffer: [48]u8 = undefined;
        const scrap = std.fmt.bufPrint(&buffer, "{d} SCRAP", .{sb.kits[0].wallet.scrap}) catch "";
        const w: f32 = 290;
        const r: Rect = .{ .x = v.x + v.w - w - 20, .y = v.y + 20, .w = w, .h = 72 };
        c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
        c.text(r.x + 14, r.y + 10, scrap, 1.3, gold);
        c.print(r.x + 14, r.y + 32, 1, ink, "{d} GOLD   {d} PARTS   {d} KITS", .{ sb.kits[0].wallet.gold, sb.kits[0].wallet.parts, kits(sb.kits[0].wallet) });
        inventoryLine(c, sb, r.x + 14, r.y + 50, 1);
        c.text(r.x + w - 14 - Canvas.textWidth(hud.clock, 1), r.y + 12, hud.clock, 1, dim);
        colonyPanel(c, sb, .{ .x = r.x, .y = r.y + r.h + 8, .w = w, .h = 72 });
    }
    if (sb.space_battle.active) spaceHud(c, v, sb);
    if (!sb.arena.active and !hud.space_trial and !sb.hangar.space_mode) drawPlayerCoordinates(c, v, sb);
    if (menu.map_target != .none and !panels) {
        if (trackedTarget(menu.map_target, sb, sb.player.feet, 0)) |target| {
            const dx = target.position[0] - sb.player.feet[0];
            const dz = target.position[2] - sb.player.feet[2];
            const bearing = std.math.atan2(dx, dz);
            const octant: i32 = @intFromFloat(@floor((bearing + std.math.pi / 8.0) / (std.math.pi / 4.0)));
            const direction: usize = @intCast(@mod(octant, 8));
            const cardinal = [_][]const u8{ "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
            const label: []const u8 = switch (menu.map_target) {
                .none => "",
                .nest => "HIVE NEST",
                .cave => "CAVE",
                .wildkin => "WILDKIN",
                .wildlife => "CAPTURABLE WILDLIFE",
            };
            const w: f32 = @min(v.w - 40, 310);
            const box: Rect = .{ .x = v.x + (v.w - w) / 2, .y = v.y + 54, .w = w, .h = 30 };
            c.rect(box, .{ 0.02, 0.035, 0.05, 0.72 });
            c.frame(box, 1, alpha(gold, 0.7));
            c.print(box.x + 10, box.y + 10, 1.05, gold, "{s}  {d:.0}M  {s}", .{ label, @sqrt(dx * dx + dz * dz), cardinal[direction] });
        }
    }
    if (hud.music_available) drawMusicPlayer(c, hud, .{ .x = v.x + v.w - 266, .y = v.y + v.h - 90, .w = 250, .h = 72 }, true);
    if (panels) return;
    // The Starbowl's wave banner, top centre.
    if (sb.arena.active) {
        const ready = sb.arena.readyOpacity();
        if (ready > 0) {
            const pulse = 1.75 + 0.08 * @sin(menu.seconds * 7);
            const banner: Rect = .{ .x = v.x + v.w * 0.34, .y = v.y + 18, .w = v.w * 0.32, .h = 54 };
            c.rect(banner, alpha(.{ 0.02, 0.035, 0.05, 0.78 }, ready));
            c.frame(banner, 2, alpha(gold, ready));
            c.centered(v.x + v.w / 2, banner.y + 9, "GET READY", pulse, alpha(gold, ready));
            var countdown: [24]u8 = undefined;
            c.centered(v.x + v.w / 2, banner.y + 34, std.fmt.bufPrint(&countdown, "WAVE 1 IN {d:.1}", .{sb.arena.waiting}) catch "WAVE 1", 0.85, alpha(ink, ready));
            return;
        }
        var line: [64]u8 = undefined;
        const bots = sb.enemies.unitCount(@import("../game/Enemies.zig").arena_nest);
        const text = if (sb.arena.waiting > 0)
            std.fmt.bufPrint(&line, "STARBOWL  NEXT WAVE IN {d:.0}  BEST {d}", .{ @ceil(sb.arena.waiting), sb.progress.arena_best }) catch ""
        else
            std.fmt.bufPrint(&line, "STARBOWL  WAVE {d}  BOTS LEFT {d}", .{ sb.arena.wave, bots }) catch "";
        const w = Canvas.textWidth(text, 1.4) + 40;
        const banner: Rect = .{ .x = v.x + (v.w - w) / 2, .y = v.y + 18, .w = w, .h = 34 };
        c.rect(banner, .{ 0.02, 0.035, 0.05, 0.72 });
        c.frame(banner, 1, alpha(gold, 0.7));
        c.centered(v.x + v.w / 2, banner.y + 10, text, 1.4, gold);
    }
    // Interaction prompt and toast, bottom centre.
    prompt(c, v, hud.prompt, accent);
    if (hud.toast.len > 0) c.centered(v.x + v.w / 2, v.y + v.h - 150, hud.toast, 1.2, accent);
}

fn petStatus(c: *Canvas, v: Rect, sb: *const Sandbox, owner: usize) void {
    if (sb.pets.out[owner]) |pet| {
        const kit = &sb.kits[owner];
        const r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 170, .w = 250, .h = 22 };
        const lumen = Pets.info(pet.species).glow;
        c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
        c.text(r.x + 9, r.y + 4, Pets.info(pet.species).name, 0.9, .{ lumen[0], lumen[1], lumen[2], 1 });
        c.print(r.x + 72, r.y + 4, 0.85, ink, "LV {d}  HP {d:.0}/{d:.0}", .{ kit.petLevel(pet.species), pet.health, pet.max_health });
        bar(c, .{ .x = r.x + 9, .y = r.y + 17, .w = r.w - 18, .h = 2 }, pet.health / pet.max_health, .{ lumen[0], lumen[1], lumen[2], 1 });
    }
    if (sb.droid_companions.out[owner]) |droid| {
        const kit = &sb.kits[owner];
        const r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 143, .w = 250, .h = 22 };
        const cyan = [4]f32{ 0.34, 0.84, 1, 1 };
        c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
        c.text(r.x + 9, r.y + 4, "FIELD DROID", 0.9, cyan);
        c.print(r.x + 103, r.y + 4, 0.85, ink, "LV {d}  HP {d:.0}/{d:.0}", .{ kit.robotLevel(), droid.health, droid.max_health });
        bar(c, .{ .x = r.x + 9, .y = r.y + 17, .w = r.w - 18, .h = 2 }, droid.health / droid.max_health, cyan);
    }
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
    const motion = if (p.mode == .fly or p.flight_engaged) "SUPER FLIGHT" else @tagName(p.motion);
    c.text(r.x + 14 + Canvas.textWidth(profile.name(), 1.2) + 12, r.y + 12, pretty(&name_buffer, motion), 1, dim);
    c.text(r.x + 14, r.y + 32, "HEALTH", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 32, .w = 166, .h = 8 }, health.health / health.max, .{ 0.95, 0.32, 0.32, 1 });
    // An overshield shows as a bright band over the health bar.
    if (health.shield > 0) c.rect(.{ .x = r.x + 66, .y = r.y + 29, .w = 166 * @min(1, health.shield / 80), .h = 3 }, .{ 0.45, 0.9, 1, 1 });
    c.text(r.x + 14, r.y + 50, "FUEL", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 50, .w = 166, .h = 8 }, p.fuel / p.suit.fuel_max, accent);
    c.text(r.x + 14, r.y + 68, "STAMINA", 0.9, dim);
    bar(c, .{ .x = r.x + 66, .y = r.y + 68, .w = 166, .h = 8 }, p.stamina / 100, good);
    if (p.mode == .fly or p.flight_engaged) c.text(r.x + 14, r.y + 78, "TRAVERSAL OR V: LAND", 0.8, accent);
}

/// Energy and the class's three specials (key, name, cooldown), beside the vitals.
fn specials(c: *Canvas, v: Rect, sb: *const Sandbox, player: u8, profile: Profile, keys: [3][]const u8) void {
    const s = sb.specials.players[player];
    const w: f32 = @min(230, v.w - 290);
    if (w < 150) return;
    const r: Rect = .{ .x = v.x + 280, .y = v.y + v.h - 110, .w = w, .h = 90 };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    const lumen = Profile.accent_colors[profile.accent];
    c.text(r.x + 12, r.y + 10, if (profile.species != .human) "WILD" else if (profile.class == .synthetic) "POWERS" else "TECH", 0.9, lumen);
    for (Specials.loadout(profile).kit, 0..) |kind, i| {
        const about = Specials.info(kind);
        const y = r.y + 30 + @as(f32, @floatFromInt(i)) * 19;
        const ready = s.cooldowns[i] == 0;
        c.rect(.{ .x = r.x + 10, .y = y - 2, .w = 20, .h = 15 }, if (ready) alpha(lumen, 0.35) else .{ 1, 1, 1, 0.08 });
        c.centered(r.x + 20, y + 2, keys[i], 0.8, ink);
        c.text(r.x + 38, y + 2, about.label, 0.85, if (ready) ink else dim);
        // The cooldown drains away to the right.
        if (s.cooldowns[i] > 0) c.rect(.{ .x = r.x + 38, .y = y + 12, .w = (r.w - 50) * s.cooldowns[i] / about.cooldown, .h = 2 }, alpha(lumen, 0.7));
    }
}

/// The selected weapon and its charge, above the vitals (weapon tool only).
fn weaponLine(c: *Canvas, v: Rect, sb: *const Sandbox, player: u8) void {
    const r: Rect = .{ .x = v.x + 20, .y = v.y + v.h - 154, .w = 250, .h = 38 };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.6 });
    var buffer: [24]u8 = undefined;
    const arsenal = &sb.combat.arsenals[player];
    const name = if (arsenal.active) |w| (if (w == .blaster) "KI BLAST" else pretty(&buffer, @tagName(w))) else "NO WEAPON";
    c.text(r.x + 14, r.y + 9, name, 1, gold);
    if (arsenal.active) |w| {
        var tier_buffer: [8]u8 = undefined;
        const tier = std.fmt.bufPrint(&tier_buffer, "MK {d}", .{1 + arsenal.weapon_upgrades[@intFromEnum(w)]}) catch "MK I";
        c.text(r.x + 100, r.y + 9, tier, 0.75, alpha(gold, 0.8));
    }
    bar(c, .{ .x = r.x + 160, .y = r.y + 10, .w = 76, .h = 6 }, arsenal.charge(), gold);
    if (arsenal.stance().move) |move| c.text(r.x + 14, r.y + 24, move.label(), 0.78, Profile.accent_colors[sb.profileOf(player).accent]);
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

/// A guest's split view: vitals, the aimed prompt, and a compact shop panel while trading or
/// fabricating from that guest's own Kit.
fn drawGuest(c: *Canvas, sb: *const Sandbox, guest: Hud.Guest) void {
    const g = &sb.guests[guest.index];
    const v = guest.view;
    const tint = Profile.accent_colors[g.profile.accent];
    if (!sb.arena.active and !sb.hangar.space_mode) drawPlayerCoordinates(c, v, sb);
    vitals(c, v, g.player, g.profile, sb.combat.vitals[guest.index + 1]);
    petStatus(c, v, sb, guest.index + 1);
    specials(c, v, sb, guest.index + 1, g.profile, .{ "UP", "DN", "R3+UP" });
    if (sb.kits[guest.index + 1].weapons != 0) weaponLine(c, v, sb, guest.index + 1);
    if (g.shop) |shop| return drawGuestFabricator(c, sb, shop, guest.index + 1, v, tint);
    const stall = g.trading orelse return prompt(c, v, guest.prompt, tint);
    const w = @min(v.w - 40, 460);
    const h = 84 + @as(f32, Sandbox.trade_rows) * 26;
    const r: Rect = .{ .x = v.x + v.w - w - 20, .y = v.y + 20, .w = w, .h = h };
    c.rect(r, panel_fill);
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 2 }, tint);
    var title: [48]u8 = undefined;
    var upper: [48]u8 = undefined;
    c.text(r.x + 14, r.y + 12, pretty(&upper, std.fmt.bufPrint(&title, "{s}'S STALL", .{keeperName(sb, stall)}) catch ""), 1.2, tint);
    const purse = sb.kits[guest.index + 1].wallet;
    c.print(r.x + w - 200, r.y + 14, 1, gold, "{d} SCRAP  {d} PARTS", .{ purse.scrap, purse.parts });
    var y = r.y + 38;
    for (0..Sandbox.trade_rows) |i| {
        const row: Rect = .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = 22 };
        rowBack(c, row, g.trade_row == i);
        var line: Sandbox.TradeLine = .{};
        sb.tradeRow(guest.index + 1, stall, @intCast(i), false, &line);
        var shown: [96]u8 = undefined;
        c.text(row.x + 8, row.y + 7, pretty(&shown, std.mem.trimStart(u8, line.slice(), " ")), 0.9, if (g.trade_row == i) tint else ink);
        y += 26;
    }
    c.text(r.x + 14, r.y + r.h - 22, "D-PAD CHOOSE  X TRADE  B CLOSE", 0.9, dim);
}

fn drawPlayerCoordinates(c: *Canvas, v: Rect, sb: *const Sandbox) void {
    var count: usize = 1;
    for (sb.guests) |g| if (g.active) {
        count += 1;
    };
    const row_h: f32 = 16;
    const w = @min(v.w - 24, 236);
    const r: Rect = .{ .x = v.x + 12, .y = v.y + 20, .w = w, .h = 25 + row_h * @as(f32, @floatFromInt(count)) };
    c.rect(r, .{ 0.02, 0.035, 0.05, 0.68 });
    c.frame(r, 1, alpha(accent, 0.5));
    c.text(r.x + 8, r.y + 6, "PLAYER COORDINATES", 0.72, accent);
    var y = r.y + 22;
    for (0..Sandbox.max_players) |owner| {
        if (owner > 0 and !sb.guests[owner - 1].active) continue;
        const position = if (owner == 0) blk: {
            if (sb.hangar.piloting) {
                const p = sb.hangar.fighter.?.body.pos;
                break :blk [3]f32{ p.x, p.y, p.z };
            }
            break :blk sb.player.feet;
        } else sb.guests[owner - 1].player.feet;
        const color = if (owner == 0) ink else Profile.accent_colors[sb.guests[owner - 1].profile.accent];
        const key = ChunkKey.fromPosition(position[0], position[2]);
        if (Region.moon.contains(key.x, key.z)) {
            const dx = position[0] - Region.moon.arrival[0];
            const dz = position[2] - Region.moon.arrival[1];
            c.print(r.x + 8, y, 0.78, color, "P{d}  LUNA  {d:.0}m  {d:.0}m", .{ owner + 1, dx, dz });
        } else {
            const coord = CityGeography.atWorld(position[0], position[2]);
            const lat_dir: []const u8 = if (coord.latitude >= 0) "N" else "S";
            const lon_dir: []const u8 = if (coord.longitude >= 0) "E" else "W";
            c.print(r.x + 8, y, 0.78, color, "P{d}  {d:.4} {s}  {d:.4} {s}", .{ owner + 1, @abs(coord.latitude), lat_dir, @abs(coord.longitude), lon_dir });
        }
        y += row_h;
    }
}

fn drawGuestFabricator(c: *Canvas, sb: *const Sandbox, shop: Sandbox.Shop, owner: usize, v: Rect, tint: Color) void {
    var indices: [Fabricator.recipes.len]u8 = undefined;
    const rows = Fabricator.onTab(@enumFromInt(shop.tab), &indices);
    const kit = &sb.kits[owner];
    const w = @min(v.w - 20, 320);
    const h = @min(v.h - 20, 220);
    const r: Rect = .{ .x = v.x + v.w - w - 10, .y = v.y + 10, .w = w, .h = h };
    c.rect(r, panel_fill);
    c.rect(.{ .x = r.x, .y = r.y, .w = r.w, .h = 2 }, tint);
    var title: [32]u8 = undefined;
    c.text(r.x + 10, r.y + 10, std.fmt.bufPrint(&title, "P{d} FABRICATOR", .{owner + 1}) catch "FABRICATOR", 0.95, tint);
    c.print(r.x + 10, r.y + 28, 0.7, dim, "SCRAP {d}  PARTS {d}", .{ kit.wallet.scrap, kit.wallet.parts });
    var tab_name: [20]u8 = undefined;
    c.print(r.x + 10, r.y + 45, 0.72, ink, "TAB {d}/{d}  {s}", .{ shop.tab + 1, Fabricator.tab_count, pretty(&tab_name, @tagName(@as(Fabricator.Tab, @enumFromInt(shop.tab)))) });

    const selected_row: usize = shop.row;
    const first = if (selected_row > 2) @min(selected_row - 2, rows.len -| 4) else 0;
    const end = @min(rows.len, first + 4);
    var y = r.y + 63;
    for (rows[first..end], first..) |index, row_index| {
        const selected = row_index == shop.row;
        const recipe = Fabricator.recipes[index];
        if (selected) c.rect(.{ .x = r.x + 6, .y = y - 3, .w = r.w - 12, .h = 19 }, alpha(tint, 0.14));
        var name: [28]u8 = undefined;
        c.text(r.x + 10, y, Fabricator.name(recipe.output, &name), 0.72, if (selected) tint else ink);
        if (selected) if (Fabricator.status(&sb.progress, kit, recipe.output)) |state|
            c.text(r.x + r.w - Canvas.textWidth(state, 0.62) - 10, y, state, 0.62, good)
        else
            c.text(r.x + r.w - Canvas.textWidth("SELECTED", 0.62) - 10, y, "SELECTED", 0.62, dim);
        y += 21;
    }
    const selected_index = rows[shop.row];
    const cost = Fabricator.recipes[selected_index].cost;
    c.print(r.x + 10, r.y + r.h - 43, 0.66, gold, "COST  L{d} R{d} A{d} S{d} P{d}", .{ cost.lumen, cost.rotor, cost.alloy, cost.scrap, cost.parts });
    c.text(r.x + 10, r.y + r.h - 27, "UP/DN SELECT  LEFT/RIGHT TAB  X BUILD  B CLOSE", 0.62, dim);
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
    .{ .title = "CHARACTER MODEL", .first = .body_style },
    .{ .title = "BODY", .first = .height },
    .{ .title = "FACE", .first = .face_style },
    .{ .title = "HAIR", .first = .hair_style },
    .{ .title = "GEAR", .first = .outfit },
    .{ .title = "ARMOR COLOR STUDIO  /  RGB", .first = .armor_metal_r },
    .{ .title = "BOOTS", .first = .boot_style },
    // Cel styles exist only as mod content, so this row cycles "default" plus installed mods.
    .{ .title = "RENDER STYLE", .first = .cel_style },
};

pub const creator_tab_starts = [_]Profile.Field{ .name, .face_style, .outfit, .armor_metal_r, .cel_style };
pub const creator_tab_ends = [_]usize{ 10, 19, 27, 36, 37 };
const creator_tab_labels = [_][]const u8{ "BASICS", "FACE/HAIR", "GEAR", "ARMOR RGB", "STYLE" };

fn swatch(field: Profile.Field, p: Profile) ?Color {
    return switch (field) {
        .skin => Profile.skin_tones[p.skin],
        .hair_color => Profile.hair_colors[p.hair_color],
        .eye_color => if (p.eye_color == 0 or p.class == .synthetic) null else Profile.eye_colors[p.eye_color - 1],
        .hair_highlight => if (p.hair_highlight == 0) null else Profile.hair_colors[p.hair_highlight - 1],
        .outfit => Profile.outfit_colors[p.outfit],
        .accent => Profile.accent_colors[p.accent],
        .gemstone => switch (p.gemstone) {
            .lumen => .{ 0.30, 0.95, 1.00, 1 },
            .ruby => .{ 1.00, 0.18, 0.22, 1 },
            .sapphire => .{ 0.20, 0.38, 1.00, 1 },
            .emerald => .{ 0.20, 0.95, 0.46, 1 },
            .amethyst => .{ 0.72, 0.34, 1.00, 1 },
            .citrine => .{ 1.00, 0.70, 0.18, 1 },
        },
        .coat => Profile.coat_colors[p.coat],
        .marking => Profile.coat_colors[p.marking],
        .armor_metal_r, .armor_metal_g, .armor_metal_b => armorSwatch(p, 0),
        .armor_secondary_r, .armor_secondary_g, .armor_secondary_b => armorSwatch(p, 1),
        .armor_trim_r, .armor_trim_g, .armor_trim_b => armorSwatch(p, 2),
        else => null,
    };
}

fn armorSwatch(p: Profile, slot: u8) Color {
    const Armor = @import("../character/armor.zig");
    const def = Armor.find(&Armor.builtin_sets, @tagName(p.armor)) orelse &Armor.builtin_sets[1];
    const custom = switch (slot) {
        0 => p.armor_metal_color,
        1 => p.armor_secondary_color,
        else => p.armor_trim_color,
    };
    const rgb = custom orelse switch (slot) {
        0 => .{ def.metal.r, def.metal.g, def.metal.b },
        1 => .{ def.secondary.r, def.secondary.g, def.secondary.b },
        else => .{ def.trim.r, def.trim.g, def.trim.b },
    };
    return .{ rgb[0], rgb[1], rgb[2], 1 };
}

/// Height of a section title row in the creator.
const creator_header: f32 = 16;

fn drawCreator(c: *Canvas, sb: *const Sandbox, v: Rect) void {
    const cr = &sb.creator;
    const fields = enum_compat.fields(Profile.Field);
    const clothing_count = enum_compat.fields(Profile.Clothing).len;
    const all: u8 = @intCast((@as(u16, 1) << clothing_count) - 1);
    const locked = clothing_count - @popCount(cr.owned & all);
    // Title and tabs above, below: an optional shop notice, then actions and hints.
    const top: f32 = 66;
    const bottom: f32 = 50 + @as(f32, if (locked > 0) 16 else 0);
    const tab = creatorTab(cr.field);
    const first = @intFromEnum(creator_tab_starts[tab]);
    const last = creator_tab_ends[tab];
    const field_count = last - first;
    var visible_headers: usize = 0;
    for (sections) |s| {
        const at: usize = @intFromEnum(s.first);
        if (at >= first and at < last) visible_headers += 1;
    }
    const avail = v.h - 16 - top - bottom;
    const rows_height = @as(f32, @floatFromInt(field_count));
    const header_height = @as(f32, @floatFromInt(visible_headers)) * creator_header;
    const step = @min(row_height, @max(14, (avail - header_height) / rows_height));
    const h = top + rows_height * step + header_height + bottom;
    const r: Rect = .{ .x = v.x + 24, .y = v.y + @max(8, (v.h - h) / 2), .w = 460, .h = h };
    panel(c, r, if (cr.confirmed) "CUSTOMIZE RANGER" else "CREATE YOUR RANGER");
    const tab_gap: f32 = 3;
    const tab_width = (r.w - 20 - tab_gap * @as(f32, @floatFromInt(creator_tab_labels.len - 1))) / @as(f32, @floatFromInt(creator_tab_labels.len));
    for (creator_tab_labels, 0..) |label, i| {
        const tab_rect: Rect = .{ .x = r.x + 10 + @as(f32, @floatFromInt(i)) * (tab_width + tab_gap), .y = r.y + 34, .w = tab_width, .h = 24 };
        button(c, tab_rect, label, hitId(.creator_tab, i), tab == i);
    }
    var y = r.y + top;
    inline for (fields, 0..) |f, i| {
        const field: Profile.Field = @enumFromInt(f.value);
        if (i >= first and i < last) {
            for (sections) |s| if (s.first == field) {
                c.text(r.x + 18, y + 4, s.title, 0.9, alpha(accent, 0.8));
                c.rect(.{ .x = r.x + 18 + Canvas.textWidth(s.title, 0.9) + 8, .y = y + 8, .w = r.w - 60 - Canvas.textWidth(s.title, 0.9), .h = 1 }, alpha(accent, 0.25));
                y += creator_header;
            };
            const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = step - 2 };
            const selected = cr.field == field;
            rowBack(c, row, selected);
            c.hit(row, hitId(.creator_field, i));
            var label_buffer: [24]u8 = undefined;
            const ty = row.y + (step - 10) / 2 - 1;
            c.text(row.x + 14, ty, pretty(&label_buffer, f.name), 1, if (selected) accent else dim);
            var buffer: [40]u8 = undefined;
            var value = cr.value(field, &buffer);
            var pretty_buffer: [40]u8 = undefined;
            if (field != .name) value = pretty(&pretty_buffer, value);
            const vx = row.x + 196;
            if (field != .name) {
                button(c, .{ .x = vx, .y = row.y + 1, .w = 20, .h = step - 4 }, "<", hitId(.creator_left, i), false);
                button(c, .{ .x = row.x + row.w - 28, .y = row.y + 1, .w = 20, .h = step - 4 }, ">", hitId(.creator_right, i), false);
            }
            var tx = vx + 30;
            if (swatch(field, cr.draft)) |color| {
                c.rect(.{ .x = tx, .y = row.y + (step - 14) / 2 - 1, .w = 26, .h = 14 }, color);
                c.frame(.{ .x = tx, .y = row.y + (step - 14) / 2 - 1, .w = 26, .h = 14 }, 1, .{ 1, 1, 1, 0.4 });
                tx += 34;
            }
            c.text(tx, ty, value, 1, ink);
            y += step;
        }
    }
    if (locked > 0) c.print(r.x + 18, y + 4, 0.9, gold, "{d} ARMOR SUITS LOCKED: BUY THEM FROM MARO, SOUTH MARKET", .{locked});
    // The hint shares a line with DONE; the shop notice above has its own.
    const done: Rect = .{ .x = r.x + r.w - 140, .y = r.y + r.h - 38, .w = 120, .h = 28 };
    button(c, done, "DONE", hitId(.creator_done, 0), false);
    const library: Rect = .{ .x = r.x + 18, .y = done.y, .w = 150, .h = 28 };
    button(c, library, "IMPORTED PARTS", hitId(.creator_imported, 0), false);
    const forge: Rect = .{ .x = library.x + library.w + 8, .y = done.y, .w = 126, .h = 28 };
    button(c, forge, "HIVE FORGE", hitId(.enemy_forge, 0), false);
}

fn creatorTab(field: Profile.Field) usize {
    const index = @intFromEnum(field);
    for (creator_tab_ends, 0..) |end, i| if (index < end) return i;
    return creator_tab_ends.len - 1;
}

fn drawEnemyDesign(c: *Canvas, cr: *const Creator, v: Rect) void {
    const w = @min(@as(f32, 620), v.w - 32);
    const h = @min(@as(f32, 520), v.h - 24);
    const r: Rect = .{ .x = v.x + (v.w - w) / 2, .y = v.y + (v.h - h) / 2, .w = w, .h = h };
    panel(c, r, "HIVE FRAME FORGE");
    c.text(r.x + 22, r.y + 38, "SCALARI TITAN  /  MODULAR ENEMY ASSEMBLY", 0.92, alpha(accent, 0.85));
    c.text(r.x + 22, r.y + 60, "PART MODULES: SELECT A ROW, THEN CYCLE ITS VARIANTS", 0.8, dim);
    const palette_y = r.y + 82;
    c.text(r.x + 22, palette_y + 8, "PALETTE", 0.88, dim);
    button(c, .{ .x = r.x + 115, .y = palette_y, .w = 24, .h = 24 }, "<", hitId(.enemy_palette_left, 0), false);
    c.rect(.{ .x = r.x + 150, .y = palette_y + 3, .w = 30, .h = 18 }, EnemyDesign.colors[@intFromEnum(cr.enemy_design.palette)].armor);
    c.rect(.{ .x = r.x + 184, .y = palette_y + 3, .w = 30, .h = 18 }, EnemyDesign.colors[@intFromEnum(cr.enemy_design.palette)].accent);
    c.rect(.{ .x = r.x + 218, .y = palette_y + 3, .w = 30, .h = 18 }, EnemyDesign.colors[@intFromEnum(cr.enemy_design.palette)].glow);
    c.text(r.x + 262, palette_y + 8, EnemyDesign.palette_names[@intFromEnum(cr.enemy_design.palette)], 0.9, ink);
    button(c, .{ .x = r.x + 402, .y = palette_y, .w = 24, .h = 24 }, ">", hitId(.enemy_palette_right, 0), false);
    c.text(r.x + 22, palette_y + 34, "7 FINISHES INCLUDE SILVER / MOSS STEEL / AMBER CARAPACE", 0.72, dim);
    const style_y = palette_y + 51;
    c.text(r.x + 22, style_y + 8, "LAYER STYLE", 0.84, dim);
    button(c, .{ .x = r.x + 115, .y = style_y, .w = 24, .h = 24 }, "<", hitId(.enemy_style_left, 0), false);
    c.text(r.x + 150, style_y + 8, EnemyDesign.layer_style_names[@intFromEnum(cr.enemy_design.layer_style)], 0.88, ink);
    button(c, .{ .x = r.x + 402, .y = style_y, .w = 24, .h = 24 }, ">", hitId(.enemy_style_right, 0), false);
    const labels = [_][]const u8{ "FRAME", "HEAD", "SHOULDERS", "ARMS", "LEGS", "BACK UNIT", "WEAPON" };
    var y = palette_y + 85;
    for (labels, 0..) |label, i| {
        const part: EnemyDesign.Part = @enumFromInt(i);
        const row: Rect = .{ .x = r.x + 18, .y = y, .w = r.w - 36, .h = 37 };
        const selected = cr.enemy_part == part;
        rowBack(c, row, selected);
        c.hit(row, hitId(.enemy_part, i));
        c.text(row.x + 12, row.y + 13, label, 0.86, if (selected) accent else dim);
        const info = EnemyDesign.module(part, cr.enemy_design.value(part));
        c.text(row.x + 150, row.y + 13, info.name, 0.9, ink);
        c.text(row.x + 330, row.y + 13, info.description, 0.75, dim);
        button(c, .{ .x = row.x + row.w - 58, .y = row.y + 5, .w = 22, .h = 26 }, "<", hitId(.enemy_left, i), false);
        button(c, .{ .x = row.x + row.w - 30, .y = row.y + 5, .w = 22, .h = 26 }, ">", hitId(.enemy_right, i), false);
        y += 40;
    }
    c.text(r.x + 22, r.y + r.h - 35, "P: PALETTE  /  L: LAYER STYLE  /  SIEGE FRAMES JOIN PLAZA RAIDS", 0.78, alpha(accent, 0.85));
    button(c, .{ .x = r.x + r.w - 134, .y = r.y + r.h - 43, .w = 112, .h = 28 }, "BACK", hitId(.enemy_forge, 0), false);
}

fn drawImportedComponents(c: *Canvas, cr: *const Creator, v: Rect) void {
    const doc = cr.imported_doc orelse return;
    const w = @min(@as(f32, 720), v.w - 32);
    const h = @min(@as(f32, 620), v.h - 24);
    // Keep the live character in the exposed left strip. The imported model is rendered by the
    // game scene behind this panel, so centering the editor used to cover the preview entirely.
    const r: Rect = .{ .x = v.x + v.w - w - 12, .y = v.y + (v.h - h) / 2, .w = w, .h = h };
    panel(c, r, "IMPORTED CHARACTER LIBRARY");
    const rig_label = if (cr.imported_rig_status_len > 0) cr.imported_rig_status[0..cr.imported_rig_status_len] else "NO EXTERNAL RIG  |  BUNDLED CAPTAIN COMPONENTS";
    c.print(r.x + 18, r.y + 36, 0.76, dim, "LIVE PREVIEW LEFT  |  {d} COMPONENTS  |  {s}", .{ doc.parts.len, rig_label });
    button(c, .{ .x = r.x + r.w - 150, .y = r.y + 26, .w = 132, .h = 28 }, "IMPORT GLB", hitId(.imported_import_glb, 0), false);
    button(c, .{ .x = r.x + r.w - 300, .y = r.y + 26, .w = 142, .h = 28 }, "VERTEX TOOLS", hitId(.mesh_tool, @intFromEnum(@import("../game/MeshTools.zig").Control.open)), false);

    const filter_names = [_][]const u8{ "ALL", "ARMOR", "SKIN", "EYES", "ENERGY", "NEUTRAL" };
    const tab_w: f32 = @min(112, (r.w - 40) / @as(f32, @floatFromInt(filter_names.len)));
    for (filter_names, 0..) |name, i| {
        const tab: Rect = .{ .x = r.x + 18 + @as(f32, @floatFromInt(i)) * (tab_w + 4), .y = r.y + 56, .w = tab_w, .h = 26 };
        button(c, tab, name, hitId(.imported_filter, i), cr.imported_filter == i);
    }

    // The uploaded meshes: step through them (choosing one puts it on the character) or delete.
    const lib = &cr.imports;
    const mesh_row: Rect = .{ .x = r.x + 18, .y = r.y + 90, .w = r.w - 36, .h = 28 };
    c.rect(mesh_row, alpha(panel_fill, 0.6));
    c.text(mesh_row.x + 8, mesh_row.y + 10, "MESH", 0.8, alpha(accent, 0.8));
    button(c, .{ .x = mesh_row.x + 52, .y = mesh_row.y + 2, .w = 30, .h = 24 }, "<", hitId(.imported_library_prev, 0), false);
    button(c, .{ .x = mesh_row.x + 86, .y = mesh_row.y + 2, .w = 30, .h = 24 }, ">", hitId(.imported_library_next, 0), false);
    if (lib.activeName()) |name| {
        var upper: [40]u8 = undefined;
        c.print(mesh_row.x + 126, mesh_row.y + 10, 0.82, gold, "{s}  ({d} OF {d})", .{ pretty(&upper, name), lib.active.? + 1, lib.count });
        button(c, .{ .x = mesh_row.x + mesh_row.w - 150, .y = mesh_row.y + 2, .w = 146, .h = 24 }, if (cr.import_delete_armed) "CONFIRM DELETE" else "DELETE MESH", hitId(.imported_library_delete, 0), cr.import_delete_armed);
    } else c.text(mesh_row.x + 126, mesh_row.y + 10, if (lib.count == 0) "NO UPLOADS YET: IMPORT GLB ADDS ONE" else "NONE IN USE: CHOOSE ONE WITH < >", 0.8, dim);
    if (cr.import_message_len > 0) c.text(r.x + 18, r.y + h - 70, cr.import_message[0..cr.import_message_len], 0.74, if (cr.import_message_ok) good else bad);

    const list = Rect{ .x = r.x + 18, .y = r.y + 126, .w = @min(@as(f32, 380), (r.w - 60) * 0.45), .h = h - 206 };
    c.rect(list, alpha(panel_fill, 0.5));
    const row_step: f32 = 25;
    const rows: usize = @min(18, @as(usize, @intFromFloat(@max(list.h / row_step, 1))));
    var selected_rank: usize = 0;
    for (doc.parts[0..@min(cr.imported_selected, doc.parts.len)]) |part| if (cr.matchesFilter(part.surface)) {
        selected_rank += 1;
    };
    const first_rank = selected_rank -| (rows / 2);
    var rank: usize = 0;
    var row: usize = 0;
    for (doc.parts, 0..) |part, index| {
        if (!cr.matchesFilter(part.surface)) continue;
        if (rank >= first_rank and row < rows) {
            const item: Rect = .{ .x = list.x + 4, .y = list.y + 4 + @as(f32, @floatFromInt(row)) * row_step, .w = list.w - 8, .h = row_step - 2 };
            rowBack(c, item, index == cr.imported_selected);
            c.hit(item, hitId(.imported_part, index & 0xff));
            var label: [48]u8 = undefined;
            const name = pretty(&label, part.label);
            c.text(item.x + 9, item.y + 7, name, 0.82, if (!part.enabled) bad else if (index == cr.imported_selected) accent else ink);
            c.text(item.x + item.w - 76, item.y + 7, @tagName(part.surface), 0.72, dim);
            row += 1;
        }
        rank += 1;
    }
    const selected = if (cr.imported_selected < doc.parts.len) &doc.parts[cr.imported_selected] else null;
    const info_x = list.x + list.w + 24;
    c.text(info_x, list.y + 4, "PALETTE", 0.9, alpha(accent, 0.8));
    const palette_name = @tagName(cr.imported_palette);
    const palette_color: Color = switch (cr.imported_palette) {
        .skin => .{ doc.skin_color[0], doc.skin_color[1], doc.skin_color[2], 1 },
        .eyes => .{ doc.eye_color[0], doc.eye_color[1], doc.eye_color[2], 1 },
        .armor => .{ doc.armor_color[0], doc.armor_color[1], doc.armor_color[2], 1 },
        .energy => .{ doc.energy_color[0], doc.energy_color[1], doc.energy_color[2], 1 },
    };
    const palette_row: Rect = .{ .x = info_x, .y = list.y + 22, .w = 350, .h = 30 };
    button(c, .{ .x = palette_row.x, .y = palette_row.y, .w = 34, .h = 26 }, "<", hitId(.imported_palette_left, 0), false);
    button(c, .{ .x = palette_row.x + 41, .y = palette_row.y, .w = 34, .h = 26 }, ">", hitId(.imported_palette_right, 0), false);
    c.rect(.{ .x = palette_row.x + 86, .y = palette_row.y + 4, .w = 24, .h = 18 }, palette_color);
    var pretty_palette: [20]u8 = undefined;
    var palette_value: [40]u8 = undefined;
    const palette_text = std.fmt.bufPrint(&palette_value, "{s}  {d}", .{ pretty(&pretty_palette, palette_name), cr.imported_palette_variant + 1 }) catch "";
    c.text(palette_row.x + 120, palette_row.y + 8, palette_text, 0.9, ink);
    const channel_names = [_][]const u8{ "R", "G", "B" };
    for (0..3) |channel| {
        const channel_y = palette_row.y + 42 + @as(f32, @floatFromInt(channel)) * 27;
        c.text(info_x + 2, channel_y + 8, channel_names[channel], 0.85, dim);
        button(c, .{ .x = info_x + 26, .y = channel_y, .w = 34, .h = 24 }, "-", hitId(.imported_color, channel * 2), false);
        const channel_value = switch (channel) {
            0 => palette_color[0],
            1 => palette_color[1],
            else => palette_color[2],
        };
        c.print(info_x + 72, channel_y + 8, 0.8, ink, "{d:.2}", .{channel_value});
        button(c, .{ .x = info_x + 126, .y = channel_y, .w = 34, .h = 24 }, "+", hitId(.imported_color, channel * 2 + 1), false);
    }

    if (selected) |part| {
        c.text(info_x, list.y + 142, "SELECTED COMPONENT", 0.9, alpha(accent, 0.8));
        var label_buffer: [80]u8 = undefined;
        c.text(info_x, list.y + 168, pretty(&label_buffer, part.label), 1.05, ink);
        c.print(info_x, list.y + 194, 0.82, dim, "SOURCE ID {d}  |  {d} VERTICES", .{ part.id, part.vertex_count });
        c.text(info_x, list.y + 224, "SURFACE ROLE", 0.9, alpha(accent, 0.8));
        const role_y = list.y + 244;
        button(c, .{ .x = info_x, .y = role_y, .w = 36, .h = 28 }, "<", hitId(.imported_surface_left, 0), false);
        button(c, .{ .x = info_x + 44, .y = role_y, .w = 36, .h = 28 }, ">", hitId(.imported_surface_right, 0), false);
        var role: [20]u8 = undefined;
        c.text(info_x + 96, role_y + 9, pretty(&role, @tagName(part.surface)), 0.9, gold);
        const paint: Rect = .{ .x = info_x, .y = role_y + 48, .w = 212, .h = 30 };
        button(c, paint, if (part.color == null) "PAINT FROM PALETTE" else "CLEAR PART PAINT", hitId(.imported_paint, 0), false);
        if (part.color) |color| c.rect(.{ .x = paint.x + paint.w + 10, .y = paint.y + 6, .w = 24, .h = 18 }, .{ color[0], color[1], color[2], 1 });
        const visible: Rect = .{ .x = info_x, .y = paint.y + 38, .w = 160, .h = 28 };
        button(c, visible, if (part.enabled) "HIDE COMPONENT" else "RESTORE PART", hitId(.imported_toggle, 0), false);
    }
    const hint = if (cr.imported_status == .saved) "SAVED  |  LEFT/RIGHT SURFACE  P PALETTE  C PAINT  H HIDE  Z UNDO / SHIFT+Z REDO" else if (cr.imported_status == .unsaved) "UNSAVED  |  LEFT/RIGHT SURFACE  P PALETTE  C PAINT  H HIDE  Z UNDO / SHIFT+Z REDO" else "UP/DOWN SELECT  LEFT/RIGHT SURFACE  P PALETTE  C PAINT  H HIDE  Z UNDO / SHIFT+Z REDO";
    c.text(r.x + 18, r.y + h - 48, hint, 0.72, if (cr.imported_status == .unsaved) gold else dim);
    c.print(info_x, r.y + h - 75, 0.72, dim, "HISTORY {d}/{d}", .{ cr.imported_history.cursor, cr.imported_history.len });
    button(c, .{ .x = r.x + r.w - 414, .y = r.y + h - 42, .w = 68, .h = 28 }, "UNDO", hitId(.imported_undo, 0), cr.imported_history.cursor > 0);
    button(c, .{ .x = r.x + r.w - 338, .y = r.y + h - 42, .w = 68, .h = 28 }, "REDO", hitId(.imported_redo, 0), cr.imported_history.cursor < cr.imported_history.len);
    button(c, .{ .x = r.x + r.w - 258, .y = r.y + h - 42, .w = 88, .h = 28 }, "BACK", hitId(.imported_back, 0), false);
    button(c, .{ .x = r.x + r.w - 158, .y = r.y + h - 42, .w = 140, .h = 28 }, "SAVE LIBRARY", hitId(.imported_save, 0), false);
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
    c.print(x, y, 1.1, gold, "{d} SCRAP", .{sb.kits[0].wallet.scrap});
    c.print(x + 140, y, 1.1, ink, "{d} PARTS", .{sb.kits[0].wallet.parts});
    c.print(x + 280, y, 1.1, gold, "{d} GOLD", .{sb.kits[0].wallet.gold});
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
            c.text(row.x + 14, row.y + 10, "SELL SALVAGED PARTS", 1.1, if (sb.kits[0].wallet.parts == 0) dim else ink);
            c.print(row.x + row.w - 260, row.y + 10, 1, if (sb.kits[0].wallet.parts == 0) dim else gold, "{d} X {d} = +{d} SCRAP", .{ sb.kits[0].wallet.parts, price, sb.kits[0].wallet.parts * price });
        } else {
            const ware: Market.Ware = @enumFromInt(i - 1);
            const stock = sb.market.stalls[stall].stock[i - 1];
            const price = sb.market.price(stall, ware);
            var name_buffer: [32]u8 = undefined;
            var buffer: [40]u8 = undefined;
            const name = std.fmt.bufPrint(&buffer, "{s} KIT", .{ware_names[i - 1]}) catch "";
            c.text(row.x + 14, row.y + 10, pretty(&name_buffer, name), 1.1, if (stock == 0) dim else ink);
            c.print(row.x + row.w - 260, row.y + 10, 1, if (stock == 0) dim else if (price > sb.kits[0].wallet.scrap) bad else gold, "{d} SCRAP", .{price});
            if (stock == 0) c.text(row.x + row.w - 150, row.y + 10, "SOLD OUT", 1, bad) else c.print(row.x + row.w - 150, row.y + 10, 1, dim, "STOCK {d}", .{stock});
            c.print(row.x + row.w - 64, row.y + 10, 1, dim, "HAVE {d}", .{sb.kits[0].wallet.kits[i - 1]});
        }
        y += 34;
    }
    const about = if (sb.trade_row == 0) "Harvest young trees for parts; every stall buys them." else ware_about[sb.trade_row - 1];
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
    if (cost.gold > 0) return std.fmt.bufPrint(buffer, "{d} GOLD + {d} SCRAP + {d} PARTS", .{ cost.gold, cost.scrap, cost.parts }) catch "";
    if (cost.parts == 0) return std.fmt.bufPrint(buffer, "{d} SCRAP", .{cost.scrap}) catch "";
    return std.fmt.bufPrint(buffer, "{d} SCRAP + {d} PARTS", .{ cost.scrap, cost.parts }) catch "";
}

fn affordable(w: Market.Wallet, cost: Progress.Cost) bool {
    return w.scrap >= cost.scrap and w.parts >= cost.parts and w.gold >= cost.gold;
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
        pips(c, row.x + 230, row.y + 9, sb.kits[0].level(u));
        var buffer: [40]u8 = undefined;
        if (sb.kits[0].level(u) >= Progress.max_level) {
            c.text(row.x + row.w - 200, row.y + 10, "FULLY TUNED", 1, good);
        } else {
            const cost = sb.kits[0].cost(u);
            c.text(row.x + row.w - 200, row.y + 10, costText(&buffer, cost), 1, if (affordable(sb.kits[0].wallet, cost)) gold else bad);
        }
        y += 34;
    }
    const s = sb.kits[0].suit();
    c.print(r.x + 18, y + 10, 1, dim, "FUEL {d:.0}  BURN {d:.0}%  SPRINT {d:.1} M/S  GRAPPLE {d:.0} M  PARTS/RELIC {d}", .{ s.fuel_max, s.burn * 100, s.sprint, s.grapple_range, sb.kits[0].partsPerSalvage() });
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
    inline for (enum_compat.fields(Profile.Clothing), 0..) |f, i| {
        const clothing: Profile.Clothing = @enumFromInt(f.value);
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        rowBack(c, row, selected == i);
        c.hit(row, hitId(.shop_row, i));
        var name_buffer: [24]u8 = undefined;
        c.text(row.x + 14, row.y + 10, pretty(&name_buffer, f.name), 1.1, if (selected == i) accent else ink);
        var buffer: [40]u8 = undefined;
        if (sb.profile.clothing == clothing) {
            c.text(row.x + row.w - 200, row.y + 10, "WEARING", 1, good);
        } else if (sb.kits[0].owns(clothing)) {
            c.text(row.x + row.w - 200, row.y + 10, "OWNED", 1, ink);
        } else {
            const cost = Progress.suitPrice(clothing);
            c.text(row.x + row.w - 200, row.y + 10, costText(&buffer, cost), 1, if (affordable(sb.kits[0].wallet, cost)) gold else bad);
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
        const text = std.fmt.bufPrint(&buffer, "{d}", .{sb.kits[0].count(kind)}) catch "";
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
    var y = r.y + 76;
    for (rows, 0..) |index, i| {
        const recipe = Fabricator.recipes[index];
        const row: Rect = .{ .x = r.x + 10, .y = y, .w = r.w - 20, .h = 30 };
        rowBack(c, row, shop.row == i);
        c.hit(row, hitId(.shop_row, i));
        var buffer: [24]u8 = undefined;
        c.text(row.x + 14, row.y + 10, Fabricator.name(recipe.output, &buffer), 1.1, if (shop.row == i) accent else ink);
        if (recipe.output == .kestrel_upgrade) {
            const upgrade = recipe.output.kestrel_upgrade;
            var level: [24]u8 = undefined;
            const label = std.fmt.bufPrint(&level, "LV {d}/{d}", .{ sb.progress.kestrelLevel(upgrade), Progress.max_level }) catch "";
            c.text(row.x + row.w - 340, row.y + 10, label, 0.9, dim);
        }
        if (recipe.output == .space_frame and shop.tab == @intFromEnum(Fabricator.Tab.aircraft)) {
            const rank = Progress.spaceFrameRank(recipe.output.space_frame);
            var rank_buffer: [32]u8 = undefined;
            const rank_text = std.fmt.bufPrint(&rank_buffer, "RANK {d}/{d}", .{ sb.kits[0].combatLevel(), rank }) catch "";
            c.text(row.x + row.w - 590, row.y + 10, rank_text, 0.9, if (sb.kits[0].combatLevel() >= rank) good else dim);
        }
        if (Fabricator.status(&sb.progress, &sb.kits[0], recipe.output)) |status| {
            const state_color = if (std.mem.eql(u8, status, "FABRICATE KESTREL FIRST")) bad else good;
            c.text(row.x + row.w - 250, row.y + 10, status, 1, state_color);
        } else if (Fabricator.progressCost(&sb.progress, recipe.output)) |cost| {
            var text_buffer: [40]u8 = undefined;
            c.text(row.x + row.w - 250, row.y + 10, costText(&text_buffer, cost), 1, if (affordable(sb.kits[0].wallet, cost)) gold else bad);
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
                const have = if (p.kind) |k| sb.kits[0].count(k) else sb.kits[0].wallet.scrap;
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
            if (recipe.cost.parts > 0) {
                var text: [20]u8 = undefined;
                const label = std.fmt.bufPrint(&text, "{d} PARTS", .{recipe.cost.parts}) catch "";
                c.text(cx, row.y + 10, label, 1, if (sb.kits[0].wallet.parts >= recipe.cost.parts) gold else bad);
            }
        }
        y += 34;
    }
    const selected = Fabricator.recipes[rows[@min(shop.row, rows.len - 1)]];
    if (@as(Fabricator.Tab, @enumFromInt(shop.tab)) == .aircraft) {
        c.text(r.x + 18, r.y + r.h - 72, selected.about, 0.9, ink);
        aircraftDetail(c, sb, selected.output, r.x + 18, r.y + r.h - 52);
    } else {
        c.text(r.x + 18, r.y + r.h - 50, selected.about, 1, ink);
    }
    c.text(r.x + 18, r.y + r.h - 28, if (@as(Fabricator.Tab, @enumFromInt(shop.tab)) == .aircraft) "LEFT RIGHT TAB  ENTER INSTALL / SELECT  ESC CLOSE" else "LEFT RIGHT TAB  ENTER FABRICATE  ESC CLOSE  FIND PICKUPS IN THE WORLD", 0.9, alpha(dim, 0.8));
}

fn aircraftDetail(c: *Canvas, sb: *const Sandbox, output: Fabricator.Output, x: f32, y: f32) void {
    switch (output) {
        .space_frame => |frame| {
            const cfg = Hangar.configFor(frame, sb.progress.kestrel_levels);
            c.print(x, y, 0.9, accent, "THRUST {d:.0}   HULL {d:.0}   WING ASPECT {d:.1}   REQUIRED RANK {d}", .{ cfg.thrust, cfg.hull_max, cfg.aero.aspect, Progress.spaceFrameRank(frame) });
        },
        .kestrel_upgrade => |upgrade| {
            const level = sb.progress.kestrelLevel(upgrade);
            const cfg = Hangar.configFor(.kestrel, sb.progress.kestrel_levels);
            switch (upgrade) {
                .armor => c.print(x, y, 0.9, accent, "CURRENT HULL {d:.0}   NEXT LEVEL +75 HULL", .{cfg.hull_max}),
                .engine => c.print(x, y, 0.9, accent, "CURRENT THRUST {d:.0}   NEXT LEVEL +12% THRUST", .{cfg.thrust}),
                .missile_rack => c.print(x, y, 0.9, accent, "UPGRADE LEVEL {d}/{d}   +2 MISSILES PER LEVEL", .{ level, Progress.max_level }),
                .gun_cooling => c.print(x, y, 0.9, accent, "UPGRADE LEVEL {d}/{d}   FASTER COOLING, LONGER FIRING", .{ level, Progress.max_level }),
            }
        },
        .kestrel_paint => |paint| {
            const state = Fabricator.status(&sb.progress, &sb.kits[0], .{ .kestrel_paint = paint }) orelse "AVAILABLE TO UNLOCK";
            c.text(x, y, state, 0.9, accent);
        },
        else => {},
    }
}

fn drawPlatformEditor(c: *Canvas, sb: *const Sandbox) void {
    const w: f32 = @min(520, c.width - 32);
    const h: f32 = 304;
    const x = (c.width - w) / 2;
    const y = (c.height - h) / 2;
    const frame: Rect = .{ .x = x, .y = y, .w = w, .h = h };
    panel(c, frame, "FLOATING PLATFORM BUILDER");
    c.text(x + 20, y + 52, "Aim at a surface, then set the deck height from that point.", 1, dim);

    const button_y = y + 82;
    const gap: f32 = 12;
    const wide = (w - 40 - gap) / 2;
    button(c, .{ .x = x + 20, .y = button_y, .w = wide, .h = 42 }, "HORIZONTAL 16m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.horizontal)), !sb.tools.platform_vertical);
    button(c, .{ .x = x + 20 + wide + gap, .y = button_y, .w = wide, .h = 42 }, "VERTICAL 16m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.vertical)), sb.tools.platform_vertical);

    var offset: [48]u8 = undefined;
    const label = std.fmt.bufPrint(&offset, "HEIGHT OFFSET  {d:.0} m", .{sb.tools.platform_offset}) catch unreachable;
    c.centered(x + w / 2, y + 152, label, 1.5, ink);
    const step_y = y + 178;
    const step_w = (w - 40 - 3 * gap) / 4;
    button(c, .{ .x = x + 20, .y = step_y, .w = step_w, .h = 38 }, "-10 m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.down_ten)), false);
    button(c, .{ .x = x + 20 + (step_w + gap), .y = step_y, .w = step_w, .h = 38 }, "-1 m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.down_one)), false);
    button(c, .{ .x = x + 20 + 2 * (step_w + gap), .y = step_y, .w = step_w, .h = 38 }, "+1 m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.up_one)), false);
    button(c, .{ .x = x + 20 + 3 * (step_w + gap), .y = step_y, .w = step_w, .h = 38 }, "+10 m", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.up_ten)), false);

    button(c, .{ .x = x + 20, .y = y + 238, .w = wide, .h = 38 }, "RESET HEIGHT", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.reset)), false);
    button(c, .{ .x = x + 20 + wide + gap, .y = y + 238, .w = wide, .h = 38 }, "DONE  [ESC]", hitId(.platform_editor, @intFromEnum(Build.PlatformEditorAction.close)), true);
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
    for ([_]Case{ .{ .screen = .title, .base = .title }, .{ .screen = .settings, .base = .title }, .{ .screen = .none, .base = .none }, .{ .screen = .pause, .base = .pause }, .{ .screen = .settings, .base = .pause }, .{ .screen = .controls, .base = .pause }, .{ .screen = .pad_controls, .base = .pause }, .{ .screen = .quest_log, .base = .pause }, .{ .screen = .guide, .base = .pause }, .{ .screen = .world_map, .base = .pause }, .{ .screen = .confirm_quit, .base = .pause } }) |case| {
        m.open(case.base);
        m.screen = case.screen;
        c.reset(1280, 720);
        draw(&c, &m, &sb, hud);
        try expectInside(&c);
        if (case.screen != .none) try std.testing.expect(c.hit_len > 0);
    }
    // Every HOW TO PLAY page stays inside the panel's window.
    m.open(.pause);
    m.open(.guide);
    for (0..@import("Guide.zig").page_count) |page| {
        m.guide_page = @intCast(page);
        c.reset(1280, 720);
        draw(&c, &m, &sb, hud);
        try expectInside(&c);
    }
    m.open(.pause);
    m.open(.world_map);
    for ([_][2]f32{ .{ 640, 480 }, .{ 853, 480 }, .{ 1280, 720 } }) |size| {
        for (0..3) |zoom| {
            m.map_zoom = @intCast(zoom);
            for ([_]bool{ false, true }) |framed| {
                m.map_frame_destination = framed;
                c.reset(size[0], size[1]);
                var scaled_hud = hud;
                scaled_hud.view = .{ .x = 0, .y = 0, .w = size[0], .h = size[1] };
                draw(&c, &m, &sb, scaled_hud);
                try expectInside(&c);
            }
        }
    }
    m.open(.none);
    // Panels: customization, every conversation node, the stall, upgrades and the wardrobe.
    sb.creator.begin(sb.profile);
    sb.creator.owned = Sandbox.Kit.free_suits;
    c.reset(1280, 720);
    draw(&c, &m, &sb, hud);
    try expectInside(&c);
    // Every field remains reachable, but each tab shows only its own rows. Check the full
    // tab contract at 720p and the smaller 640x480 window, including selectable tab hits.
    for ([_][2]f32{ .{ 1280, 720 }, .{ 640, 480 } }) |size| {
        for (creator_tab_starts, 0..) |start, tab| {
            sb.creator.field = start;
            c.reset(size[0], size[1]);
            draw(&c, &m, &sb, .{ .view = .{ .x = 0, .y = 0, .w = size[0], .h = size[1] }, .clock = "", .prompt = "", .toast = "" });
            try expectInside(&c);
            var rows: usize = 0;
            var selected = false;
            var tab_hit = false;
            var done = false;
            for (c.hits[0..c.hit_len]) |h| switch (hitArea(h.id)) {
                .creator_field => {
                    rows += 1;
                    const field_index: usize = h.id & 0xff;
                    try std.testing.expect(field_index >= @intFromEnum(start) and field_index < creator_tab_ends[tab]);
                    try std.testing.expect(h.rect.y >= 0 and h.rect.y + h.rect.h <= size[1]);
                    if (field_index == @intFromEnum(start)) selected = true;
                },
                .creator_tab => {
                    if (hitRow(h.id) == tab) tab_hit = true;
                },
                .creator_done => done = true,
                else => {},
            };
            try std.testing.expectEqual(creator_tab_ends[tab] - @intFromEnum(start), rows);
            try std.testing.expect(selected and tab_hit and done);
        }
    }
    sb.creator.field = .name;
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
    sb.guests[0].shop = .{ .kind = .fabricate, .tab = @intFromEnum(Fabricator.Tab.weapons) };
    for ([_][2]f32{ .{ 1280, 720 }, .{ 640, 480 } }) |size| {
        split.view = .{ .x = 0, .y = 0, .w = size[0] * 0.5, .h = size[1] * 0.5 };
        for (&guests, 0..) |*g, i| {
            const guest_rect = @import("../render/Layout.zig").viewRect(i + 1, 4);
            g.view = .{ .x = guest_rect.x * size[0], .y = guest_rect.y * size[1], .w = guest_rect.w * size[0], .h = guest_rect.h * size[1] };
        }
        c.reset(size[0], size[1]);
        draw(&c, &m, &sb, split);
        try expectInside(&c);
    }
    sb.guests[0].shop = null;
    const id = hitId(.choice, 3);
    try std.testing.expectEqual(Area.choice, hitArea(id));
    try std.testing.expectEqual(@as(u8, 3), hitRow(id));
}

/// Keep marker labels separate while retaining a small dot at their true projected position.
fn mapMarker(c: *Canvas, map: Rect, fx: f32, fy: f32, label: []const u8, color: Color, selected: bool, occupied: []Rect, count: *usize) void {
    const outside = fx < 0.03 or fx > 0.97 or fy < 0.12 or fy > 0.95;
    const x = map.x + map.w * std.math.clamp(fx, 0.03, 0.97);
    const y = map.y + map.h * std.math.clamp(fy, 0.12, 0.95);
    var buffer: [32]u8 = undefined;
    const direction: []const u8 = if (fy < 0.12) "N" else if (fy > 0.95) "S" else if (fx < 0.03) "W" else "E";
    const text = if (outside) std.fmt.bufPrint(&buffer, "{s} {s} OFF", .{ label, direction }) catch label else label;
    const width = Canvas.textWidth(text, 0.8) + 6;
    var tag: Rect = .{ .x = std.math.clamp(x + 7, map.x + 2, map.x + map.w - width - 2), .y = y, .w = width, .h = 12 };
    for (0..32) |attempt| {
        const offset: f32 = @floatFromInt((attempt + 1) / 2 * 13);
        tag.y = std.math.clamp(y + (if (attempt % 2 == 0) offset else -offset), map.y + 24, map.y + map.h - 14);
        var overlaps = false;
        for (occupied[0..count.*]) |other| {
            if (tag.x < other.x + other.w and tag.x + tag.w > other.x and tag.y < other.y + other.h and tag.y + tag.h > other.y) overlaps = true;
        }
        if (!overlaps) break;
    }
    if (count.* < occupied.len) {
        occupied[count.*] = tag;
        count.* += 1;
    }
    c.rect(.{ .x = x - 2, .y = y - 2, .w = 4, .h = 4 }, color);
    if (selected) {
        c.frame(.{ .x = x - 5, .y = y - 5, .w = 10, .h = 10 }, 1, ink);
        c.focus(.{ .x = x - 5, .y = y - 5, .w = 10, .h = 10 });
    }
    c.rect(tag, .{ 0.015, 0.025, 0.035, 0.95 });
    c.text(tag.x + 3, tag.y + 2, text, 0.8, color);
}

/// Compact, unlabeled point of interest. The legend explains its single-letter marker.
fn mapPoi(c: *Canvas, map: Rect, fx: f32, fy: f32, mark: []const u8, color: Color, selected: bool) void {
    if (fx < 0.02 or fx > 0.98 or fy < 0.15 or fy > 0.98) return;
    const x = map.x + map.w * fx;
    const y = map.y + map.h * fy;
    const icon: Rect = .{ .x = x - 7, .y = y - 7, .w = 14, .h = 14 };
    c.rect(icon, .{ 0.012, 0.026, 0.034, 0.96 });
    c.frame(icon, 1, if (selected) gold else color);
    c.text(icon.x + 4, icon.y + 3, mark, 0.9, color);
    if (selected) c.focus(icon);
}

const TrackedTarget = struct { position: [3]f32 };

fn sameTarget(a: [3]f32, b: [3]f32) bool {
    return a[0] == b[0] and a[2] == b[2];
}

fn trackedTarget(kind: Menu.MapTarget, sb: *const Sandbox, from: [3]f32, player: usize) ?TrackedTarget {
    if (kind == .none) return null;
    var best: ?TrackedTarget = null;
    var best_d2 = std.math.inf(f32);
    const consider = struct {
        fn add(best_target: *?TrackedTarget, best_distance: *f32, origin: [3]f32, position: [3]f32) void {
            const dx = position[0] - origin[0];
            const dz = position[2] - origin[2];
            const d2 = dx * dx + dz * dz;
            if (d2 < best_distance.*) {
                best_distance.* = d2;
                best_target.* = .{ .position = position };
            }
        }
    }.add;
    switch (kind) {
        .none => unreachable,
        .nest => for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| {
            if (nest.alive and !nest.cave) consider(&best, &best_d2, from, nest.position);
        },
        .cave => for (sb.caves.systems[0..sb.caves.count]) |cave| consider(&best, &best_d2, from, cave.entrance),
        .wildkin => for (sb.encounters) |maybe| if (maybe) |spot| {
            if (Heroes.roster[spot.hero].home == .wilds and !sb.progress.hasHero(spot.hero)) consider(&best, &best_d2, from, spot.position);
        },
        .wildlife => for (sb.pets.spots, 0..) |spot, i| {
            if (sb.pets.wild_health[i] <= 0) continue;
            const species: Pets.Species = @enumFromInt(i);
            if (!sb.kits[player].hasPet(species)) consider(&best, &best_d2, from, spot.position);
        },
    }
    return best;
}

/// Keep the map's destination list readable while fitting the panel on short windows.
fn mapRowStep(panel_height: f32, zoom: u8) f32 {
    const row_count: f32 = @floatFromInt(Menu.map_items.len);
    const zoom_reserve: f32 = if (zoom == 3) 60 else 0;
    const available = panel_height - (55 + 40 + 60 + 63 + zoom_reserve);
    return @min(24, @max(14, available / row_count));
}

fn drawWorldMap(c: *Canvas, menu: *const Menu, sb: *const Sandbox) void {
    const r = menuRect(c, @min(720, c.width - 30), @min(690, c.height - 30));
    panel(c, r, "WORLD MAP / FAST TRAVEL");
    // The rows (every travel destination, the frame row and RESUME) set the map's height, so the
    // list always fits: the panel used to overflow once there were more than eight rows.
    const map_row_step = mapRowStep(r.h, menu.map_zoom);
    const rows_h = @as(f32, @floatFromInt(Menu.map_items.len)) * map_row_step;
    const map: Rect = .{ .x = r.x + 20, .y = r.y + 55, .w = r.w - 40, .h = @max(60, r.h - (55 + 40 + rows_h + 63 + (if (menu.map_zoom == 3) @as(f32, 60) else 0))) };
    c.rect(map, .{ 0.025, 0.09, 0.075, 1 });
    const span: f32 = switch (menu.map_zoom) {
        0 => 1400,
        1 => 2800,
        2 => 5600,
        else => 560000,
    };
    const depth = span * map.h / map.w;
    const player_position = if (menu.hero_player == 0 or menu.hero_player > 3) sb.player.feet else sb.guests[menu.hero_player - 1].player.feet;
    const tracked = trackedTarget(menu.map_target, sb, player_position, menu.hero_player);
    const destination = if (menu.row < Sandbox.travel_count) menu.row else menu.map_destination;
    if (menu.map_zoom == 3) return drawPlanetMap(c, menu, sb, r, map, destination);
    const focus = if (tracked) |target| target.position else if (menu.row < Sandbox.travel_count or menu.map_frame_destination) sb.travelPoint(destination) else player_position;
    for (0..12) |z| for (0..20) |x| {
        const fx = @as(f32, @floatFromInt(x)) / 20;
        const fz = @as(f32, @floatFromInt(z)) / 12;
        const wx = focus[0] + (fx - 0.5) * span;
        const wz = focus[2] + (fz - 0.5) * depth;
        const region_seed = @import("../world/Region.zig").seedAtPosition(sb.seed, wx, wz);
        const surface = @import("../procedural/Terrain.zig").surface(sb.seed, wx, wz);
        const biome = @import("../procedural/Biome.zig").sample(region_seed, wx, wz).color();
        const relief = std.math.clamp(0.55 + surface.normal[0] * 0.3 + surface.normal[2] * 0.25 + surface.height / 350, 0.25, 1);
        const color = [3]f32{ biome[0] * relief, biome[1] * relief, biome[2] * relief };
        c.rect(.{ .x = map.x + map.w * fx, .y = map.y + map.h * fz, .w = map.w / 20 + 1, .h = map.h / 12 + 1 }, .{ color[0] * 0.5, color[1] * 0.6, color[2] * 0.5, 1 });
    };
    for (0..8) |i| {
        const f = @as(f32, @floatFromInt(i)) / 7;
        c.rect(.{ .x = map.x + map.w * f, .y = map.y, .w = 1, .h = map.h }, alpha(dim, 0.2));
        c.rect(.{ .x = map.x, .y = map.y + map.h * f, .w = map.w, .h = 1 }, alpha(dim, 0.2));
    }
    const title = if (destination < Sandbox.travel_count) Sandbox.travel_destinations[destination].map_title else @import("../world/Region.zig").default_title;
    c.print(map.x + 8, map.y + 8, 1, ink, "{s}", .{title});
    c.print(map.x + 8, map.y + 23, 0.8, dim, "N ^  {d:.0}M WIDE / LEFT-RIGHT ZOOM", .{span});
    const legend_y = map.y + 39;
    c.text(map.x + 8, legend_y, "N", 0.9, bad);
    c.text(map.x + 18, legend_y, "NEST", 0.7, dim);
    c.text(map.x + 58, legend_y, "C", 0.9, accent);
    c.text(map.x + 68, legend_y, "CAVE", 0.7, dim);
    c.text(map.x + 111, legend_y, "H", 0.9, .{ 0.82, 0.63, 1, 1 });
    c.text(map.x + 121, legend_y, "WILDKIN", 0.7, dim);
    c.text(map.x + 184, legend_y, "A", 0.9, good);
    c.text(map.x + 194, legend_y, "WILDLIFE", 0.7, dim);
    c.text(map.x + 261, legend_y, "!", 0.9, gold);
    c.text(map.x + 271, legend_y, "ENCOUNTER", 0.7, dim);
    c.text(map.x + 337, legend_y, "T", 0.9, gold);
    c.text(map.x + 347, legend_y, "TRAVEL", 0.7, dim);
    var occupied: [12]Rect = undefined;
    var marker_count: usize = 0;
    for (0..Sandbox.travel_count) |i| {
        const point = sb.travelPoint(i);
        mapPoi(c, map, 0.5 + (point[0] - focus[0]) / span, 0.5 + (point[2] - focus[2]) / depth, "T", gold, destination == i);
    }
    for (0..4) |i| {
        if (i > 0 and !sb.guests[i - 1].active) continue;
        const point = if (i == 0) sb.player.feet else sb.guests[i - 1].player.feet;
        var label: [8]u8 = undefined;
        mapMarker(c, map, 0.5 + (point[0] - focus[0]) / span, 0.5 + (point[2] - focus[2]) / depth, std.fmt.bufPrint(&label, "P{d}", .{i + 1}) catch "?", accent, menu.hero_player == i, &occupied, &marker_count);
    }
    for (sb.enemies.nests[0..sb.enemies.nest_count]) |nest| if (nest.alive and !nest.cave) {
        const selected = if (tracked) |target| sameTarget(target.position, nest.position) else false;
        mapPoi(c, map, 0.5 + (nest.position[0] - focus[0]) / span, 0.5 + (nest.position[2] - focus[2]) / depth, "N", bad, selected);
    };
    for (sb.caves.systems[0..sb.caves.count]) |cave| {
        const selected = if (tracked) |target| sameTarget(target.position, cave.entrance) else false;
        mapPoi(c, map, 0.5 + (cave.entrance[0] - focus[0]) / span, 0.5 + (cave.entrance[2] - focus[2]) / depth, "C", accent, selected);
    }
    for (sb.encounters) |maybe| if (maybe) |spot| {
        if (Heroes.roster[spot.hero].home == .wilds and !sb.progress.hasHero(spot.hero)) {
            const selected = if (tracked) |target| sameTarget(target.position, spot.position) else false;
            mapPoi(c, map, 0.5 + (spot.position[0] - focus[0]) / span, 0.5 + (spot.position[2] - focus[2]) / depth, "H", .{ 0.82, 0.63, 1, 1 }, selected);
        }
    };
    for (sb.pets.spots, 0..) |spot, species_index| {
        if (sb.pets.wild_health[species_index] <= 0) continue;
        const species: Pets.Species = @enumFromInt(species_index);
        var wanted = false;
        for (0..Sandbox.max_players) |p| if (sb.present(p) and !sb.kits[p].hasPet(species)) {
            wanted = true;
        };
        if (wanted) {
            const selected = if (tracked) |target| sameTarget(target.position, spot.position) else false;
            mapPoi(c, map, 0.5 + (spot.position[0] - focus[0]) / span, 0.5 + (spot.position[2] - focus[2]) / depth, "A", good, selected);
        }
    }
    for (0..Enemies.max_nests) |nest_index| {
        if (sb.enemies.unitCount(@intCast(nest_index)) == 0) continue;
        const nest = sb.enemies.nests[nest_index];
        mapPoi(c, map, 0.5 + (nest.position[0] - focus[0]) / span, 0.5 + (nest.position[2] - focus[2]) / depth, "!", gold, false);
    }
    c.print(r.x + 22, map.y + map.h + 15, 1, ink, "P{d} / GOLD: DESTINATION / {s} VIEW", .{ menu.hero_player + 1, if (menu.map_frame_destination) "DESTINATION" else "PLAYER" });
    for (Menu.map_items, 0..) |item, i| {
        const row: Rect = .{ .x = r.x + 12, .y = map.y + map.h + 40 + @as(f32, @floatFromInt(i)) * map_row_step, .w = r.w - 24, .h = map_row_step - 3 };
        rowBack(c, row, menu.row == i);
        const on = menu.enabled(i);
        if (i == Menu.frame_row) {
            const label: []const u8 = switch (menu.map_target) {
                .none => "TRACK TARGET: OFF",
                .nest => "TRACK TARGET: HIVE NESTS",
                .cave => "TRACK TARGET: CAVES",
                .wildkin => "TRACK TARGET: WILDKIN",
                .wildlife => "TRACK TARGET: CAPTURABLE WILDLIFE",
            };
            c.text(row.x + 12, row.y + 6, label, 1, if (menu.row == i) accent else ink);
        } else c.text(row.x + 12, row.y + 6, item.label, 1, if (!on) dim else if (menu.row == i) accent else ink);
        if (on) c.hit(row, hitId(.menu, i));
        if (i < Sandbox.travel_count) {
            const point = sb.travelPoint(i);
            const dx = point[0] - player_position[0];
            const dz = point[2] - player_position[2];
            c.print(row.x + row.w - 175, row.y + 6, 0.8, dim, "{d:.0}M / ALT {d:.0}M", .{ @sqrt(dx * dx + dz * dz), point[1] });
        }
    }
    c.text(r.x + 22, r.y + r.h - 24, "ENTER CYCLE TARGET / LEFT FRAME / RIGHT ZOOM OUT / ESC BACK", 1, dim);
}

fn drawPlanetMap(c: *Canvas, menu: *const Menu, sb: *const Sandbox, panel_rect: Rect, map: Rect, destination: usize) void {
    const map_row_step = mapRowStep(panel_rect.h, menu.map_zoom);
    c.rect(map, .{ 0.012, 0.035, 0.075, 1 });
    c.hit(map, hitId(.planet_globe, 0));
    const radius = @min(map.h * 0.43, map.w * 0.24);
    const center_x = map.x + map.w / 2;
    const center_y = map.y + map.h * 0.46;
    const pi: f32 = std.math.pi;
    const latitude_steps: usize = 18;
    const longitude_steps: usize = 32;
    for (0..latitude_steps) |yi| {
        const lat = -pi / 2 + (@as(f32, @floatFromInt(yi)) + 0.5) * pi / @as(f32, @floatFromInt(latitude_steps));
        const lat_deg = lat * 180 / pi;
        const cell_h = radius * pi / @as(f32, @floatFromInt(latitude_steps)) * 1.12;
        for (0..longitude_steps) |xi| {
            const lon = -pi + (@as(f32, @floatFromInt(xi)) + 0.5) * 2 * pi / @as(f32, @floatFromInt(longitude_steps));
            const lon_deg = lon * 180 / pi;
            const point = globePoint(lat, lon, menu.globe_yaw, menu.globe_pitch);
            if (point[2] <= 0) continue;
            const px = center_x + point[0] * radius;
            const py = center_y - point[1] * radius;
            if (px < map.x or px > map.x + map.w or py < map.y + 28 or py > map.y + map.h) continue;
            const cell_w = radius * 2 * pi / @as(f32, @floatFromInt(longitude_steps)) * @cos(lat) * 1.15;
            const lit = 0.58 + 0.3 * point[2] + 0.12 * @max(point[1], 0);
            const color: [4]f32 = if (isLand(lat_deg, lon_deg))
                .{ 0.22 * lit, 0.42 * lit, 0.26 * lit, 1 }
            else
                .{ 0.035 * lit, 0.23 * lit, 0.42 * lit, 1 };
            c.rect(.{ .x = px - cell_w / 2, .y = py - cell_h / 2, .w = cell_w + 1, .h = cell_h + 1 }, color);
        }
    }
    for (TerrainSites.us_cities) |city| {
        const lat = city.latitude * pi / 180;
        const lon = city.longitude * pi / 180;
        const point = globePoint(lat, lon, menu.globe_yaw, menu.globe_pitch);
        if (point[2] <= 0) continue;
        const px = center_x + point[0] * radius;
        const py = center_y - point[1] * radius;
        const travel_label = cityTravelLabel(city.name);
        const selected = if (travel_label) |label| destinationNamed(destination, label) else false;
        const color = if (travel_label != null) (if (selected) accent else gold) else if (city.asset != null) cityBiomeColor(city.biome) else alpha(dim, 0.75);
        const size: f32 = if (selected) 9 else if (travel_label != null) 5 else 3.5;
        c.rect(.{ .x = px - size / 2, .y = py - size / 2, .w = size, .h = size }, color);
        if (selected) c.frame(.{ .x = px - size / 2 - 3, .y = py - size / 2 - 3, .w = size + 6, .h = size + 6 }, 1, accent);
    }
    for (TerrainSites.mountains) |site| {
        const point = globePoint(site.latitude * pi / 180, site.longitude * pi / 180, menu.globe_yaw, menu.globe_pitch);
        if (point[2] <= 0) continue;
        const px = center_x + point[0] * radius;
        const py = center_y - point[1] * radius;
        const selected = std.mem.eql(u8, site.name, "K2") and (destinationNamed(destination, "K2 EXPEDITION") or destinationNamed(destination, "CLOUDWATER BASIN"));
        const color: Color = if (std.mem.eql(u8, site.name, "K2")) gold else .{ 0.38, 0.78, 1, 1 };
        const size: f32 = if (selected) 9 else 4;
        c.rect(.{ .x = px - size / 2, .y = py - size / 2, .w = size, .h = size }, if (selected) accent else color);
        if (selected) c.frame(.{ .x = px - size / 2 - 3, .y = py - size / 2 - 3, .w = size + 6, .h = size + 6 }, 1, accent);
    }
    for (TerrainSites.strongholds) |site| {
        const point = globePoint(site.latitude * pi / 180, site.longitude * pi / 180, menu.globe_yaw, menu.globe_pitch);
        if (point[2] <= 0) continue;
        const px = center_x + point[0] * radius;
        const py = center_y - point[1] * radius;
        const size: f32 = 4;
        c.frame(.{ .x = px - size / 2, .y = py - size / 2, .w = size, .h = size }, 1, .{ 0.86, 0.54, 1, 1 });
    }
    const antarctica_point = globePoint(CityGeography.antarctica.latitude * pi / 180, CityGeography.antarctica.longitude * pi / 180, menu.globe_yaw, menu.globe_pitch);
    if (antarctica_point[2] > 0) {
        const px = center_x + antarctica_point[0] * radius;
        const py = center_y - antarctica_point[1] * radius;
        const selected = destinationNamed(destination, "ANTARCTICA");
        const size: f32 = if (selected) 9 else 5;
        c.rect(.{ .x = px - size / 2, .y = py - size / 2, .w = size, .h = size }, if (selected) accent else gold);
        if (selected) c.frame(.{ .x = px - size / 2 - 3, .y = py - size / 2 - 3, .w = size + 6, .h = size + 6 }, 1, accent);
    }
    c.print(map.x + 8, map.y + 8, 0.9, ink, "EARTH  /  DRAG TO ROTATE  /  LEFT-RIGHT TO ZOOM", .{});
    c.centered(center_x, map.y + map.h - 16, "24 CITIES: BIOME COLOR  /  10 MOUNTAINS: BLUE  /  6 STRONGHOLDS: VIOLET  /  GOLD: PLAYABLE", 0.72, dim);

    for (Menu.map_items, 0..) |item, i| {
        const row: Rect = .{ .x = panel_rect.x + 12, .y = map.y + map.h + 40 + @as(f32, @floatFromInt(i)) * map_row_step, .w = panel_rect.w - 24, .h = map_row_step - 3 };
        rowBack(c, row, menu.row == i);
        const on = menu.enabled(i);
        if (i == Menu.frame_row) {
            c.text(row.x + 12, row.y + 6, "TRACK TARGET / FRAME MAP", 1, if (menu.row == i) accent else ink);
        } else c.text(row.x + 12, row.y + 6, item.label, 1, if (!on) dim else if (menu.row == i) accent else ink);
        if (on) c.hit(row, hitId(.menu, i));
        if (i < Sandbox.travel_count) {
            const point = sb.travelPoint(i);
            const player = if (menu.hero_player == 0 or menu.hero_player > 3) sb.player.feet else sb.guests[menu.hero_player - 1].player.feet;
            const dx = point[0] - player[0];
            const dz = point[2] - player[2];
            c.print(row.x + row.w - 175, row.y + 6, 0.8, dim, "{d:.0}M / ALT {d:.0}M", .{ @sqrt(dx * dx + dz * dz), point[1] });
        }
    }
    c.text(panel_rect.x + 22, panel_rect.y + panel_rect.h - 24, "SELECT A DESTINATION BELOW  /  ENTER TRAVEL  /  ESC BACK", 1, dim);
}

fn cityTravelLabel(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "Detroit")) return "BASE CAMP";
    if (std.mem.eql(u8, name, "Chicago")) return "CHICAGO";
    if (std.mem.eql(u8, name, "New York City")) return "NEW YORK CITY";
    return null;
}

fn cityBiomeColor(biome: TerrainSites.Biome) Color {
    return switch (biome) {
        .desert_basin, .desert_ring, .volcanic_salt_rift, .high_basalt => .{ 1, 0.65, 0.3, 1 },
        .coastal_mountain, .alpine_front_range, .alpine_glacier, .alpine_icefall => .{ 0.42, 0.78, 1, 1 },
        .subtropical_wetland, .humid_river_canopy, .jungle_mesa => .{ 0.35, 0.9, 0.75, 1 },
        else => .{ 0.58, 0.88, 0.5, 1 },
    };
}

fn destinationNamed(destination: usize, label: []const u8) bool {
    return destination < Sandbox.travel_count and std.mem.eql(u8, Sandbox.travel_destinations[destination].label, label);
}

fn globePoint(latitude: f32, longitude: f32, yaw: f32, pitch: f32) [3]f32 {
    const x = @cos(latitude) * @sin(longitude);
    const y = @sin(latitude);
    const z = @cos(latitude) * @cos(longitude);
    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const cp = @cos(pitch);
    const sp = @sin(pitch);
    const rx = x * cy - z * sy;
    const rz = x * sy + z * cy;
    return .{ rx, y * cp - rz * sp, y * sp + rz * cp };
}

fn isLand(latitude: f32, longitude: f32) bool {
    const north_america = [_][2]f32{ .{ -168, 72 }, .{ -145, 70 }, .{ -128, 56 }, .{ -112, 50 }, .{ -96, 50 }, .{ -82, 25 }, .{ -97, 8 }, .{ -116, 25 }, .{ -130, 48 }, .{ -155, 55 } };
    const south_america = [_][2]f32{ .{ -81, 12 }, .{ -66, 10 }, .{ -48, -4 }, .{ -36, -18 }, .{ -53, -56 }, .{ -72, -42 }, .{ -79, -10 } };
    const eurasia = [_][2]f32{ .{ -12, 36 }, .{ -10, 58 }, .{ 15, 72 }, .{ 45, 66 }, .{ 65, 72 }, .{ 100, 70 }, .{ 135, 58 }, .{ 165, 60 }, .{ 178, 48 }, .{ 145, 38 }, .{ 120, 20 }, .{ 104, 6 }, .{ 74, 8 }, .{ 57, 28 }, .{ 42, 38 }, .{ 30, 34 }, .{ 20, 42 }, .{ 8, 36 } };
    const africa = [_][2]f32{ .{ -18, 35 }, .{ 8, 37 }, .{ 36, 29 }, .{ 51, 11 }, .{ 42, -12 }, .{ 32, -34 }, .{ 16, -35 }, .{ 2, -28 }, .{ -9, -3 }, .{ -17, 15 } };
    const australia = [_][2]f32{ .{ 112, -11 }, .{ 132, -10 }, .{ 154, -25 }, .{ 145, -39 }, .{ 116, -35 }, .{ 112, -22 } };
    const greenland = [_][2]f32{ .{ -54, 84 }, .{ -22, 78 }, .{ -38, 59 }, .{ -60, 61 } };
    return pointInPolygon(latitude, longitude, &north_america) or pointInPolygon(latitude, longitude, &south_america) or pointInPolygon(latitude, longitude, &eurasia) or pointInPolygon(latitude, longitude, &africa) or pointInPolygon(latitude, longitude, &australia) or pointInPolygon(latitude, longitude, &greenland) or latitude < -72;
}

fn pointInPolygon(latitude: f32, longitude: f32, polygon: []const [2]f32) bool {
    var inside = false;
    var previous = polygon.len - 1;
    for (polygon, 0..) |current, index| {
        const a = current;
        const b = polygon[previous];
        if ((a[1] > latitude) != (b[1] > latitude) and longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
        previous = index;
    }
    return inside;
}

test "clustered and offscreen map markers retain separate labels inside the map" {
    var c: Canvas = .{};
    c.reset(640, 480);
    const map: Rect = .{ .x = 30, .y = 70, .w = 580, .h = 165 };
    for ([_][2]f32{ .{ 0.5, 0.5 }, .{ 10, -10 }, .{ -10, 10 } }) |point| {
        var occupied: [7]Rect = undefined;
        var count: usize = 0;
        c.reset(640, 480);
        for (0..7) |_| mapMarker(&c, map, point[0], point[1], "P1", accent, false, &occupied, &count);
        try expectInside(&c);
        for (occupied, 0..) |a, i| {
            try std.testing.expect(a.x >= map.x and a.y >= map.y and a.x + a.w <= map.x + map.w and a.y + a.h <= map.y + map.h);
            for (occupied[0..i]) |b| try std.testing.expect(a.x >= b.x + b.w or a.x + a.w <= b.x or a.y >= b.y + b.h or a.y + a.h <= b.y);
        }
    }
}
