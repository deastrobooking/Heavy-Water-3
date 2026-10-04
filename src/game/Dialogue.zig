//! Branching conversations, written as data (`conversations.json`, embedded) and validated at
//! load. A conversation starts at its first entry whose flag conditions hold; each node shows
//! text, may set a flag, and offers choices gated by flags. A choice can set a flag, give scrap,
//! move to another node, end the conversation, or end it by opening a panel (trade, upgrades,
//! wardrobe). Conversation `keeper_<stall>` belongs to a market keeper; `walker_<n>` lines are
//! shared by pedestrians.
const std = @import("std");
const Progress = @import("Progress.zig");
const Market = @import("../city/Market.zig");
const Dialogue = @This();

pub const Action = enum { none, trade, upgrades, wardrobe };
pub const max_choices = 8;
pub const max_text = 280;
pub const Choice = struct {
    text: []const u8,
    /// Node to show next; empty ends the conversation (after `action`, if any).
    next: []const u8 = "",
    action: Action = .none,
    /// Shown only while this flag is set / not set.
    requires: []const u8 = "",
    unless: []const u8 = "",
    sets: []const u8 = "",
    /// Scrap given to the wallet when chosen.
    scrap: u32 = 0,
};
pub const Node = struct {
    id: []const u8,
    text: []const u8,
    /// Where "continue" leads when no choice is shown; empty ends the conversation.
    next: []const u8 = "",
    /// Flag set when the node is shown.
    sets: []const u8 = "",
    choices: []const Choice = &.{},
};
pub const Entry = struct { node: []const u8, requires: []const u8 = "", unless: []const u8 = "" };
pub const Conversation = struct { id: []const u8, speaker: []const u8, entries: []const Entry, nodes: []const Node };
pub const Speaker = struct { id: []const u8, name: []const u8, role: []const u8 = "", accent: u8 = 0 };
pub const Data = struct { speakers: []const Speaker, conversations: []const Conversation };
pub const Error = error{ InvalidDialogue, UnknownSpeaker, UnknownNode, DuplicateId, TextTooLong, TooManyChoices, BadFlag };

parsed: std.json.Parsed(Data),

pub const builtin = @embedFile("conversations.json");

pub fn load(allocator: std.mem.Allocator, bytes: []const u8) !Dialogue {
    const parsed = std.json.parseFromSlice(Data, allocator, bytes, .{}) catch return error.InvalidDialogue;
    errdefer parsed.deinit();
    const self: Dialogue = .{ .parsed = parsed };
    try self.validate();
    return self;
}

pub fn deinit(self: *Dialogue) void {
    self.parsed.deinit();
}

fn checkFlag(name: []const u8) Error!void {
    if (name.len > Progress.flag_capacity) return error.BadFlag;
}

fn validate(self: *const Dialogue) Error!void {
    const data = self.parsed.value;
    for (data.speakers, 0..) |s, i| for (data.speakers[0..i]) |o| if (std.mem.eql(u8, o.id, s.id)) return error.DuplicateId;
    for (data.conversations, 0..) |c, ci| {
        for (data.conversations[0..ci]) |o| if (std.mem.eql(u8, o.id, c.id)) return error.DuplicateId;
        _ = self.speakerIndex(c.speaker) orelse return error.UnknownSpeaker;
        if (c.entries.len == 0 or c.nodes.len == 0 or c.nodes.len > std.math.maxInt(u16)) return error.InvalidDialogue;
        for (c.entries) |e| {
            _ = nodeIndex(c, e.node) orelse return error.UnknownNode;
            try checkFlag(e.requires);
            try checkFlag(e.unless);
        }
        for (c.nodes, 0..) |n, ni| {
            for (c.nodes[0..ni]) |o| if (std.mem.eql(u8, o.id, n.id)) return error.DuplicateId;
            if (n.text.len == 0 or n.text.len > max_text) return error.TextTooLong;
            if (n.choices.len > max_choices) return error.TooManyChoices;
            if (n.next.len > 0 and nodeIndex(c, n.next) == null) return error.UnknownNode;
            try checkFlag(n.sets);
            for (n.choices) |ch| {
                if (ch.text.len == 0 or ch.text.len > 60) return error.TextTooLong;
                if (ch.next.len > 0 and nodeIndex(c, ch.next) == null) return error.UnknownNode;
                // A choice that opens a panel ends the conversation.
                if (ch.action != .none and ch.next.len > 0) return error.InvalidDialogue;
                try checkFlag(ch.requires);
                try checkFlag(ch.unless);
                try checkFlag(ch.sets);
            }
        }
    }
}

