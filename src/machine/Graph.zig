const std = @import("std");
const Node = @import("Node.zig").Node;
const Id = @import("Node.zig").Id;
const max_inputs = @import("Node.zig").max_inputs;
const Graph = @This();
pub const capacity = 128;
nodes: [capacity]Node = undefined,
values: [capacity]f32 = @splat(0),
len: u16 = 0,

/// Append order is evaluation order. Only earlier nodes can be referenced, excluding cycles.
pub fn append(self: *Graph, node: Node) !Id {
    if (self.len == capacity) return error.GraphFull;
    try check(node, self.len);
    const id = self.len;
    self.nodes[id] = node;
    self.len += 1;
    return id;
}

/// Validates one node at position `at` of a node list.
pub fn check(node: Node, at: usize) error{ InvalidValue, InvalidReference, InvalidInput }!void {
    switch (node) {
        .constant => |v| if (!std.math.isFinite(v)) return error.InvalidValue,
        .input => |i| if (i >= max_inputs) return error.InvalidInput,
        inline else => |inputs| if (inputs.a >= at or inputs.b >= at) return error.InvalidReference,
    }
}

pub fn validate(nodes: []const Node) !void {
    for (nodes, 0..) |node, i| try check(node, i);
}

pub fn evaluate(self: *Graph, inputs: []const f32) void {
    evaluateNodes(self.nodes[0..self.len], self.values[0..self.len], inputs);
}

/// Allocation-free evaluation of a validated node list into caller storage.
pub fn evaluateNodes(nodes: []const Node, values: []f32, inputs: []const f32) void {
    for (nodes, 0..) |node, i| {
        values[i] = switch (node) {
            .constant => |v| v,
            .input => |n| if (n < inputs.len) inputs[n] else 0,
            .add => |n| values[n.a] + values[n.b],
            .multiply => |n| values[n.a] * values[n.b],
            .greater => |n| if (values[n.a] > values[n.b]) 1 else 0,
        };
    }
}

test "signal graph evaluates in order and rejects cycles, bad inputs, and capacity overflow" {
    var graph: Graph = .{};
    try std.testing.expectError(error.InvalidReference, graph.append(.{ .add = .{ .a = 0, .b = 0 } }));
    try std.testing.expectError(error.InvalidInput, graph.append(.{ .input = max_inputs }));
    const a = try graph.append(.{ .input = 1 });
    const b = try graph.append(.{ .constant = 4 });
    const sum = try graph.append(.{ .add = .{ .a = a, .b = b } });
    const product = try graph.append(.{ .multiply = .{ .a = sum, .b = b } });
    graph.evaluate(&.{ 0, 3 });
    try std.testing.expectEqual(@as(f32, 28), graph.values[product]);
    while (graph.len < capacity) _ = try graph.append(.{ .constant = 0 });
    try std.testing.expectError(error.GraphFull, graph.append(.{ .constant = 0 }));
}
