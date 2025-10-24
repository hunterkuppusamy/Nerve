const std = @import("std");
const LineInfo = @import("LineInfo.zig");

pub const Node = union(enum) {
    declare: Declare,
    lazy_import: LazyImport,
    get: Get,

    access: Access,
    invoke: Invoke, // Access (the function) -> Invoke (the accessed function)

    pub const Get = struct {
        line: LineInfo,
        scope: enum { local, static },
        name: []const u8,
    };

    pub const Invoke = struct {
        line: LineInfo,
        lhs: *Node, // the function
        args: []Node, // the arguments
        return_type: *Node, // the return type
    };

    pub const Access = struct {
        line: LineInfo,
        lhs: *Node,
        name: []const u8, // field name
        return_type: *Node,
    };

    pub const LazyImport = struct {
        line: LineInfo,
        qualified_name: []const u8,
    };

    pub const TypeRef = union(enum) {
        local: *Node,
        static: *Node,
        type: Type,
        fun: Fun,

        pub const Type = struct {
            line: LineInfo,
            decls: []Declare
        };

        pub const Fun = struct {
            line: LineInfo,
            params: []Param,
            return_type: *TypeRef,
            body: []Node,

            pub const Param = struct {
                name: []const u8,
                type: *TypeRef,
            };
        };
    };

    pub const Declare = struct {
        line: LineInfo,
        name: []const u8,
        thing: TypeRef,
    };

    pub fn lineInfo(self: *Node) LineInfo {
        const tag = @as(std.meta.Tag(Node), self.*);
        return tag.line;
    }
};