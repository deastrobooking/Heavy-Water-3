/// CPU-only signal foundation. Physical ports, persistence and construction are later milestones.
pub const Graph = @import("Graph.zig");
graph: Graph = .{},

pub fn step(self: *@This()) void {
    self.graph.evaluate();
}
