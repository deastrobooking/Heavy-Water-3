//! Market stalls at the district's tower plazas. Each stall buys salvaged parts for scrap and
//! sells blueprint kits: one kit places one machine of that design from the build palette. Stock and prices are seeded per stall and
//! per day; a stall sells out and restocks at the next dawn. Stock, the day it was stocked,
//! and the player's wallet are saved.
const std = @import("std");
const Seed = @import("../procedural/Seed.zig");
const Sky = @import("../engine/Sky.zig");
const District = @import("../procedural/District.zig");
const Market = @This();

pub const Ware = enum { proximity_gate, street_lamp, signal_relay };
pub const ware_count = @typeInfo(Ware).@"enum".fields.len;
pub const stall_count = 3;
/// Tower plazas host the stalls.
pub const stall_plazas = [stall_count]u8{ 1, 3, 5 };
const base_price = [ware_count]u32{ 24, 12, 18 };
/// Scrap, salvaged parts, and unplaced kits of each ware.
pub const Wallet = struct { scrap: u32 = 0, parts: u32 = 0, kits: [ware_count]u8 = @splat(0) };
pub const Stall = struct { stock: [ware_count]u8 = @splat(0) };
pub const Error = error{ SoldOut, NotEnoughScrap, NoParts, UnknownStall };

seed: u64 = 0,
/// Market day the stalls were last stocked for.
day: u64 = 0,
stalls: [stall_count]Stall = @splat(.{}),

/// Market days turn over at dawn (time of day 0.25); tick 0 is mid-morning of day 0.
pub fn dayOf(tick: u64) u64 {
    return (tick + Sky.day_ticks / 10) / Sky.day_ticks;
}

pub fn init(seed: u64, tick: u64) Market {
    var self: Market = .{ .seed = seed };
    self.restock(dayOf(tick));
    return self;
}

fn hash(self: *const Market, stall: usize, what: u64, day: u64) u64 {
    return Seed.mix(self.seed ^ Seed.mix(0x4d41524b4554 +% stall *% 0x9E37 +% what *% 0x85EB +% day *% 0xC2B2AE35));
}

/// Fresh daily stock: 0–3 of each ware, and never an empty stall.
fn restock(self: *Market, day: u64) void {
    self.day = day;
    for (&self.stalls, 0..) |*stall, s| {
        var total: u32 = 0;
        for (&stall.stock, 0..) |*count, w| {
            count.* = @intCast(self.hash(s, w, day) % 4);
            total += count.*;
        }
        if (total == 0) stall.stock[self.hash(s, 99, day) % ware_count] = 1;
    }
}

/// Restocks when a new market day has begun. Returns whether it did.
pub fn update(self: *Market, tick: u64) bool {
    const day = dayOf(tick);
    if (day == self.day) return false;
    self.restock(day);
    return true;
}

/// Today's price of a ware at a stall: 80–125% of its base.
pub fn price(self: *const Market, stall: usize, ware: Ware) u32 {
    const w: usize = @intFromEnum(ware);
    return base_price[w] * (80 + @as(u32, @intCast(self.hash(stall, 10 + w, self.day) % 46))) / 100;
}

/// Scrap paid for each salvaged part at a stall today: 3–6.
pub fn partPrice(self: *const Market, stall: usize) u32 {
    return 3 + @as(u32, @intCast(self.hash(stall, 50, self.day) % 4));
}

/// Sells every part in the wallet; returns the scrap earned.
pub fn sellParts(self: *const Market, stall: usize, wallet: *Wallet) Error!u32 {
    if (stall >= stall_count) return error.UnknownStall;
    if (wallet.parts == 0) return error.NoParts;
    const earned = wallet.parts * self.partPrice(stall);
    wallet.scrap += earned;
    wallet.parts = 0;
    return earned;
}

