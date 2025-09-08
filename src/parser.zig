const std = @import("std");
const lexer = @import("lexer.zig");
const root = @import("root.zig");
const Diagnostics = root.Diagnostics;
const TokenKind = lexer.TokenKind;
const TokenData = lexer.TokenData;
const Token = lexer.Token;

pub const Node = struct { token: ?Token = null, value: NodeValue };

pub const NodeValue = union(enum) {
    function_decl: struct { mods: packed struct { public: bool, constant: bool, misc: u6 }, name: Token, params: []Node, return_type: *Node, body: *Node },
    function_param: struct {
        name: Token,
        type: *Node,
    },
    function_invoke: struct {
        namespace: *Node,
        args: []Node,
    },
    body: struct { nodes: []Node },
    return_expr: *Node,

    namespace: struct {
        tokens: []Token,
    },
    binary_op: struct {
        op: BinaryOperation,
        lhs: *Node,
        rhs: *Node,
    },
    unary_op: struct {
        op: UnaryOperation,
        rhs: *Node,
    },
    make_var: struct {
        name: Token,
        mods: packed struct {
            constant: bool = false,
        },
        /// Null if type is to be inferred.
        typ: ?*Node,
        value: *Node,
    },
    _if: struct {
        condition: *Node,
        /// Executed when condition is true
        if_true: *Node,
        /// Either another if, the else block, or nothing.
        if_false: ?*Node,
    },

    // literals
    integer: root.INTEGER,
    u_integer: root.U_INTEGER,
    float: root.FLOAT,
    char: root.FLOAT,
    string: TokenData,
};

pub const UnaryOperation = enum { negate };

