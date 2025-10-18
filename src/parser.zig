const std = @import("std");
const lexer = @import("tokenizer.zig");
const root = @import("root.zig");
const AST = @import("AST.zig");
const Node = AST.Node;
const LineInfo = Node.LineInfo;
const expect = std.testing.expect;
const Diagnostics = root.Diagnostics;
const TokenKind = lexer.TokenKind;
const TokenData = lexer.TokenData;
const Token = lexer.Token;
const Type = @import("type.zig").Type;

pub const Parser = struct {
    // Parameters
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: []Token,

    // State
    _i: usize = 0,
    diagnostics: Diagnostics = .{},

    pub fn init(allocator: std.mem.Allocator, tokens: []Token, source: []const u8) Parser {
        return Parser {
            .allocator = allocator,
            .tokens = tokens,
            .source = source,
        };
    }

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
            return .{ .@"var" = .{
                .loc = LineInfo {
                    .line = var_token.source_data.line,
                    .src_start_ndx = var_token.source_data.index,
                    .src_end_ndx = 0 -| -1
                },
                .mods = .{
                    .constant = constant,
                },
                .name = try self.allocator.dupe(u8, name.data.string.slice),
                .type = typ,
                .value = e,
            } };
        },
        .identifier, .open_bracket => return try object_invoke_or_field_access(self),
        .keyword_return => {
            _ = try self.consume(.keyword_return);
            if (try self.peek() == .semicolon) {
                return .{ .@"return" = null };
            }
            return .{ .@"return" = try self.doAlloc(expression) } ;
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

fn object_invoke_or_field_access(self: *Parser) anyerror!Node {
    var builtin = false;
    var is_func = false;
    if (try self.peek() == .open_bracket) {
        builtin = true;
        is_func = true;
        _ = try self.consume(.open_bracket);
    }
    const ns = try namespace(self);
    if (builtin) _ = try self.consume(.close_bracket);

    if (try self.peek() == .open_paren) is_func = true;

    if (!is_func) return ns;

    _ = try self.consume(.open_paren);
    const args = try arguments(self);
    const closing = try self.consume(.close_paren);
    return .{
        .fn_invoke = .{
            .loc = LineInfo{
                .line = ns.namespace.loc.line,
                .src_start_ndx = ns.namespace.loc.src_start_ndx,
                .src_end_ndx = closing.source_data.index + 1
            },
            .builtin = builtin,
            .namespace = try self.alloc(ns),
            .args = args,
        }
    };
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
    const closing = try self.consume(.close_brace);
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
    return .{ .@"if" = .{
        .loc = LineInfo {
            .line = if_token.source_data.line,
            .src_start_ndx = if_token.source_data.index,
            .src_end_ndx = closing.source_data.index
        },
        .condition = condition,
        .branch_true = if_true,
        .branch_false = if_false,
    } };
}

fn factor(self: *Parser) !Node {
    const kind = try self.peek();
    switch (kind) {
        .literal_string => {
            const token = try self.consume(.literal_string);
            return .{ .string = .{
                .loc = LineInfo{
                    .line = token.source_data.line,
                    .src_start_ndx = token.source_data.index,
                    .src_end_ndx = token.source_data.index
                },
                .data = try self.allocator.dupe(u8, token.data.string.slice)
            } };
        },
        .literal_bool => {
            const token = try self.consume(.literal_bool);
            return .{ .bool = .{
                .loc = LineInfo{
                    .line = token.source_data.line,
                    .src_start_ndx = token.source_data.index,
                    .src_end_ndx = token.source_data.index
                },
                .data = token.data.bool
            } };
        },
        .literal_float => {
            const token = try self.consume(.literal_float);
            return .{ .float = .{
                .loc = LineInfo{
                    .line = token.source_data.line,
                    .src_start_ndx = token.source_data.index,
                    .src_end_ndx = token.source_data.index
                },
                .data = token.data.float
            } };
        },
        .literal_integer => {
            const token = try self.consume(.literal_integer);
            return .{ .integer = .{
                .loc = LineInfo{
                    .line = token.source_data.line,
                    .src_start_ndx = token.source_data.index,
                    .src_end_ndx = token.source_data.index
                },
                .data = token.data.integer
            } };
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
            return .{ .unary_op = .{
                .loc = LineInfo{
                    .line = token.source_data.line,
                    .src_start_ndx = token.source_data.index,
                    .src_end_ndx = token.source_data.index
                },
                .op = .negate,
                .rhs = node
            } };
        },
        .identifier, .open_bracket => return try object_invoke_or_field_access(self),
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

    var a = try expression(self);
    try args.append(self.allocator, a);

    while (try self.peek() == .comma) {
        _ = try self.consume(.comma);
        a = try expression(self);
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
    const keyword = try self.consume(.keyword_fn);

    // read name
    const name = try self.consume(.identifier);

    // read params
    _ = try self.consume(.open_paren);
    std.debug.print("parsing parameters\n", .{});
    const params = params: {
        if (try self.peek() == .close_paren) break :params &[0]Node.FnDecl.Param{};

        var params = try std.ArrayList(Node.FnDecl.Param).initCapacity(self.allocator, 4);
        var p = try parameter(self);
        try params.append(self.allocator, p);

        while (try self.peek() == .comma) {
            _ = try self.consume(.comma);
            p = try parameter(self);
            try params.append(self.allocator, p);
        }

        break :params try params.toOwnedSlice(self.allocator);
    };
    _ = try self.consume(.close_paren);

    //read return type
    _ = try self.consume(.right_arrow);
    const rtype_ns = try self.doAlloc(namespace);

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

    const rtype = try Type.typeFromNamespace(self.allocator, rtype_ns.namespace);

    std.debug.print("Returned function '{s}'\n", .{name.data.string.slice});
    return .{ .fn_decl = .{
        .loc = LineInfo {
            .line = keyword.source_data.line,
            .src_start_ndx = keyword.source_data.index,
            .src_end_ndx = 0,
        },
        .name = name.data.string.slice,
        .mods = .{
            .public = public,
            .constant = constant,
        },
        .params = params,
        .return_type = reType: {

            const ptr = try self.allocator.create(Type);
            ptr.* = rtype;
            break :reType ptr;
        },
        .body = body_node
    } };
}

fn body(self: *Parser) !Node {
    std.debug.print("parsing body\n", .{});
    if (try self.peek() == .close_brace) {
        const closing = try self.consume(.close_brace);
        self._i -= 1;
        return .{ .body = .{ .loc = LineInfo{
            .line = closing.source_data.line,
            .src_start_ndx = closing.source_data.index - 1,
            .src_end_ndx = closing.source_data.index,
        }, .nodes = &[0]Node{} } };
    }

    var statements = try std.ArrayList(Node).initCapacity(self.allocator, 4);
    var s = try statement(self);
    try statements.append(self.allocator, s);

    while (self._i + 1 < self.tokens.len) {
        if (try self.seek(-1) != .close_brace)
            _ = try self.consume(.semicolon);
        if (try self.peek() == .close_brace) {
            break;
        }
        s = try statement(self);
        try statements.append(self.allocator, s);
    }

    return .{ .body = .{
        .loc = LineInfo {
            .line = 0,
            .src_start_ndx = 0,
            .src_end_ndx = 0
        },
        .nodes = try statements.toOwnedSlice(self.allocator)
    } };
}

/// Gathers all consecutive identifiers delimited by periods.
fn namespace(self: *Parser) !Node {
    std.debug.print("parsing namespace\n", .{});
    var ns = try std.ArrayList([] const u8).initCapacity(self.allocator, 4);

    const first = try self.consume(.identifier);
    try ns.append(self.allocator, first.data.string.slice);

    while (try self.peek() == .period) {
        _ = try self.consume(.period);
        const i = try self.consume(.identifier);
        try ns.append(self.allocator, i.data.string.slice);
    }

    const tokens = try ns.toOwnedSlice(self.allocator);
    var length: usize = 0;
    for (tokens) |str| {
        length = length + str.len;
    }
    return .{ .namespace = .{
        .loc = LineInfo {
            .line = first.source_data.line,
            .src_start_ndx = first.source_data.index,
            .src_end_ndx = first.source_data.index + length
        },
        .data = tokens
    } };
}

fn parameter(self: *Parser) !Node.FnDecl.Param {
    const name = try self.consume(.identifier);
    _ = try self.consume(.colon);
    const typ = try self.doAlloc(namespace);
    return .{
        .loc = LineInfo {
            .line = name.source_data.line,
            .src_start_ndx = name.source_data.index,
            .src_end_ndx = typ.namespace.loc.src_end_ndx,
        },
        .name = try self.allocator.dupe(u8, name.data.string.slice),
        .type = typ,
    };
}

fn term(self: *Parser) !Node {
    var node = try factor(self);
    var peeked = self.peek() catch |e| {
        if (e == Parser.Error.UnexpectedEndOfFile) return node else return e;
    };

    while (true) {
        const op_kind: Node.BinaryOp.Op = switch (peeked) {
            .operator_mul => .mul,
            .operator_div => .div,
            else => break,
        };
        _ = try self.consume(peeked);

        const lhs = node;
        const rhs = try self.doAlloc(factor);

        node = .{ .binary_op = .{
            .loc = .{
                .line = 0,
                .src_start_ndx = 0,
                .src_end_ndx = 0,
            },
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } };

        peeked = try self.peek();
    }

    return node;
}

fn expression(self: *Parser) anyerror!Node {
    std.debug.print("parsing expression\n", .{});
    var node = try term(self);
    var peeked = self.peek() catch |e| {
        if (e == Parser.Error.UnexpectedEndOfFile) return node else return e;
    };

    while (true) {
        const op_kind: Node.BinaryOp.Op = switch (peeked) {
            .operator_add => .add,
            .operator_sub => .sub,
            .operator_greater_than => .gt,
            .operator_less_than => .lt,
            else => break,
        };

        _ = try self.consume(peeked);

        const lhs = node;
        const rhs = try self.doAlloc(term);
        node = .{ .binary_op = .{
            .loc = .{
                .line = 0,
                .src_start_ndx = 0,
                .src_end_ndx = 0
            },
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } };

        peeked = try self.peek();
    }

    return node;
}

fn lexAndParse(alloc: std.mem.Allocator, source: []const u8) !*Node {
    var l = lexer.Tokenizer{ .allocator = alloc, .source = source };
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();
    const node = try lexAndParse(alloc, "var const test = 1.0 * 2 + (3 - 4);");

    const root_node = node.body.nodes[0];
    try expect(root_node == Node.@"var");
    const vnode = root_node.@"var";

    const var_name = vnode.name;
    try expect(std.mem.eql(u8, var_name, "test"));
    const var_type = vnode.type;
    try expect(var_type == null);
    const var_value = vnode.value.*;
    try expect(var_value == Node.binary_op);

    // op_mid sums op_left and op_right
    const op_mid = var_value.binary_op;
    try expect(op_mid.op == .add);

    const op_left = op_mid.lhs.binary_op;
    try expect(op_left.lhs.float.data == 1.0);
    try expect(op_left.op == .mul);
    try expect(op_left.rhs.integer.data == 2);

    const op__right = op_mid.rhs.binary_op;
    try expect(op__right.lhs.integer.data == 3);
    try expect(op__right.op == .sub);
    try expect(op__right.rhs.integer.data == 4);
}

test "parse function expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub fn start() -> int = 1;");

    const fnode = node.body.nodes[0];

    try expect(fnode == Node.fn_decl);
    const func = fnode.fn_decl;
    try expect(std.mem.eql(u8, func.name, "start"));
    try expect(func.params.len == 0);
    const return_type_name = @tagName(func.return_type.*);
    try expect(std.mem.eql(u8, return_type_name, "int"));
    // there isnt even a body in this situation; The expression is directly parsed into that slot.
    const return_value = func.body.integer.data;
    try expect(return_value == 1);
}

test "parse function body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub fn start() -> int { return SUCCESS; }");

    const fnode = node.body.nodes[0];

    try expect(fnode == Node.fn_decl);
    const func = fnode.fn_decl;
    try expect(std.mem.eql(u8, func.name, "start"));
    try expect(func.params.len == 0);
    const return_type_name = @tagName(func.return_type.*);
    std.debug.print("return type = '{s}'\n", .{ return_type_name });
    try expect(std.mem.eql(u8, return_type_name, "int"));
    const return_statement = func.body.body.nodes[0];
    try expect(return_statement == Node.@"return");
    const return_var_name = return_statement.@"return".?.namespace.data[0];
    try expect(std.mem.eql(u8, return_var_name, "SUCCESS"));
}