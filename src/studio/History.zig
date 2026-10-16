//! Bounded undo and redo for studio documents. Commands carry their before and after values, so
//! reversing one needs no recomputation. A continuous gesture (a slider drag, a brush stroke)
//! merges into one entry through the command's own `coalesce`. Fixed capacity: no allocation.
const std = @import("std");

/// `Command` must provide `pub fn coalesce(self: *Command, next: Command) bool`, which merges
/// `next` into `self` and returns true when both belong to the same gesture.
pub fn History(comptime Command: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        items: [capacity]Command = undefined,
        /// Entries that exist; `cursor` of them are applied and the rest are redo.
        len: usize = 0,
        cursor: usize = 0,

        pub fn push(self: *Self, command: Command) void {
            self.len = self.cursor; // a new edit discards the redo tail
            if (self.cursor > 0 and self.items[self.cursor - 1].coalesce(command)) return;
            if (self.cursor == capacity) {
                std.mem.copyForwards(Command, self.items[0 .. capacity - 1], self.items[1..capacity]);
                self.cursor -= 1;
            }
            self.items[self.cursor] = command;
            self.cursor += 1;
            self.len = self.cursor;
        }

        /// The command to reverse, or null at the start of history.
        pub fn undo(self: *Self) ?Command {
            if (self.cursor == 0) return null;
            self.cursor -= 1;
            return self.items[self.cursor];
        }

        /// The command to re-apply, or null at the end of history.
        pub fn redo(self: *Self) ?Command {
            if (self.cursor == self.len) return null;
            defer self.cursor += 1;
            return self.items[self.cursor];
        }
    };
}

const TestCommand = struct {
    gesture: u32,
    before: f32,
    after: f32,
    pub fn coalesce(self: *TestCommand, next: TestCommand) bool {
        if (self.gesture != next.gesture) return false;
        self.after = next.after;
        return true;
    }
};

test "history undoes, redoes, merges a gesture into one entry and drops the redo tail" {
    var history: History(TestCommand, 4) = .{};
    history.push(.{ .gesture = 1, .before = 0, .after = 1 });
    history.push(.{ .gesture = 1, .before = 1, .after = 2 }); // same drag
    try std.testing.expectEqual(@as(usize, 1), history.cursor);
    const undone = history.undo().?;
    try std.testing.expectEqual(@as(f32, 2), undone.after);
    try std.testing.expectEqual(@as(f32, 0), undone.before); // the first before survives the merge
    try std.testing.expect(history.undo() == null);
    try std.testing.expect(history.redo() != null);
    _ = history.undo();
    history.push(.{ .gesture = 2, .before = 0, .after = 5 });
    try std.testing.expect(history.redo() == null); // the old redo entry is gone
    for (3..13) |g| history.push(.{ .gesture = @intCast(g), .before = 0, .after = 1 });
    try std.testing.expectEqual(@as(usize, 4), history.len); // bounded: the oldest are dropped
}