pub const BinaryOperation = enum {
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

pub const Parser = struct {
    // Parameters
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []Token,

    // State
    i: usize = 0,
    diagnostics: Diagnostics = .{},

    fn peek(self: *Parser) !TokenKind {
        return if (self.i < self.tokens.len) self.tokens[self.i].kind else Error.UnexpectedEndOfFile;
    }

    fn consume(self: *Parser, kind: TokenKind) !Token {
        if (self.i >= self.tokens.len) return Error.UnexpectedEndOfFile;
        const token = self.tokens[self.i];
        std.log.info("Try consume '{s}'", .{@tagName(kind)});
        if (token.kind == kind) {
            self.i += 1;
            return token;
        } else {
            self.diagnostics.err = .{ .error_type = Error.UnexpectedToken, .data = .{ .u = @intFromEnum(kind) } };
            return Error.UnexpectedToken;
        }
    }

    pub fn parse(self: *Parser) !*Node {
        self.i = 0;

        return body(self) catch |e| {
            switch (e) {
                Error.UnexpectedToken => try handleUnexpectedToken(self),
                else => {},
            }
            return e;
        };
    }

    pub const Error = error{
        UnexpectedToken,
        UnexpectedEndOfFile,
    };
};

fn handleUnexpectedToken(self: *Parser) !void {
    const token = self.tokens[self.i];
    const kind = @as(TokenKind, @enumFromInt(self.diagnostics.err.?.data.?.u));
    std.log.err("Expected '{s}', but got '{s}'\n", .{ @tagName(kind), @tagName(token.kind) });
    const back_dist = 3;
    const forward_dist = 3;
    const min = if (self.i < back_dist) self.i else self.i - back_dist;
    const max = if (self.tokens.len < forward_dist) self.tokens.len - 1 else self.i + forward_dist + 1;
    for (self.tokens[min..max], 0..) |tok, i| {
        if (min + i == self.i) {
            std.log.err("// Wanted '{s}' here.", .{@tagName(kind)});
            std.log.err("---> {s} <---, ", .{@tagName(tok.kind)});
        } else std.log.err("{s}, ", .{@tagName(tok.kind)});
    }
    const first_token = self.tokens[min - 1];
    const start_source_offset = first_token.source_data.index;
    const last_token = self.tokens[max];
    const last_source_offset = last_token.source_data.index;
    std.debug.print("=--\n", .{});

    try writeSource(self.source[start_source_offset..last_source_offset], first_token.source_data.line);
    std.debug.print("=--\n", .{});
}

fn writeSource(source: []const u8, line_start: usize) !void {
    var buf: [64]u8 = undefined;
    const w = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();

    var line = line_start + 1;
    try w.print("{any: >3}: ", .{ line - 1 });
    for (source) |c| {
        try w.printAsciiChar(c, .{});

        if (std.ascii.isWhitespace(c) and c != ' ') {
            try w.print("{any: >3}: ", .{ line });
            line += 1;
        }
    }

    try w.writeByte('\n');
}

fn statement(self: *Parser) !*Node {
    std.debug.print("parsing statement\n", .{});
    const p = try self.peek();
    switch (p) {
        .keyword_const, .keyword_pub, .keyword_fn => {
            return function(self);
        },
        .keyword_var => {
            const var_token = try self.consume(.keyword_var);
            var constant = false;
            switch (try self.peek()) {
                .keyword_const => {
                    _ = try self.consume(.keyword_const);
                    constant = true;
                },
                else => {},
            }
            const name = try self.consume(.identifier);
            var typ: ?*Node = null;
            if (try self.peek() == .colon) {
                _ = try self.consume(.colon);
                typ = try namespace(self);
            }
            _ = try self.consume(.equals);
            const e = try expr(self);
            return try allocNode(self, .{ .token = var_token, .value = .{ .make_var = .{ .name = name, .value = e, .typ = typ, .mods = .{
                .constant = constant,
            } } } });
        },
        .keyword_return => {
            const token = try self.consume(.keyword_return);
            return try allocNode(self, .{ .token = token, .value = .{ .return_expr = try expr(self) } });
        },
        .keyword_if => {
            return try if_statement(self);
        },
        else => {
            std.log.err("Unknown statement token '{s}'", .{@tagName(p)});
            return error.UnknownStatement;
            // return try expr(self);
        },
    }

    unreachable;
}

fn if_statement(self: *Parser) anyerror!*Node {
    std.debug.print("parsing if statement\n", .{});
    const if_token = switch (try self.peek()) {
        .keyword_elif => try self.consume(.keyword_elif),
        else => try self.consume(.keyword_if),
    };
    _ = try self.consume(.open_paren);
    const condition = try expr(self);
    _ = try self.consume(.close_paren);
    _ = try self.consume(.open_brace);
    const if_true = try body(self);
    _ = try self.consume(.close_brace);
    var if_false: ?*Node = null;
    switch (try self.peek()) {
        .keyword_elif => {
            if_false = try if_statement(self);
        },
        .keyword_else => {
            _ = try self.consume(.keyword_else);
            _ = try self.consume(.open_brace);
            if_false = try body(self);
            _ = try self.consume(.close_brace);
        },
        else => {},
    }
    return try allocNode(self, .{ .token = if_token, .value = .{ ._if = .{
        .condition = condition,
        .if_true = if_true,
        .if_false = if_false,
    } } });
}

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
            return try allocNode(self, .{ .token = token, .value = .{ .integer = token.data.integer } });
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
            return try allocNode(self, .{ .token = token, .value = .{ .unary_op = .{ .op = .negate, .rhs = node } } });
        },
        .identifier => {
            const ns = try namespace(self);
            if (try self.peek() == .open_paren) {
                // this is a function invocation, not field access.
                _ = try self.consume(.open_paren);
                const args = try arguments(self);
                _ = try self.consume(.close_paren);
                return try allocNode(self, .{ .value = .{ .function_invoke = .{
                    .namespace = ns,
                    .args = args,
                } } });
            } else {
                // just field access
                return ns;
            }
        },
        // idk
        else => {
            std.log.err("Unhandled factor kind {s}\n", .{@tagName(kind)});
            @panic("");
        },
    }
}

fn arguments(self: *Parser) ![]Node {
    std.debug.print("parsing arguments\n", .{});
    // if there are no expressions
    if (try self.peek() == .close_paren) return &[0]Node{};

    var args = try std.ArrayList(Node).initCapacity(self.allocator, 4);

    const first = try expr(self);
    (try args.addOne(self.allocator)).* = first.*;
    self.allocator.destroy(first);

    while (try self.peek() == .comma) {
        _ = try self.consume(.comma);
        const a = try expr(self);
        (try args.addOne(self.allocator)).* = a.*;
        self.allocator.destroy(a);
    }

    return try args.toOwnedSlice(self.allocator);
}

fn function(self: *Parser) !*Node {
    std.debug.print("parsing function\n", .{});
    var public = false;
    var constant = false;

    switch (try self.peek()) {
        .keyword_const => {
            if (constant) return error.UnexpectedConstModifier;
            constant = true;
            _ = try self.consume(.keyword_const);
        },
        .keyword_pub => {
            if (public) return error.UnexpectedPubModifier;
            public = true;
            _ = try self.consume(.keyword_pub);
        },
        .keyword_fn => {},
        else => return error.UnexpectedToken,
    }

    // assert fn
    _ = try self.consume(.keyword_fn);

    // read name
    const name = try self.consume(.identifier);

    // read params
    _ = try self.consume(.open_paren);
    const params = try parameters(self);
    _ = try self.consume(.close_paren);

    //read return type
    _ = try self.consume(.right_arrow);
    const ret_type = try namespace(self);

    var body_node: *Node = undefined;
    // handle expr body
    if (try self.peek() == .equals) {
        _ = try self.consume(.equals);
        body_node = try expr(self);
    } else {
        // read usual body
        _ = try self.consume(.open_brace);
        body_node = try body(self);
        _ = try self.consume(.close_brace);
    }

    std.debug.print("Returned function '{s}'\n", .{name.data.string.slice});
    return try allocNode(self, .{ .value = .{ .function_decl = .{ .name = name, .mods = .{ .public = public, .constant = constant, .misc = 0 }, .params = params, .return_type = ret_type, .body = body_node } } });
}