pub fn speakerIndex(self: *const Dialogue, id: []const u8) ?usize {
    for (self.parsed.value.speakers, 0..) |s, i| if (std.mem.eql(u8, s.id, id)) return i;
    return null;
}

fn nodeIndex(c: Conversation, id: []const u8) ?u16 {
    for (c.nodes, 0..) |n, i| if (std.mem.eql(u8, n.id, id)) return @intCast(i);
    return null;
}

pub fn find(self: *const Dialogue, id: []const u8) ?u16 {
    for (self.parsed.value.conversations, 0..) |c, i| if (std.mem.eql(u8, c.id, id)) return @intCast(i);
    return null;
}

/// Pedestrian `index`'s conversation, cycling through the `walker_` conversations in file
/// order (their numbering need not be contiguous).
pub fn walker(self: *const Dialogue, index: usize) ?u16 {
    var count: usize = 0;
    for (self.parsed.value.conversations) |c| {
        if (std.mem.startsWith(u8, c.id, "walker_")) count += 1;
    }
    if (count == 0) return null;
    var n = index % count;
    for (self.parsed.value.conversations, 0..) |c, i| if (std.mem.startsWith(u8, c.id, "walker_")) {
        if (n == 0) return @intCast(i);
        n -= 1;
    };
    unreachable;
}

fn passes(progress: *const Progress, requires: []const u8, unless: []const u8) bool {
    if (requires.len > 0 and !progress.hasFlag(requires)) return false;
    if (unless.len > 0 and progress.hasFlag(unless)) return false;
    return true;
}

/// Who the conversation is with, so actions reach the right stall and the camera the right face.
pub const Partner = union(enum) { keeper: u8, walker: u8 };

pub const Session = struct {
    conversation: u16,
    node: u16 = 0,
    /// Index into the node's *visible* choices.
    choice: u8 = 0,
    /// Characters of the node's text revealed so far (a typewriter, skipped by confirm).
    reveal: f32 = 0,
    partner: Partner,
};
pub const Outcome = union(enum) { talking, ended, action: Action };
pub const Key = enum { up, down, confirm, back };
/// Characters revealed per second.
pub const reveal_rate: f32 = 70;

pub fn conversation(self: *const Dialogue, s: Session) Conversation {
    return self.parsed.value.conversations[s.conversation];
}
pub fn node(self: *const Dialogue, s: Session) Node {
    return self.conversation(s).nodes[s.node];
}
pub fn speaker(self: *const Dialogue, s: Session) Speaker {
    return self.parsed.value.speakers[self.speakerIndex(self.conversation(s).speaker).?];
}

fn enter(self: *const Dialogue, s: *Session, index: u16, progress: *Progress) void {
    s.node = index;
    s.choice = 0;
    s.reveal = 0;
    progress.setFlag(self.node(s.*).sets);
}

/// Starts conversation `index` at its first entry whose conditions hold.
pub fn begin(self: *const Dialogue, index: u16, partner: Partner, progress: *Progress) ?Session {
    const c = self.parsed.value.conversations[index];
    for (c.entries) |e| if (passes(progress, e.requires, e.unless)) {
        var s: Session = .{ .conversation = index, .partner = partner };
        self.enter(&s, nodeIndex(c, e.node).?, progress);
        return s;
    };
    return null;
}

