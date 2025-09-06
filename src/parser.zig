const std = @import("std");
const lexer = @import("lexer.zig");
const root = @import("root.zig");
const Diagnostics = root.Diagnostics;
const TokenKind = lexer.TokenKind;
const TokenData = lexer.TokenData;
const Token = lexer.Token;

pub const Node = struct {
    token: ?Token = null,
    value: NodeValue
};

pub const NodeValue = union(enum) {
    function_decl: struct {
        mods: packed struct {
            public: bool,
            constant: bool,
            misc: u6
        },
        name: *Node,
        params: *[]Node,
        return_type: *Node,
        body: *[]Node
    },

    binary_op: struct {
        op: BinaryOperation,
        lhs: *Node,
        rhs: *Node,
    },
    qualifier_op: struct {
        post: *Node,
    },
    unary_op: struct {
        op: UnaryOperation,
        rhs: *Node,
    },

    variable: root.STRING,

    // literals
    integer: root.INTEGER,
    u_integer: root.U_INTEGER,
    float: root.FLOAT,
    char: root.FLOAT,
    string: TokenData,
};

pub const UnaryOperation = enum { negate };

pub const BinaryOperation = enum { add, sub, mul, div };

pub const Parser = struct {
    // Parameters
    allocator: std.mem.Allocator,
    source: []Token,

    // State
    i: usize = 0,

    fn peek(self: *Parser) !TokenKind {
        return if (self.i < self.source.len) self.source[self.i].kind
        else error.EOF;
    }

    fn consume(self: *Parser, kind: TokenKind) !Token {
        if (self.i >= self.source.len) return error.EOF;
        const token = self.source[self.i];
        self.i += 1;
        std.log.info("Consumed kind {s}", .{ @tagName(kind) });
        return if (token.kind == kind) token
        else b: {
                std.log.err("Unexpected token '{s}'\n", .{ @tagName(token.kind) });
                break :b error.UnexpectedToken;
            };
    }

    pub fn parse(self: *Parser) !*Node {
        self.i = 0;

        return expr(self);
    }
};

fn allocNode(self: *Parser, node: Node) !*Node {
    const node_ptr = try self.allocator.create(Node);
    node_ptr.* = node;
    return node_ptr;
}

fn factor(self: *Parser) !*Node {
    const kind = try self.peek();
    switch (kind) {
        .literal_integer => {
            const token = try self.consume(.literal_integer);
            return try allocNode(self, .{
                .token = token,
                .value = .{ .integer = token.data.integer }
            });
        },
        .open_paren => {
            _ = try self.consume(.open_paren);
            const node = try expr(self);
            _ = try self.consume(.close_paren);
            return node;
        },
        .operator_sub => {
            const token = try self.consume(.operator_sub);
            const node = try factor(self);
            return try allocNode(self, .{
                .token = token,
                .value = .{ .unary_op = .{
                    .op = .negate,
                    .rhs = node
                }}
            });
        },
        .identifier => {
            const token = try self.consume(.identifier);
            return try allocNode(self, .{
                .token = token,
                .value = .{ .variable = token.data.source_string }
            });
        },
        .keyword_const,
        .keyword_pub => {

        },
        // idk
        else => {
            std.log.err("Unhandled factor kind {s}\n", .{ @tagName(kind) });
            @panic("");
        }
    }
}

fn functionModifiers(self: *Parser) !?TokenKind {

}

fn term(self: *Parser) !*Node {
    var node_ptr = try factor(self);
    var peeked = try self.peek();

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_mul => .mul,
            .operator_div => .div,
            else => break
        };

        _ = try self.consume(peeked);

        const lhs = node_ptr;
        const rhs = try factor(self);
        node_ptr = try allocNode(self, .{
            .token = null,
            .value = .{
                .binary_op = .{
                    .lhs = lhs,
                    .op = op_kind,
                    .rhs = rhs,
                }
            }
        });

        peeked = try self.peek();
    }

    return node_ptr;
}

fn expr(self: *Parser) anyerror!*Node {
    var node_ptr = try term(self);
    var peeked = try self.peek();

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_add => .add,
            .operator_sub => .sub,
            else => break
        };

        _ = try self.consume(peeked);

        const lhs = node_ptr;
        const rhs = try term(self);
        node_ptr = try allocNode(self, .{
            .token = null,
            .value = .{
                .binary_op = .{
                    .lhs = lhs,
                    .op = op_kind,
                    .rhs = rhs,
                }
            }
        });

        peeked = try self.peek();
    }

    return node_ptr;
}

fn decl(self: *Parser) !*Node {

}