fn body(self: *Parser) !*Node {
    std.debug.print("parsing body\n", .{});
    if (try self.peek() == .close_brace) return try allocNode(self, .{ .value = .{ .body = .{ .nodes = &[0]Node{} } } });

    var node_list = try std.ArrayList(Node).initCapacity(self.allocator, 4);

    const first = try statement(self);
    try node_list.append(self.allocator, first.*);
    self.allocator.destroy(first);

    while (self.i + 1 < self.tokens.len and try self.peek() == .semicolon) {
        _ = try self.consume(.semicolon);
        if (try self.peek() == .close_brace) break;
        const i = try statement(self);
        try node_list.append(self.allocator, i.*);
        self.allocator.destroy(i);
    }

    const nodes = try self.allocator.alloc(Node, node_list.items.len);
    @memmove(nodes, node_list.items);
    node_list.deinit(self.allocator);
    return try allocNode(self, .{ .value = .{ .body = .{ .nodes = nodes } } });
}

/// Gathers all consecutive identifiers delimited by periods.
fn namespace(self: *Parser) !*Node {
    std.debug.print("parsing namespace\n", .{});
    var ns = try std.ArrayList(Token).initCapacity(self.allocator, 4);
    const first = try self.consume(.identifier);
    try ns.append(self.allocator, first);

    while (try self.peek() == .period) {
        _ = try self.consume(.period);
        const i = try self.consume(.identifier);
        try ns.append(self.allocator, i);
    }

    const tokens = try self.allocator.alloc(Token, ns.items.len);
    @memmove(tokens, ns.items);
    ns.deinit(self.allocator);
    return try allocNode(self, .{ .value = .{ .namespace = .{ .tokens = tokens } } });
}

/// Reads all consecutive parameters delimited by commas.
/// Slice is allocated on the heap.
fn parameters(self: *Parser) ![]Node {
    std.debug.print("parsing parameters\n", .{});
    if (try self.peek() == .close_paren) return &[0]Node{};

    var params = try std.ArrayList(Node).initCapacity(self.allocator, 4);

    const first = try parameter(self);
    try params.append(self.allocator, first);

    while (try self.peek() == .comma) {
        _ = try self.consume(.comma);
        const p = try parameter(self);
        try params.append(self.allocator, p);
    }

    const param_slice = try self.allocator.alloc(Node, params.items.len);
    @memmove(param_slice, params.items);
    params.deinit(self.allocator);
    return param_slice;
}

fn parameter(self: *Parser) !Node {
    const name = try self.consume(.identifier);
    _ = try self.consume(.colon);
    const t = try namespace(self);
    return Node{ .value = .{ .function_param = .{
        .name = name,
        .type = t,
    } } };
}

fn term(self: *Parser) !*Node {
    var node_ptr = try factor(self);
    var peeked = try self.peek();

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_mul => .mul,
            .operator_div => .div,
            else => break,
        };

        const op = try self.consume(peeked);

        const lhs = node_ptr;
        const rhs = try factor(self);
        node_ptr = try allocNode(self, .{ .token = op, .value = .{ .binary_op = .{
            .lhs = lhs,
            .op = op_kind,
            .rhs = rhs,
        } } });

        peeked = try self.peek();
    }

    return node_ptr;
}

fn expr(self: *Parser) anyerror!*Node {
    std.debug.print("parsing expression\n", .{});
    var node_ptr = try term(self);
    var peeked = try self.peek();

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_add => .add,
            .operator_sub => .sub,
            .greater_than => .gt,
            .less_than => .lt,
            else => break,
        };

        const op = try self.consume(peeked);

        const lhs = node_ptr;
        const rhs = try term(self);
        node_ptr = try allocNode(self, .{ .token = op, .value = .{ .binary_op = .{
            .lhs = lhs,
            .op = op_kind,
            .rhs = rhs,
        } } });

        peeked = try self.peek();
    }

    return node_ptr;
}
