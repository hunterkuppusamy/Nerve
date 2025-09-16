const std = @import("std");
const lexer = @import("lexer.zig");
const root = @import("root.zig");
const expect = std.testing.expect;
const Diagnostics = root.Diagnostics;
const TokenKind = lexer.TokenKind;
const TokenData = lexer.TokenData;
const Token = lexer.Token;

pub const Node = struct {
    token: ?Token = null,
    value: NodeValue,

    pub fn destroy(self: *const Node, alloc: std.mem.Allocator) void {
        std.debug.print("Switching '", .{});
        self.print(0);
        std.debug.print("'\n", .{});
        switch (self.value) {
            .fn_decl => {
                const f = self.value.fn_decl;
                for (f.params) |node| {
                    node.destroy(alloc);
                }
                alloc.free(f.params);
                f.return_type.destroy(alloc);
                f.body.destroy(alloc);
            },
            .fn_param => {
                const p = self.value.fn_param;
                p.type.destroy(alloc);
            },
            .namespace => {
                alloc.free(self.value.namespace.tokens);
            },
            .body => {
                const b = self.value.body;
                for (b.nodes) |node| {
                    node.destroy(alloc);
                }
                alloc.free(b.nodes);
            },
            .@"return" => {
                self.value.@"return".destroy(alloc);
            },
            .@"if" => b: {
                const f = self.value.@"if";
                f.condition.destroy(alloc);
                f.branch_true.destroy(alloc);
                (f.branch_false orelse break :b).destroy(alloc);
            },
            .@"var" => b: {
                const v = self.value.@"var";
                v.value.destroy(alloc);
                (v.typ orelse break :b).destroy(alloc);
            },
            .unary_op => {
                const o = self.value.unary_op;
                o.rhs.destroy(alloc);
            },
            .binary_op => {
                const o = self.value.binary_op;
                o.lhs.destroy(alloc);
                o.rhs.destroy(alloc);
            },
            .fn_invoke => {
                const f = self.value.fn_invoke;
                for (f.args) |node| {
                    node.destroy(alloc);
                }
                alloc.free(f.args);
                f.namespace.destroy(alloc);
            },

            // Literals
            .integer,
            .u_integer,
            .float,
            .char,
            .bool,
            .string, => {
                std.debug.print("Not freeing literal '{s}'.\n", .{ @tagName(self.value) });
            }
        }
        std.debug.print("Freed '{s}'\n", .{ @tagName(self.value) });
        alloc.destroy(self);
    }

    fn printIndents(indents: isize) void {
        const v = if (indents < 0) 0 else indents;
        for (0..std.math.cast(usize, v).?) |_| {
            std.debug.print("  ", .{});
        }
    }

    pub fn print(node: *const Node, indents: isize) void {
        switch (node.value) {
            .binary_op => {
                node.value.binary_op.lhs.print(indents);
                const o = switch (node.value.binary_op.op) {
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
                node.value.binary_op.rhs.print(indents);
            },
            .unary_op => {
                const o: u8 = switch (node.value.unary_op.op) {
                    .negate => '-',
                };
                std.debug.print("{c}", .{o});
                node.value.unary_op.rhs.print(indents);
            },
            .@"var" => {
                printIndents(indents);
                const make = node.value.@"var";
                std.debug.print("var ", .{});
                if (make.mods.constant) {
                    std.debug.print("const ", .{});
                }
                std.debug.print("{s}", .{make.name.data.string.slice});
                if (make.typ != null) {
                    std.debug.print(": ", .{});
                    make.typ.?.print(indents);
                } else {
                    std.debug.print(": ?", .{});
                }
                std.debug.print(" = ", .{});
                make.value.print(indents);
            },
            .fn_decl => {
                printIndents(indents);
                const fun = node.value.fn_decl;
                if (fun.mods.public) {
                    std.debug.print("pub ", .{});
                }
                if (fun.mods.constant) {
                    std.debug.print("const ", .{});
                }
                std.debug.print("fn {s}(", .{fun.name.data.string.slice});
                for (fun.params) |p| {
                    std.debug.print("{s}: ", .{p.value.fn_param.name.data.string.slice});
                    p.value.fn_param.type.print(indents);
                }
                std.debug.print(") -> ", .{});
                fun.return_type.print(indents);
                if (fun.body.value != NodeValue.body) {
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
                node.value.@"return".print(indents);
            },
            .body => {
                printIndents(indents);
                const bod = node.value.body;
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
                const _if = node.value.@"if";
                std.debug.print("if (", .{});
                _if.condition.print(indents + 1);
                std.debug.print(") {{", .{});
                _if.branch_true.print(indents);
                std.debug.print("\n", .{});
                printIndents(indents);
                std.debug.print("}}", .{});
                if (_if.branch_false == null) return;
                std.debug.print(" else ", .{});
                if (_if.branch_false.?.*.value == NodeValue.body) {
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
                const f = node.value.fn_invoke;
                f.namespace.print(indents);
                std.debug.print("(", .{});
                for (f.args) |a| {
                    a.print(indents);
                }
                std.debug.print(")", .{});
            },
            .namespace => {
                for (node.value.namespace.tokens, 0..) |tok, i| {
                    if (i + 1 >= node.value.namespace.tokens.len) {
                        std.debug.print("{s}", .{tok.data.string.slice});
                    } else std.debug.print("{s}.", .{tok.data.string.slice});
                }
            },
            .float => std.debug.print("{any}", .{node.value.float}),
            .integer => std.debug.print("{any}", .{node.value.integer}),
            else => std.debug.print("|{any}|", .{node.value}),
        }
    }
};

pub const NodeValue = union(enum) {
    fn_decl: struct { mods: packed struct { public: bool, constant: bool, misc: u6 }, name: Token, params: []*Node, return_type: *Node, body: *Node },
    fn_param: struct {
        name: Token,
        type: *Node,
    },
    fn_invoke: struct {
        namespace: *Node,
        args: []*Node,
    },
    body: struct { nodes: []*Node },
    @"return": *Node,

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
    @"var": struct {
        name: Token,
        mods: packed struct {
            constant: bool = false,
        },
        /// Null if type is to be inferred.
        typ: ?*Node,
        value: *Node,
    },
    @"if": struct {
        condition: *Node,
        /// Executed when condition is true
        branch_true: *Node,
        /// Either another if, the else block, or nothing.
        branch_false: ?*Node,
    },

    // literals
    integer: root.INTEGER,
    u_integer: root.U_INTEGER,
    float: root.FLOAT,
    char: root.FLOAT,
    bool: bool,
    string: lexer.StringData,
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
    _i: usize = 0,
    diagnostics: Diagnostics = .{},

    fn peek(self: *Parser) !TokenKind {
        return self.seek(0);
    }

    fn seek(self: *Parser, o: isize) !TokenKind {
        const i = std.math.cast(usize, std.math.cast(isize, self._i).? + o).?;
        return if (i < self.tokens.len) self.tokens[i].kind else Error.UnexpectedEndOfFile;
    }

    fn consume(self: *Parser, kind: TokenKind) !Token {
        if (self._i >= self.tokens.len) return Error.UnexpectedEndOfFile;
        const token = self.tokens[self._i];
        std.log.info("Try consume '{s}'", .{@tagName(kind)});
        if (token.kind == kind) {
            self._i += 1;
            return token;
        } else {
            self.diagnostics.err = .{ .error_type = Error.UnexpectedToken, .data = .{ .u = @intFromEnum(kind) } };
            return Error.UnexpectedToken;
        }
    }

    pub fn parse(self: *Parser) !*Node {
        self._i = 0;

        const ret = body(self) catch |e| {
            switch (e) {
                Error.UnexpectedToken => try generalUnexpectedToken(self),
                Error.ExpectedStartOfStatement => try iWantedThingHere(self, "start of statement"),
                else => {},
            }
            return e;
        };

        std.debug.print("Parsed.", .{});
        ret.print(10);
        std.debug.print("\n", .{});

        return self.alloc(ret);
    }

    fn doAlloc(self: *Parser, f: fn (*Parser) anyerror!Node) !*Node {
        return self.alloc(f(self));
    }

    fn alloc(self: *Parser, en: anyerror!Node) !*Node {
        const n = try en;
        const ptr = try self.allocator.create(Node);
        ptr.* = n;
        return ptr;
    }

    pub const Error = error{
        UnexpectedToken,
        UnexpectedEndOfFile,
        ExpectedStartOfStatement
    };
};

fn generalUnexpectedToken(self: *Parser) !void {
    const kind = @as(TokenKind, @enumFromInt(self.diagnostics.err.?.data.?.u));
    try iWantedThingHere(self, @tagName(kind));
}

fn iWantedThingHere(self: *Parser, thing: []const u8) !void {
    const token = self.tokens[self._i];
    std.log.err("Expected '{s}', but got '{s}'\n", .{ thing, @tagName(token.kind) });
    const back_dist = 3;
    const forward_dist = 3;
    const min = if (self._i < back_dist) self._i else self._i - back_dist;
    const max = if (self.tokens.len < forward_dist) self.tokens.len - 1 else self._i + forward_dist + 1;
    for (self.tokens[min..max], 0..) |tok, i| {
        if (min + i == self._i) {
            std.log.err("// Wanted '{s}' here.", .{ thing });
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
    try w.print("{any: >3}: ", .{line - 1});
    for (source) |c| {
        try w.printAsciiChar(c, .{});

        if (std.ascii.isWhitespace(c) and c != ' ') {
            try w.print("{any: >3}: ", .{line});
            line += 1;
        }
    }

    try w.writeByte('\n');
}

fn statement(self: *Parser) !Node {
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
                typ = try self.doAlloc(namespace);
            }
            _ = try self.consume(.equals);
            const e = try self.doAlloc(expression);
            return .{ .token = var_token, .value = .{ .@"var" = .{ .name = name, .value = e, .typ = typ, .mods = .{
                .constant = constant,
            } } } };
        },
        .keyword_return => {
            const token = try self.consume(.keyword_return);
            return .{ .token = token, .value = .{ .@"return" = try self.doAlloc(expression) } };
        },
        .keyword_if => {
            return try if_statement(self);
        },
        else => {
            std.log.err("Expected start of statement, got '{s}'.", .{@tagName(p)});
            return Parser.Error.ExpectedStartOfStatement;
            // return try expr(self);
        },
    }

    unreachable;
}

fn if_statement(self: *Parser) anyerror!Node {
    std.debug.print("parsing if statement\n", .{});
    const if_token = switch (try self.peek()) {
        .keyword_elif => try self.consume(.keyword_elif),
        else => try self.consume(.keyword_if),
    };
    _ = try self.consume(.open_paren);
    const condition = try self.doAlloc(expression);
    _ = try self.consume(.close_paren);
    _ = try self.consume(.open_brace);
    const if_true = try self.doAlloc(body);
    _ = try self.consume(.close_brace);
    var if_false: ?*Node = null;
    switch (try self.peek()) {
        .keyword_elif => {
            if_false = try self.doAlloc(if_statement);
        },
        .keyword_else => {
            _ = try self.consume(.keyword_else);
            _ = try self.consume(.open_brace);
            if_false = try self.doAlloc(body);
            _ = try self.consume(.close_brace);
        },
        else => {},
    }
    return .{ .token = if_token, .value = .{ .@"if" = .{
        .condition = condition,
        .branch_true = if_true,
        .branch_false = if_false,
    } } };
}

fn factor(self: *Parser) !Node {
    const kind = try self.peek();
    switch (kind) {
        .literal_string => {
            const token = try self.consume(.literal_string);
            return .{ .token = token, .value = .{ .string = token.data.string } };
        },
        .literal_bool => {
            const token = try self.consume(.literal_bool);
            return .{ .token = token, .value = .{ .bool = token.data.bool } };
        },
        .literal_float => {
            const token = try self.consume(.literal_float);
            return .{ .token = token, .value = .{ .float = token.data.float } };
        },
        .literal_integer => {
            const token = try self.consume(.literal_integer);
            return .{ .token = token, .value = .{ .integer = token.data.integer } };
        },
        .open_paren => {
            _ = try self.consume(.open_paren);
            const node = try expression(self);
            _ = try self.consume(.close_paren);
            return node;
        },
        .operator_sub => {
            const token = try self.consume(.operator_sub);
            const node = try self.doAlloc(factor);
            return .{ .token = token, .value = .{ .unary_op = .{ .op = .negate, .rhs = node } } };
        },
        .identifier => {
            const ns = namespace(self);
            if (try self.peek() == .open_paren) {
                // this is a function invocation, not field access.
                _ = try self.consume(.open_paren);
                const args = try arguments(self);
                _ = try self.consume(.close_paren);
                return .{ .value = .{ .fn_invoke = .{
                    .namespace = try self.alloc(ns),
                    .args = args,
                } } };
            } else {
                // just field access
                return try ns;
            }
        },
        // idk
        else => {
            std.log.err("Unhandled factor kind {s}\n", .{@tagName(kind)});
            @panic("");
        },
    }
}

fn arguments(self: *Parser) ![]*Node {
    std.debug.print("parsing arguments\n", .{});
    // if there are no expressions
    if (try self.peek() == .close_paren) return &[0]*Node{};

    var args = try std.ArrayList(*Node).initCapacity(self.allocator, 4);

    var a = try self.doAlloc(expression);
    try args.append(self.allocator, a);

    while (try self.peek() == .comma) {
        _ = try self.consume(.comma);
        a = try self.doAlloc(expression);
        try args.append(self.allocator, a);
    }

    return try args.toOwnedSlice(self.allocator);
}

fn function(self: *Parser) !Node {
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
    std.debug.print("parsing parameters\n", .{});
    const params: []*Node = params: {
        if (try self.peek() == .close_paren) break :params &[0]*Node{};

        var params = try std.ArrayList(*Node).initCapacity(self.allocator, 4);
        var p = try self.doAlloc(parameter);
        try params.append(self.allocator, p);

        while (try self.peek() == .comma) {
            _ = try self.consume(.comma);
            p = try self.doAlloc(parameter);
            try params.append(self.allocator, p);
        }

        break :params try params.toOwnedSlice(self.allocator);
    };
    _ = try self.consume(.close_paren);

    //read return type
    _ = try self.consume(.right_arrow);
    const ret_type = try self.doAlloc(namespace);

    var body_node: *Node = undefined;
    // handle expr body
    if (try self.peek() == .equals) {
        _ = try self.consume(.equals);
        body_node = try self.doAlloc(expression);
    } else {
        // read usual body
        _ = try self.consume(.open_brace);
        body_node = try self.doAlloc(body);
        _ = try self.consume(.close_brace);
    }

    std.debug.print("Returned function '{s}'\n", .{name.data.string.slice});
    return .{ .value = .{ .fn_decl = .{ .name = name, .mods = .{ .public = public, .constant = constant, .misc = 0 }, .params = params, .return_type = ret_type, .body = body_node } } };
}

fn body(self: *Parser) !Node {
    std.debug.print("parsing body\n", .{});
    if (try self.peek() == .close_brace) {
        _ = try self.consume(.close_brace);
        return .{ .value = .{ .body = .{ .nodes = &[0]*Node{} } } };
    }

    var statements = try std.ArrayList(*Node).initCapacity(self.allocator, 4);

    var s = try self.doAlloc(statement);
    try statements.append(self.allocator, s);

    while (self._i + 1 < self.tokens.len) {
        if (try self.seek(-1) != .close_brace)
            _ = try self.consume(.semicolon);
        if (try self.peek() == .close_brace) {
            break;
        }
        s = try self.doAlloc(statement);
        try statements.append(self.allocator, s);
    }

    return .{ .value = .{ .body = .{ .nodes = try statements.toOwnedSlice(self.allocator) } } };
}

/// Gathers all consecutive identifiers delimited by periods.
fn namespace(self: *Parser) !Node {
    std.debug.print("parsing namespace\n", .{});
    var ns = try std.ArrayList(Token).initCapacity(self.allocator, 4);
    const first = try self.consume(.identifier);
    try ns.append(self.allocator, first);

    while (try self.peek() == .period) {
        _ = try self.consume(.period);
        const i = try self.consume(.identifier);
        try ns.append(self.allocator, i);
    }

    const tokens = try ns.toOwnedSlice(self.allocator);
    return .{ .value = .{ .namespace = .{ .tokens = tokens } } };
}

fn parameter(self: *Parser) !Node {
    const name = try self.consume(.identifier);
    _ = try self.consume(.colon);
    const t = try self.doAlloc(namespace);
    return .{ .value = .{ .fn_param = .{
        .name = name,
        .type = t,
    } } };
}

fn term(self: *Parser) !Node {
    var node = try factor(self);
    var peeked = self.peek() catch |e| {
        if (e == Parser.Error.UnexpectedEndOfFile) return node else return e;
    };

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_mul => .mul,
            .operator_div => .div,
            else => break,
        };

        const op = try self.consume(peeked);

        const lhs = node;
        const rhs = try self.doAlloc(factor);
        node = .{ .token = op, .value = .{ .binary_op = .{
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } } };

        peeked = try self.peek();
    }

    return node;
}