/// Takes one of `ware` from the stall for scrap; nothing changes on failure.
pub fn buy(self: *Market, stall: usize, ware: Ware, wallet: *Wallet) Error!void {
    if (stall >= stall_count) return error.UnknownStall;
    const count = &self.stalls[stall].stock[@intFromEnum(ware)];
    if (count.* == 0) return error.SoldOut;
    const cost = self.price(stall, ware);
    if (wallet.scrap < cost) return error.NotEnoughScrap;
    if (wallet.kits[@intFromEnum(ware)] == std.math.maxInt(u8)) return error.SoldOut;
    wallet.scrap -= cost;
    count.* -= 1;
    wallet.kits[@intFromEnum(ware)] += 1;
}

/// Saved stock is accepted only for a plausible day and in-range counts.
pub fn restore(self: *Market, day: u64, stock: []const [ware_count]u8, tick: u64) error{InvalidSave}!void {
    if (stock.len != stall_count or day > dayOf(tick)) return error.InvalidSave;
    for (stock) |row| for (row) |count| if (count > 3) return error.InvalidSave;
    self.day = day;
    for (&self.stalls, stock) |*stall, row| stall.stock = row;
    _ = self.update(tick);
}

test "stalls stock seeded wares, sell out, restock at dawn, and trade parts for scrap" {
    var market = Market.init(310399555161, 0);
    try std.testing.expectEqual(@as(u64, 0), market.day);
    for (market.stalls) |stall| {
        var total: u32 = 0;
        for (stall.stock) |c| total += c;
        try std.testing.expect(total > 0);
    }
    // Sell four parts, then buy until a ware sells out.
    var wallet: Wallet = .{ .parts = 4 };
    const earned = try market.sellParts(0, &wallet);
    try std.testing.expect(earned >= 12 and earned <= 24 and wallet.parts == 0);
    try std.testing.expectError(error.NoParts, market.sellParts(0, &wallet));
    const ware: Ware = for (0..ware_count) |w| {
        if (market.stalls[0].stock[w] > 0) break @enumFromInt(w);
    } else unreachable;
    wallet.scrap = 1000;
    const stocked = market.stalls[0].stock[@intFromEnum(ware)];
    while (market.stalls[0].stock[@intFromEnum(ware)] > 0) try market.buy(0, ware, &wallet);
    try std.testing.expectError(error.SoldOut, market.buy(0, ware, &wallet));
    try std.testing.expectEqual(stocked, wallet.kits[@intFromEnum(ware)]);
    var poor: Wallet = .{};
    const other: Ware = for (0..ware_count) |w| {
        if (market.stalls[1].stock[w] > 0) break @enumFromInt(w);
    } else unreachable;
    const before = market.stalls[1].stock;
    try std.testing.expectError(error.NotEnoughScrap, market.buy(1, other, &poor));
    try std.testing.expectEqual(before, market.stalls[1].stock);

    // Still the same day until dawn; the next dawn restocks.
    const dawn = Sky.day_ticks - Sky.day_ticks / 10;
    try std.testing.expect(!market.update(dawn - 1));
    try std.testing.expectEqual(@as(u8, 0), market.stalls[0].stock[@intFromEnum(ware)]);
    try std.testing.expect(market.update(dawn));
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), Sky.timeOfDay(dawn), 1e-4);
    try std.testing.expectEqual(Market.init(310399555161, dawn).stalls, market.stalls);
    // Prices vary by day but stay within their band.
    for (0..stall_count) |s| for (0..ware_count) |w| {
        const p = market.price(s, @enumFromInt(w));
        try std.testing.expect(p >= base_price[w] * 80 / 100 and p <= base_price[w] * 125 / 100);
    };
    // Saved stock restores unless it claims a future day or impossible counts.
    var copy = Market.init(310399555161, 0);
    var rows: [stall_count][ware_count]u8 = undefined;
    for (&rows, market.stalls) |*row, stall| row.* = stall.stock;
    try copy.restore(market.day, &rows, dawn + 5);
    try std.testing.expectEqual(market.stalls, copy.stalls);
    try std.testing.expectError(error.InvalidSave, copy.restore(market.day + 1, &rows, dawn));
    rows[0][0] = 9;
    try std.testing.expectError(error.InvalidSave, copy.restore(market.day, &rows, dawn));
}
