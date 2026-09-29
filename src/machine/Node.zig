pub const Id = u16;
/// `input` reads a controller input port (0..max_inputs-1); other nodes read earlier nodes.
pub const max_inputs = 4;
pub const Node = union(enum) {
    constant: f32,
    input: u8,
    add: struct { a: Id, b: Id },
    multiply: struct { a: Id, b: Id },
    greater: struct { a: Id, b: Id },
};
