const std = @import("std");
const Node = @import("Node.zig").Node;
const Id = @import("Node.zig").Id;
const Graph = @This();
pub const capacity = 128;
nodes: [capacity]Node = undefined,
values: [capacity]f32 = @splat(0),
len: u16 = 0,

/// Append order is evaluation order. Only earlier nodes can be referenced, excluding cycles.
pub fn append(self: *Graph, node: Node) !Id {
    if (self.len == capacity) return error.GraphFull;
    switch (node) {
        .constant => |v| if (!std.math.isFinite(v)) return error.InvalidValue,
        inline else => |inputs| if (inputs.a >= self.len or inputs.b >= self.len) return error.InvalidReference,
    }
    const id = self.len;
    self.nodes[id] = node;
    self.len += 1;
    return id;
}

pub fn evaluate(self: *Graph) void {
    for (self.nodes[0..self.len], 0..) |node, i| {
        self.values[i] = switch (node) {
            .constant => |v| v,
            .add => |n| self.values[n.a] + self.values[n.b],
            .multiply => |n| self.values[n.a] * self.values[n.b],
            .greater => |n| if (self.values[n.a] > self.values[n.b]) 1 else 0,
        };
    }
}

test "signal graph evaluates in order and rejects cycles and capacity overflow" {
    var graph: Graph = .{};
    try std.testing.expectError(error.InvalidReference, graph.append(.{ .add = .{ .a = 0, .b = 0 } }));
    const a = try graph.append(.{ .constant = 3 });
    const b = try graph.append(.{ .constant = 4 });
    const sum = try graph.append(.{ .add = .{ .a = a, .b = b } });
    const product = try graph.append(.{ .multiply = .{ .a = sum, .b = b } });
    graph.evaluate();
    try std.testing.expectEqual(@as(f32, 28), graph.values[product]);
    while (graph.len < capacity) _ = try graph.append(.{ .constant = 0 });
    try std.testing.expectError(error.GraphFull, graph.append(.{ .constant = 0 }));
}
