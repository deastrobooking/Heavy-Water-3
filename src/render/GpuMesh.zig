const gpu = @import("mach").gpu;
const Mesh = @import("Mesh.zig");
const GpuMesh = @This();
vertices: *gpu.Buffer,
indices: *gpu.Buffer,
vertex_bytes: usize,
index_count: u32,

pub fn allocate(device: *gpu.Device, vertex_count: usize, index_count: usize) GpuMesh {
    return .{
        .vertices = device.createBuffer(&.{ .label = "chunk vertices", .size = vertex_count * @sizeOf(Mesh.Vertex), .usage = .{ .vertex = true, .copy_dst = true } }),
        .indices = device.createBuffer(&.{ .label = "chunk indices", .size = index_count * 4, .usage = .{ .index = true, .copy_dst = true } }),
        .vertex_bytes = vertex_count * @sizeOf(Mesh.Vertex),
        .index_count = @intCast(index_count),
    };
}

pub fn write(self: GpuMesh, queue: *gpu.Queue, mesh: Mesh) void {
    queue.writeBuffer(self.vertices, 0, mesh.vertices);
    queue.writeBuffer(self.indices, 0, mesh.indices);
}

pub fn upload(device: *gpu.Device, queue: *gpu.Queue, mesh: Mesh) GpuMesh {
    const vb = device.createBuffer(&.{ .label = "mesh vertices", .size = mesh.vertices.len * @sizeOf(Mesh.Vertex), .usage = .{ .vertex = true, .copy_dst = true } });
    const ib = device.createBuffer(&.{ .label = "mesh indices", .size = mesh.indices.len * 4, .usage = .{ .index = true, .copy_dst = true } });
    queue.writeBuffer(vb, 0, mesh.vertices);
    queue.writeBuffer(ib, 0, mesh.indices);
    return .{ .vertices = vb, .indices = ib, .vertex_bytes = mesh.vertices.len * @sizeOf(Mesh.Vertex), .index_count = @intCast(mesh.indices.len) };
}
pub fn draw(self: GpuMesh, pass: *gpu.RenderPassEncoder, instances: u32, first: u32) void {
    pass.setVertexBuffer(0, self.vertices, 0, self.vertex_bytes);
    pass.setIndexBuffer(self.indices, .uint32, 0, self.index_count * 4);
    pass.drawIndexed(self.index_count, instances, 0, 0, first);
}
pub fn deinit(self: GpuMesh) void {
    self.indices.release();
    self.vertices.release();
}
