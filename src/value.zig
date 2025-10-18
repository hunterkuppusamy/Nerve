const std = @import("std");
const Type = @import("type.zig").Type;
const Node = @import("AST.zig").Node;

pub const Value = struct {
    type: *const Type,
    data: union(enum) {
        /// Fields
        @"struct": []const Value,
        /// ref?
        @"fn": usize,
        /// ? Something ?
        @"extern": usize,
        int: i32,
        float: f32,
    }
};