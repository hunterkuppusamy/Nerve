const std = @import("std");
const BinaryOperation = @import("parser.zig").BinaryOperation;
const UnaryOperation = @import("parser.zig").UnaryOperation;
const root = @import("root");
const Type = @import("type.zig").Type;

pub const Location = @import("notification.zig").Location;

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
    integer: struct { loc: Location = .{}, data: i32 },
    u_integer: struct { loc: Location = .{}, data: u32 },
    float: struct { loc: Location = .{}, data: f32 },
    byte: struct { loc: Location = .{}, data: u8 },
    bool: struct { loc: Location = .{}, data: bool },
    string: struct { loc: Location = .{}, data: []const u8 },

    pub fn location(self: *const Node) Location {
        return switch (self.*) {
            .type_decl => |n| n.loc,
            .field_access => |n| n.loc,
            .fn_decl => |n| n.loc,
            .fn_invoke => |n| n.loc,
            .body => |n| n.loc,
            .@"return" => |n| if (n) |inner| inner.location() else .{},
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
        loc: Location = .{},
        fields: []const Node,
    };

    pub const ArrayOf = struct {
        loc: Location = .{},
        element_type: *Node,
    };

    pub const If = struct {
        loc: Location = .{},
        condition: *Node,
        branch_true: *Node,
        branch_false: ?*Node,
    };

    pub const VarDecl = struct {
        loc: Location = .{},
        scope: Scope,
        name: []const u8,
        mods: packed struct {
            public: bool,
            constant: bool,
            static: bool,
        },
        type: ?*Node,
        value: *Node,

        pub const Scope = enum { file, type, local };
    };

    pub const UnaryOp = struct {
        loc: Location = .{},
        op: Op,
        rhs: *Node,

        pub const Op = enum {
            negate,
        };
    };

    pub const BinaryOp = struct {
        loc: Location = .{},
        op: Op,
        lhs: *Node,
        rhs: *Node,

        pub const Op = enum {
            add, adda,
            sub, suba,
            mul, mula,
            div, diva,
            lt, lte,
            gt, gte,
        };
    };

    pub const Body = struct {
        loc: Location = .{},
        nodes: []const Node,
    };

    pub const FieldAccess = struct {
        loc: Location = .{},
        builtin: bool,
        instance: ?*Node,
        name: []const u8,
    };

    pub const FnInvoke = struct {
        loc: Location = .{},
        builtin: bool,
        instance: ?*Node,
        name: []const u8,
        args: []Node,
    };

    pub const FnDecl = struct {
        loc: Location = .{},
        params: []const Param,
        return_type: *Node,
        body: *Node,

        pub const Param = struct {
            loc: Location = .{},
            name: []const u8,
            type: *Node,
        };
    };

    fn printIndents(indents: isize) void {
        const v = if (indents < 0) 0 else indents;
        for (0..std.math.cast(usize, v).?) |_| {
            std.debug.print("  ", .{});
        }
    }

    pub fn print(self: *const Node, indents: isize) void {
        switch (self.*) {
            .type_decl => |td| {
                printIndents(indents);
                std.debug.print("type_decl:\n", .{});
                for (td.fields) |field| {
                    field.print(indents + 1);
                }
            },
            .field_access => |fa| {
                printIndents(indents);
                std.debug.print("field_access: {s}\n", .{fa.name});
                if (fa.instance) |inst| {
                    inst.print(indents + 1);
                }
            },
            .fn_decl => |fd| {
                printIndents(indents);
                std.debug.print("fn_decl:\n", .{});
                fd.body.print(indents + 1);
            },
            .fn_invoke => |fi| {
                printIndents(indents);
                std.debug.print("fn_invoke: {s}\n", .{fi.name});
            },
            .@"var" => |v| {
                printIndents(indents);
                std.debug.print("var: {s}\n", .{v.name});
                v.value.print(indents + 1);
            },
            .integer => |i| {
                printIndents(indents);
                std.debug.print("integer: {d}\n", .{i.data});
            },
            .float => |f| {
                printIndents(indents);
                std.debug.print("float: {d}\n", .{f.data});
            },
            .string => |s| {
                printIndents(indents);
                std.debug.print("string: \"{s}\"\n", .{s.data});
            },
            .@"return" => |r| {
                printIndents(indents);
                std.debug.print("return\n", .{});
                if (r) |inner| inner.print(indents + 1);
            },
            .body => |b| {
                for (b.nodes) |n| {
                    const n_ptr = &n;
                    n_ptr.print(indents);
                }
            },
            else => {
                printIndents(indents);
                std.debug.print("{s}\n", .{@tagName(self.*)});
            },
        }
    }
};