fn expression(self: *Parser) anyerror!Node {
    std.debug.print("parsing expression\n", .{});
    var node_ptr = try term(self);
    var peeked = self.peek() catch |e| {
        if (e == Parser.Error.UnexpectedEndOfFile) return node_ptr else return e;
    };

    while (true) {
        const op_kind: BinaryOperation = switch (peeked) {
            .operator_add => .add,
            .operator_sub => .sub,
            .operator_greater_than => .gt,
            .operator_less_than => .lt,
            else => break,
        };

        const op = try self.consume(peeked);

        const lhs = node_ptr;
        const rhs = try self.doAlloc(term);
        node_ptr = .{ .token = op, .value = .{ .binary_op = .{
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } } };

        peeked = try self.peek();
    }

    return node_ptr;
}

fn lexAndParse(alloc: std.mem.Allocator, source: []const u8) !*Node {
    var l = lexer.Lexer{ .allocator = alloc, .source = source };
    const tokens = try l.tokenize();
    defer alloc.free(tokens);
    var p = Parser{
        .allocator = alloc,
        .source = l.source,
        .tokens = tokens,
    };
    return try p.parse();
}

test "const var" {
    const node = try lexAndParse(std.testing.allocator, "var const test = 1.0 * 2 + (3 - 4);");
    defer node.destroy(std.testing.allocator);

    const root_node = node.value.body.nodes[0];
    try expect(root_node.value == NodeValue.@"var");
    const vnode = root_node.value.@"var";

    const var_name = vnode.name.data.string.slice;
    try expect(std.mem.eql(u8, var_name, "test"));
    const var_type = vnode.typ;
    try expect(var_type == null);
    const var_value = vnode.value.value;
    try expect(var_value == NodeValue.binary_op);

    // op_mid sums op_left and op_right
    const op_mid = var_value.binary_op;
    try expect(op_mid.op == .add);

    const op_left = op_mid.lhs.value.binary_op;
    try expect(op_left.lhs.value.float == 1.0);
    try expect(op_left.op == .mul);
    try expect(op_left.rhs.value.integer == 2);

    const op__right = op_mid.rhs.value.binary_op;
    try expect(op__right.lhs.value.integer == 3);
    try expect(op__right.op == .sub);
    try expect(op__right.rhs.value.integer == 4);
}

