pub const Id = u16;
pub const Node = union(enum) {
    constant: f32,
    add: struct { a: Id, b: Id },
    multiply: struct { a: Id, b: Id },
    greater: struct { a: Id, b: Id },
};
