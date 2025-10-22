const std = @import("std");
const BinaryOperation = @import("parser.zig").BinaryOperation;
const UnaryOperation = @import("parser.zig").UnaryOperation;
const root = @import("root");
const Type = @import("type.zig").Type;

/// Just use arena for all allocations...
///
/// ```
/// var const String = [import]("java/lang/String");
/// var pub const MyType = type {
///     var int = 1;
///     var main = fn(args: String)->void {
///
///     };
///     var fifteen = fn(int:Int)->Int = int + 15;
/// };
/// ```
pub const Node = union(enum) {
    type_decl: TypeDecl,
    field_access: FieldAccess,
    fn_decl: FnDecl,
    fn_invoke: FnInvoke,
    body: Body,
    array_of: ArrayOf,
    @"return": ?*Node,

    binary_op: BinaryOp,
    unary_op: UnaryOp,
    @"var": VarDecl,
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
    byte: struct {
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

    pub fn lineinfo(self: *Node) LineInfo {
        return switch (self.*) {
            .type_decl => |n| n.loc,
            .field_access => |n| n.loc,
            .fn_decl => |n| n.loc,
            .fn_invoke => |n| n.loc,
            .body => |n| n.loc,
            .@"return" => |n| (n orelse return LineInfo{}).lineinfo(),
            .binary_op => |n| n.loc,
            .unary_op => |n| n.loc,
            .@"var" => |n| n.loc,
            .@"if" => |n| n.loc,
            .integer => |n| n.loc,
            .float => |n| n.loc,
            .u_integer => |n| n.loc,
            .byte => |n| n.loc,
            .bool => |n| n.loc,
            .string => |n| n.loc,
            .array_of => |n| n.loc,
        };
    }

    pub const TypeDecl = struct {
        loc: LineInfo,
        fields: []const Node,
    };

    pub const ArrayOf = struct {
        loc: LineInfo,
        element_type: *Node,
    };

    //
    // pub const Namespace = struct {
    //     loc: LineInfo,
    //     data: []const []const u8,
    //
    //     pub fn fullName(self: *const @This(), alloc: std.mem.Allocator) ![]const u8 {
    //         var buf = try std.ArrayList(u8).initCapacity(alloc, 32);
    //         for (self.data, 0..) |p, i| {
    //             try buf.appendSlice(alloc, p);
    //             if (i < self.data.len - 1) try buf.append(alloc, '.');
    //         }
    //         return try buf.toOwnedSlice(alloc);
    //     }
    // };

    pub const If = struct {
        loc: LineInfo,
        condition: *Node,
        branch_true: *Node,
        branch_false: ?*Node,
    };

    pub const VarDecl = struct {
        loc: LineInfo,
        scope: Scope,
        name: []const u8,
        mods: packed struct {
            public: bool,
            constant: bool,
            static: bool,
        },
        /// Null if type is to be inferred.
        /// Can either be a declared variable or a type declared right here.
        type: ?*Node,
        value: *Node,

        /// Local variables cannot be public.
        pub const Scope = enum { file, type, local };
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
        nodes: []const Node,
    };

    /// If instance is null, the access is local.
    pub const FieldAccess = struct {
        loc: LineInfo,
        builtin: bool,
        instance: ?*Node,
        name: []const u8,
    };

    // No idea what a null instance here would mean. Local function eventually probably.
    pub const FnInvoke = struct {
        loc: LineInfo,
        builtin: bool,
        instance: ?*Node,
        name: []const u8,
        args: []Node,
    };

    pub const FnDecl = struct {
        loc: LineInfo,
        params: []const Param,
        return_type: *Node,
        body: *Node,

        pub const Param = struct {
            loc: LineInfo,
            name: []const u8,
            type: *Node,
        };
    };

    pub const LineInfo = struct {
        src_start_ndx: usize = 0,
        src_end_ndx: usize = 0,
        /// If multiple lines, use the first line of appearance
        line: usize = 0,
    };

    fn printIndents(indents: isize) void {
        const v = if (indents < 0) 0 else indents;
        for (0..std.math.cast(usize, v).?) |_| {
            std.debug.print("  ", .{});
        }
    }

    pub fn print(node: *const Node, indents: isize) void {
        switch (node.*) {
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
                for (fun.params) |p| {
                    std.debug.print("{s}: ", .{p.name});
                    p.type.print(indents);
                }
                std.debug.print(") -> ", .{});
                fun.return_type.print(indents);
                if (fun.body.* != Node.body) {
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
                (node.@"return" orelse return).print(indents);
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
                std.debug.print("{s}(", .{ f.name });
                for (f.args) |a| {
                    a.print(indents);
                }
                std.debug.print(")", .{});
            },
            .float => std.debug.print("{any}", .{node.float}),
            .integer => std.debug.print("{any}", .{node.integer}),
            else => std.debug.print("|{any}|", .{node}),
        }
    }
};