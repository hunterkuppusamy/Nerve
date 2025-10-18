const std = @import("std");
const BinaryOperation = @import("parser.zig").BinaryOperation;
const UnaryOperation = @import("parser.zig").UnaryOperation;
const root = @import("root");
const Type = @import("type.zig").Type;

/// Just use arena for all allocations...
pub const Node = union(enum) {
    fn_decl: FnDecl,
    fn_invoke: FnInvoke,
    body: Body,
    @"return": ?*Node,

    namespace: Namespace,
    binary_op: BinaryOp,
    unary_op: UnaryOp,
    @"var": Var,
    @"if": If,

    // literals
    integer: struct {
        loc: LineInfo,
        data: i32
    },
    u_integer: struct {
        loc: LineInfo,
        data: u32
    },
    float: struct {
        loc: LineInfo,
        data: f32
    },
    char: struct {
        loc: LineInfo,
        data: u8
    },
    bool: struct {
        loc: LineInfo,
        data: bool
    },
    string: struct {
        loc: LineInfo,
        data: []const u8,
    },

    pub const Namespace = struct {
        loc: LineInfo,
        data: []const []const u8,

        pub fn fullName(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
            var buf = try std.ArrayList(u8).initCapacity(alloc, 32);
            for (self.data, 0..) |p, i| {
                try buf.appendSlice(alloc, p);
                if (i < self.data.len - 1) try buf.append(alloc, '.');
            }
            return try buf.toOwnedSlice(alloc);
        }
    };

    pub const If = struct {
        loc: LineInfo,
        condition: *Node,
        branch_true: *Node,
        branch_false: ?*Node,
    };

    pub const Var = struct {
        loc: LineInfo,
        name: []const u8,
        mods: packed struct {
            constant: bool = false,
        },
        /// Null if type is to be inferred.
        type: ?*Node,
        value: *Node,
    };

    pub const UnaryOp = struct {
        loc: LineInfo,
        op: Op,
        rhs: *Node,

        pub const Op = enum {
            negate,
        };
    };

    pub const BinaryOp = struct {
        loc: LineInfo,
        op: Op,
        lhs: *Node,
        rhs: *Node,

        pub const Op = enum {
            // zig fmt: align
            // Op | Op then assign
            add,
            adda,

            sub,
            suba,

            mul,
            mula,

            div,
            diva,

            lt,
            lte,
            gt,
            gte,
        };
    };

    pub const Body = struct {
        loc: LineInfo,
        nodes: []Node,
    };

    pub const FnInvoke = struct {
        loc: LineInfo,
        builtin: bool,
        namespace: *Node,
        args: []Node,
    };

    pub const FnDecl = struct {
        loc: LineInfo,
        mods: packed struct {
            public: bool,
            constant: bool,
        },
        name: []const u8,
        params: []const Param,
        return_type: *Type,
        body: *Node,

        pub const Param = struct {
            loc: LineInfo,
            name: []const u8,
            type: *Node,
        };
    };

    pub const LineInfo = struct {
        src_start_ndx: usize,
        src_end_ndx: usize,
        /// If multiple lines, use the first line of appearance
        line: usize,
    };

    fn printIndents(indents: isize) void {
        const v = if (indents < 0) 0 else indents;
        for (0..std.math.cast(usize, v).?) |_| {
            std.debug.print("  ", .{});
        }
    }

    pub fn print(node: *const Node, indents: isize) void {
        switch (node.value) {
            .binary_op => {
                node.binary_op.lhs.print(indents);
                const o = switch (node.binary_op.op) {
                    .add => "+",
                    .adda => "+=",
                    .sub => "-",
                    .suba => "-=",
                    .div => "/",
                    .diva => "/=",
                    .mul => "*",
                    .mula => "*=",

                    .gt => ">",
                    .gte => ">=",
                    .lt => "<",
                    .lte => "<=",
                //else => "???"
                };
                std.debug.print(" {s} ", .{o});
                node.binary_op.rhs.print(indents);
            },
            .unary_op => {
                const o: u8 = switch (node.unary_op.op) {
                    .negate => '-',
                };
                std.debug.print("{c}", .{o});
                node.unary_op.rhs.print(indents);
            },
            .@"var" => {
                printIndents(indents);
                const make = node.@"var";
                std.debug.print("var ", .{});
                if (make.mods.constant) {
                    std.debug.print("const ", .{});
                }
                std.debug.print("{s}", .{make.name});
                if (make.type != null) {
                    std.debug.print(": ", .{});
                    make.type.?.print(indents);
                } else {
                    std.debug.print(": ?", .{});
                }
                std.debug.print(" = ", .{});
                make.value.print(indents);
            },
            .fn_decl => {
                printIndents(indents);
                const fun = node.fn_decl;
                if (fun.mods.public) {
                    std.debug.print("pub ", .{});
                }
                if (fun.mods.constant) {
                    std.debug.print("const ", .{});
                }
                std.debug.print("fn {s}(", .{fun.name.data.string.slice});
                for (fun.params) |p| {
                    std.debug.print("{s}: ", .{p.name});
                    p.type.print(indents);
                }
                std.debug.print(") -> ", .{});
                fun.return_type.print(indents);
                if (fun.body != Node.body) {
                    std.debug.print(" = ", .{});
                    fun.body.print(indents);
                    return;
                }
                std.debug.print(" {{", .{});
                fun.body.print(indents);
                std.debug.print("\n", .{});
                printIndents(indents);
                std.debug.print("}}", .{});
            },
            .@"return" => {
                printIndents(indents);
                std.debug.print("return ", .{});
                node.@"return".print(indents);
            },
            .body => {
                printIndents(indents);
                const bod = node.body;
                std.debug.print("\n", .{});
                for (bod.nodes, 0..) |n, i| {
                    n.print(indents + 1);
                    if (bod.nodes.len - 1 == i) {
                        std.debug.print(";", .{});
                    } else {
                        std.debug.print(";\n", .{});
                    }
                }
            },
            .@"if" => {
                printIndents(indents);
                const _if = node.@"if";
                std.debug.print("if (", .{});
                _if.condition.print(indents + 1);
                std.debug.print(") {{", .{});
                _if.branch_true.print(indents);
                std.debug.print("\n", .{});
                printIndents(indents);
                std.debug.print("}}", .{});
                if (_if.branch_false == null) return;
                std.debug.print(" else ", .{});
                if (_if.branch_false.?.* == Node.body) {
                    std.debug.print("{{", .{});
                    _if.branch_false.?.print(indents);
                    std.debug.print("\n", .{});
                    printIndents(indents);
                    std.debug.print("}}", .{});
                } else {
                    _if.branch_false.?.print(indents);
                }
            },
            .fn_invoke => {
                const f = node.fn_invoke;
                f.namespace.print(indents);
                std.debug.print("(", .{});
                for (f.args) |a| {
                    a.print(indents);
                }
                std.debug.print(")", .{});
            },
            .namespace => {
                for (node.namespace.data, 0..) |tok, i| {
                    if (i + 1 >= node.namespace.data.len) {
                        std.debug.print("{s}", .{tok});
                    } else std.debug.print("{s}.", .{tok});
                }
            },
            .float => std.debug.print("{any}", .{node.float}),
            .integer => std.debug.print("{any}", .{node.integer}),
            else => std.debug.print("|{any}|", .{node}),
        }
    }
};