test "parse function expression" {
    const node = try lexAndParse(std.testing.allocator, "pub fn start() -> int32 = 1;");
    defer node.destroy(std.testing.allocator);

    const fnode = node.value.body.nodes[0];

    try expect(fnode.value == NodeValue.fn_decl);
    const func = fnode.value.fn_decl;
    try expect(std.mem.eql(u8, func.name.data.string.slice, "start"));
    try expect(func.params.len == 0);
    const return_type_name = func.return_type.value.namespace.tokens[0].data.string.slice;
    try expect(std.mem.eql(u8, return_type_name, "int32"));
    const return_value = func.body.value.integer;
    try expect(return_value == 1);
}

test "parse function body" {
    const node = try lexAndParse(std.testing.allocator, "pub fn start() -> int32 { return SUCCESS; }");
    defer node.destroy(std.testing.allocator);

    const fnode = node.value.body.nodes[0];

    try expect(fnode.value == NodeValue.fn_decl);
    const func = fnode.value.fn_decl;
    try expect(std.mem.eql(u8, func.name.data.string.slice, "start"));
    try expect(func.params.len == 0);
    const return_type_name = func.return_type.value.namespace.tokens[0].data.string.slice;
    try expect(std.mem.eql(u8, return_type_name, "int32"));
    const return_statement = func.body.value.body.nodes[0];
    try expect(return_statement.value == NodeValue.@"return");
    const return_var_name = return_statement.value.@"return".value.namespace.tokens[0].data.string.slice;
    try expect(std.mem.eql(u8, return_var_name, "SUCCESS"));
}