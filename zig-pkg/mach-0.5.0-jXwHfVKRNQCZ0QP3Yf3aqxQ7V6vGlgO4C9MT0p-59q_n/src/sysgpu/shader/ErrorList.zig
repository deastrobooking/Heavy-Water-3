const std = @import("std");
const Token = @import("Token.zig");
pub const ErrorList = @This();

pub const ErrorMsg = struct {
    loc: Token.Loc,
    msg: []const u8,
    note: ?Note = null,

    pub const Note = struct {
        loc: ?Token.Loc = null,
        msg: []const u8,
    };
};

arena: std.heap.ArenaAllocator,
list: std.ArrayList(ErrorMsg) = .empty,

pub fn init(allocator: std.mem.Allocator) !ErrorList {
    return .{
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
}

pub fn deinit(self: *ErrorList) void {
    self.arena.deinit();
    self.* = undefined;
}

pub fn add(
    self: *ErrorList,
    loc: Token.Loc,
    comptime format: []const u8,
    args: anytype,
    note: ?ErrorMsg.Note,
) !void {
    try self.list.append(self.arena.allocator(), .{
        .loc = loc,
        .msg = try std.fmt.allocPrint(self.arena.allocator(), comptime format, args),
        .note = note,
    });
}

pub fn createNote(
    self: *ErrorList,
    loc: ?Token.Loc,
    comptime format: []const u8,
    args: anytype,
) !ErrorMsg.Note {
    return .{
        .loc = loc,
        .msg = try std.fmt.allocPrint(self.arena.allocator(), comptime format, args),
    };
}

pub fn print(self: ErrorList, source: []const u8, file_path: ?[]const u8) !void {
    for (self.list.items) |*err| {
        const loc_extra = err.loc.extraInfo(source);

        // 'file:line:column error: MSG'
        std.debug.print("{?s}:{d}:{d} error: {s}\n", .{ file_path, loc_extra.line, loc_extra.col, err.msg });

        printCode(source, err.loc);

        // note
        if (err.note) |note| {
            if (note.loc) |note_loc| {
                const note_loc_extra = note_loc.extraInfo(source);
                std.debug.print("{?s}:{d}:{d} ", .{ file_path, note_loc_extra.line, note_loc_extra.col });
            }
            std.debug.print("note: {s}\n", .{note.msg});

            if (note.loc) |note_loc| {
                printCode(source, note_loc);
            }
        }
    }
}

fn printCode(source: []const u8, loc: Token.Loc) void {
    const loc_extra = loc.extraInfo(source);
    std.debug.print("{d} │ {s}{s}{s}\n", .{
        loc_extra.line,
        source[loc_extra.line_start..loc.start],
        source[loc.start..loc.end],
        source[loc.end..loc_extra.line_end],
    });

    // location pointer
    const line_number_len = (std.math.log10(loc_extra.line) + 1) + 3;
    const pad = if (line_number_len > loc_extra.col) line_number_len + (loc_extra.col - 1) else 0;
    var i: usize = 0;
    while (i < pad) : (i += 1) std.debug.print(" ", .{});
    std.debug.print("^", .{});
    if (loc.end > loc.start) {
        var j: usize = 0;
        while (j < loc.end - loc.start - 1) : (j += 1) std.debug.print("~", .{});
    }
    std.debug.print("\n", .{});
}