/// Indices of the node's choices whose flag conditions hold, in order.
pub fn visibleChoices(self: *const Dialogue, s: Session, progress: *const Progress, out: *[max_choices]u8) usize {
    var n: usize = 0;
    for (self.node(s).choices, 0..) |ch, i| if (passes(progress, ch.requires, ch.unless)) {
        out[n] = @intCast(i);
        n += 1;
    };
    return n;
}

pub fn revealed(self: *const Dialogue, s: Session) bool {
    return s.reveal >= @as(f32, @floatFromInt(self.node(s).text.len));
}

pub fn advance(s: *Session, dt: f32) void {
    s.reveal += reveal_rate * dt;
}

pub fn key(self: *const Dialogue, s: *Session, k: Key, progress: *Progress, wallet: *Market.Wallet) Outcome {
    var visible: [max_choices]u8 = undefined;
    const count = self.visibleChoices(s.*, progress, &visible);
    switch (k) {
        .back => return .ended,
        .up => if (count > 0) {
            s.choice = @intCast((s.choice + count - 1) % count);
        },
        .down => if (count > 0) {
            s.choice = @intCast((s.choice + 1) % count);
        },
        .confirm => {
            if (!self.revealed(s.*)) {
                s.reveal = @floatFromInt(self.node(s.*).text.len);
                return .talking;
            }
            const c = self.conversation(s.*);
            if (count == 0) {
                const next = self.node(s.*).next;
                if (next.len == 0) return .ended;
                self.enter(s, nodeIndex(c, next).?, progress);
                return .talking;
            }
            const ch = self.node(s.*).choices[visible[@min(s.choice, count - 1)]];
            progress.setFlag(ch.sets);
            wallet.scrap += ch.scrap;
            if (ch.action != .none) return .{ .action = ch.action };
            if (ch.next.len == 0) return .ended;
            self.enter(s, nodeIndex(c, ch.next).?, progress);
        },
    }
    return .talking;
}

test "the built-in conversations load and every keeper and walker has one" {
    var d = try load(std.testing.allocator, builtin);
    defer d.deinit();
    for (0..Market.stall_count) |i| {
        var buffer: [16]u8 = undefined;
        try std.testing.expect(d.find(try std.fmt.bufPrint(&buffer, "keeper_{d}", .{i})) != null);
    }
    try std.testing.expect(d.walker(0) != null and d.walker(7) != null);
}

test "conversations branch on flags, reveal text, give scrap once, and end in panels" {
    var d = try load(std.testing.allocator, builtin);
    defer d.deinit();
    var progress: Progress = .{};
    var wallet: Market.Wallet = .{};
    const maro = d.find("keeper_0").?;
    var s = d.begin(maro, .{ .keeper = 0 }, &progress).?;
    try std.testing.expectEqualStrings("first", d.node(s).id);
    try std.testing.expect(progress.hasFlag("met_maro"));
    // The first confirm finishes the typewriter; the next one chooses.
    try std.testing.expect(!d.revealed(s));
    try std.testing.expect(d.key(&s, .confirm, &progress, &wallet) == .talking);
    try std.testing.expect(d.revealed(s));
    try std.testing.expect(d.key(&s, .confirm, &progress, &wallet) == .talking);
    try std.testing.expectEqualStrings("upgrades_intro", d.node(s).id);
    s.reveal = 999;
    try std.testing.expectEqual(Outcome{ .action = .upgrades }, d.key(&s, .confirm, &progress, &wallet));

    // Second visit: the greeting changes, the gift appears once, and "salvaged" unlocks a line.
    s = d.begin(maro, .{ .keeper = 0 }, &progress).?;
    try std.testing.expectEqualStrings("hello", d.node(s).id);
    var visible: [max_choices]u8 = undefined;
    const before = d.visibleChoices(s, &progress, &visible);
    progress.setFlag("salvaged");
    try std.testing.expectEqual(before + 1, d.visibleChoices(s, &progress, &visible));
    s.reveal = 999;
    // Choose the gift: it is the second-to-last visible choice.
    s.choice = @intCast(d.visibleChoices(s, &progress, &visible) - 2);
    _ = d.key(&s, .confirm, &progress, &wallet);
    try std.testing.expectEqual(@as(u32, 25), wallet.scrap);
    try std.testing.expectEqualStrings("gift", d.node(s).id);
    // A node without choices continues to its `next`.
    s.reveal = 999;
    _ = d.key(&s, .confirm, &progress, &wallet);
    try std.testing.expectEqualStrings("hello", d.node(s).id);
    try std.testing.expectEqual(before, d.visibleChoices(s, &progress, &visible));
    try std.testing.expect(d.key(&s, .back, &progress, &wallet) == .ended);
}

test "Hive story beats gate Tavi, Ines and Maro in campaign order" {
    var d = try load(std.testing.allocator, builtin);
    defer d.deinit();
    var progress: Progress = .{};
    var wallet: Market.Wallet = .{};

    const tavi = d.find("keeper_2").?;
    var session = d.begin(tavi, .{ .keeper = 2 }, &progress).?;
    _ = d.key(&session, .back, &progress, &wallet);
    progress.setFlag("corruption_seen");
    session = d.begin(tavi, .{ .keeper = 2 }, &progress).?;
    try chooseNext(&d, &session, &progress, &wallet, "scout_mark");
    try std.testing.expect(progress.hasFlag("tavi_scouted"));

    progress.setFlag("met_ines");
    const ines = d.find("keeper_1").?;
    session = d.begin(ines, .{ .keeper = 1 }, &progress).?;
    try chooseNext(&d, &session, &progress, &wallet, "hive_sap");
    try std.testing.expect(progress.hasFlag("ines_sap_warned"));

    progress.setFlag("met_maro");
    progress.setFlag("carrier_seen");
    const maro = d.find("keeper_0").?;
    session = d.begin(maro, .{ .keeper = 0 }, &progress).?;
    try chooseNext(&d, &session, &progress, &wallet, "carrier_blueprint");
    try std.testing.expect(progress.hasFlag("kestrel_blueprint"));
}

fn chooseNext(d: *const Dialogue, session: *Session, progress: *Progress, wallet: *Market.Wallet, target: []const u8) !void {
    session.reveal = 1000;
    var visible: [max_choices]u8 = undefined;
    const count = d.visibleChoices(session.*, progress, &visible);
    const choice = for (0..count) |i| {
        const row = visible[i];
        const ch = d.node(session.*).choices[row];
        if (std.mem.eql(u8, ch.next, target)) break i;
    } else return error.ChoiceNotVisible;
    session.choice = @intCast(choice);
    _ = d.key(session, .confirm, progress, wallet);
    try std.testing.expectEqualStrings(target, d.node(session.*).id);
}

test "invalid dialogue is rejected with a reason" {
    const a = std.testing.allocator;
    const speaker_json = "{\"speakers\":[{\"id\":\"a\",\"name\":\"A\"}],\"conversations\":[";
    try std.testing.expectError(error.UnknownNode, load(a, speaker_json ++ "{\"id\":\"c\",\"speaker\":\"a\",\"entries\":[{\"node\":\"x\"}],\"nodes\":[{\"id\":\"n\",\"text\":\"t\"}]}]}"));
    try std.testing.expectError(error.UnknownSpeaker, load(a, speaker_json ++ "{\"id\":\"c\",\"speaker\":\"b\",\"entries\":[{\"node\":\"n\"}],\"nodes\":[{\"id\":\"n\",\"text\":\"t\"}]}]}"));
    try std.testing.expectError(error.InvalidDialogue, load(a, speaker_json ++ "{\"id\":\"c\",\"speaker\":\"a\",\"entries\":[{\"node\":\"n\"}],\"nodes\":[{\"id\":\"n\",\"text\":\"t\",\"choices\":[{\"text\":\"go\",\"next\":\"n\",\"action\":\"trade\"}]}]}]}"));
    try std.testing.expectError(error.InvalidDialogue, load(a, "not json"));
}
