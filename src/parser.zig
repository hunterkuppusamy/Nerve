const std = @import("std");
const lexer = @import("tokenizer.zig");
const root = @import("root.zig");
const AST = @import("AST.zig");
const Node = AST.Node;
const Location = @import("notification.zig").Location;
const NotificationList = @import("notification.zig").NotificationList;
const expect = std.testing.expect;
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
    notifications: ?*NotificationList = null,

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
        if (self._i >= self.tokens.len) {
            self.reportError("unexpected end of file, expected '{s}'", .{@tagName(kind)});
            return Error.UnexpectedEndOfFile;
        }
        const token = self.tokens[self._i];
        std.log.info("Try consume '{s}'", .{@tagName(kind)});
        if (token.kind == kind) {
            self._i += 1;
            return token;
        } else {
            self.reportErrorAtToken(token, "expected '{s}', got '{s}'", .{ @tagName(kind), @tagName(token.kind) });
            return error.UnexpectedToken;
        }
    }

    pub fn parse(self: *Parser) !*Node {
        self._i = 0;
        const ret = type_decl(self, true) catch |e| return e;
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

    fn reportError(self: *Parser, comptime fmt: []const u8, args: anytype) void {
        if (self.notifications) |n| {
            std.debug.print("i = {d}, len = {d}\n", .{ self._i, self.tokens.len });
            const loc = if (self._i < self.tokens.len)
                tokenLoc(self.tokens[self._i])
            else if (self.tokens.len > 0)
                tokenLoc(self.tokens[self.tokens.len - 1])
            else
                Location{};
            n.err(loc, fmt, args);
        }
    }

    fn reportErrorAtToken(self: *Parser, token: Token, comptime fmt: []const u8, args: anytype) void {
        if (self.notifications) |n| n.err(tokenLoc(token), fmt, args);
    }

    pub const Error = error{
        UnexpectedToken,
        UnexpectedEndOfFile,
        ExpectedStartOfStatement
    };
};

fn tokenLoc(token: Token) Location {
    return .{ .line = token.source_data.line, .column = token.source_data.column };
}

/// The first function invoked for parsing.
fn type_decl(self: *Parser, is_root: bool) !Node {
    if (!is_root and try self.peek() == .close_brace)
        return Node { .type_decl = .{ .loc = Location{}, .fields = &.{} } };

    var decls = try std.ArrayList(Node).initCapacity(self.allocator, 4);
    var decl = try declaration(self);
    const first_loc = decl.location();
    try decls.append(self.allocator, decl);

    while (self._i < self.tokens.len) {
        const next = try self.peek();
        if (next == .semicolon) { _ = try self.consume(.semicolon); continue; }
        if (!is_root and next == .close_brace) break;
        decl = try declaration(self);
        try decls.append(self.allocator, decl);
    }

    return .{ .type_decl = .{
        .loc = first_loc,
        .fields = try decls.toOwnedSlice(self.allocator),
    } };
}

/// Parses declarations (fields) inside a type.
fn declaration(self: *Parser) !Node {
    std.debug.print("parsing declaration\n", .{});
    const p = try self.peek();
    switch (p) {
        .keyword_const,
        .keyword_pub,
        .keyword_static,
        .keyword_var => {
            return try variable(self, .file);
        },
        else => {
            self.reportError("expected declaration, got '{s}'", .{@tagName(p)});
            return error.UnexpectedToken;
        }
    }
}

/// Parses statements inside a function.
fn statement(self: *Parser) !Node {
    std.debug.print("parsing statement\n", .{});
    const p = try self.peek();
    switch (p) {
        .keyword_const, .keyword_var => {
            return try variable(self, .local);
        },
        // Will parse as field / invocation
        .identifier => return try expression(self),
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
            self.reportError("expected start of statement, got '{s}'", .{@tagName(p)});
            return Parser.Error.ExpectedStartOfStatement;
        },
    }

    unreachable;
}

fn variable(self: *Parser, scope: Node.VarDecl.Scope) !Node {
    var constant = false;
    var public = false;
    var static = false;
    // Does not allow duplicate modifiers.
    while (true) {
        switch (self.peek() catch {
            self.reportError("unexpected end of file in declaration", .{});
            return Parser.Error.UnexpectedEndOfFile;
        }) {
            .keyword_const => {
                if (constant) { self.reportError("duplicate 'const' modifier", .{}); return error.UnexpectedToken; }
                _ = try self.consume(.keyword_const);
                constant = true;
            },
            .keyword_pub => {
                if (scope == .local) { self.reportError("'pub' is not allowed on local variables", .{}); return error.UnexpectedToken; }
                if (public) { self.reportError("duplicate 'pub' modifier", .{}); return error.UnexpectedToken; }
                _ = try self.consume(.keyword_pub);
                public = true;
            },
            .keyword_static => {
                if (scope == .local) { self.reportError("'static' is not allowed on local variables", .{}); return error.UnexpectedToken; }
                if (static) { self.reportError("duplicate 'static' modifier", .{}); return error.UnexpectedToken; }
                _ = try self.consume(.keyword_static);
                static = true;
            },
            else => break,
        }
    }
    const var_token = try self.consume(.keyword_var);
    const name = try self.consume(.identifier);
    var typ: ?*Node = null;
    if ((self.peek() catch {
        self.reportErrorAtToken(name, "incomplete declaration for '{s}'", .{name.data.string.slice});
        return Parser.Error.UnexpectedEndOfFile;
    }) == .colon) {
        _ = try self.consume(.colon);
        typ = try self.doAlloc(expression);
    }
    _ = try self.consume(.equals);
    const e = try self.doAlloc(expression);
    return .{ .@"var" = .{
        .loc = tokenLoc(var_token),
        .mods = .{
            .constant = constant,
            .public = public,
            .static = static,
        },
        .scope = scope,
        .name = try self.allocator.dupe(u8, name.data.string.slice),
        .type = typ,
        .value = e,
    } };
}

fn object_invoke_or_field_access(self: *Parser, instance: ?*Node) anyerror!Node {
    var builtin = false;
    var is_func = false;
    if (try self.peek() == .open_bracket) {
        builtin = true;
        is_func = true;
        _ = try self.consume(.open_bracket);
    }
    const name = try self.consume(.identifier);
    if (builtin) _ = try self.consume(.close_bracket);

    if (try self.peek() == .open_paren) is_func = true;

    if (!is_func and builtin) {
        self.reportError("builtin cannot be used as a field", .{});
        return error.IllegalExpression;
    } else if (!is_func) return .{ .field_access = .{
        .loc = tokenLoc(name),
        .builtin = false,
        .instance = instance,
        .name = name.data.string.slice,
    } };

    _ = try self.consume(.open_paren);
    const args = try arguments(self);
    _ = try self.consume(.close_paren);
    return .{ .fn_invoke = .{
        .loc = tokenLoc(name),
        .builtin = builtin,
        .instance = instance,
        .name = name.data.string.slice,
        .args = args,
    } };
}

fn if_statement(self: *Parser) anyerror!Node {
    std.debug.print("parsing if statement\n", .{});
    const if_token = switch (try self.peek()) {
        .keyword_elseif => try self.consume(.keyword_elseif),
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
        .keyword_elseif => {
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
        .loc = tokenLoc(if_token),
        .condition = condition,
        .branch_true = if_true,
        .branch_false = if_false,
    } };
}

fn factor(self: *Parser) !Node {
    const kind = self.peek() catch {
        self.reportError("unexpected end of file in expression", .{});
        return Parser.Error.UnexpectedEndOfFile;
    };
    switch (kind) {
        .literal_string => {
            const token = try self.consume(.literal_string);
            return .{ .string = .{ .loc = tokenLoc(token), .data = try self.allocator.dupe(u8, token.data.string.slice) } };
        },
        .literal_bool => {
            const token = try self.consume(.literal_bool);
            return .{ .bool = .{ .loc = tokenLoc(token), .data = token.data.bool } };
        },
        .literal_float => {
            const token = try self.consume(.literal_float);
            return .{ .float = .{ .loc = tokenLoc(token), .data = token.data.float } };
        },
        .literal_integer => {
            const token = try self.consume(.literal_integer);
            return .{ .integer = .{ .loc = tokenLoc(token), .data = token.data.integer } };
        },
        .open_paren => {
            _ = try self.consume(.open_paren);
            const node = try expression(self);
            _ = try self.consume(.close_paren);
            return node;
        },
        .operator_sub => {
            const token = try self.consume(.operator_sub);
            return .{ .unary_op = .{ .loc = tokenLoc(token), .op = .negate, .rhs = try self.doAlloc(factor) } };
        },
        .keyword_fn => return try function_decl(self),
        .identifier, .open_bracket => {
            if (try self.seek(1) != .close_bracket)
                return try object_invoke_or_field_access(self, null);

            const open = try self.consume(.open_bracket);
            _ = try self.consume(.close_bracket);
            const expr = try self.doAlloc(expression);
            return .{ .array_of = .{ .loc = tokenLoc(open), .element_type = expr } };
        },
        .keyword_type => {
            _ = try self.consume(.keyword_type);
            _ = try self.consume(.open_brace);
            defer _ = self.consume(.close_brace) catch unreachable;
            return try type_decl(self, false);
        },
        // idk
        else => {
            self.reportError("unexpected '{s}' in expression", .{@tagName(kind)});
            return Parser.Error.UnexpectedToken;
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

fn function_decl(self: *Parser) !Node {
    std.debug.print("parsing function\n", .{});
    // assert fn
    const keyword = try self.consume(.keyword_fn);

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
    const rtype = try self.doAlloc(expression);

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

    std.debug.print("Returned function\n", .{});
    return .{ .fn_decl = .{
        .loc = tokenLoc(keyword),
        .params = params,
        .return_type = rtype,
        .body = body_node,
    } };
}

fn body(self: *Parser) !Node {
    std.debug.print("parsing body\n", .{});
    if (try self.peek() == .close_brace) {
        const closing = try self.consume(.close_brace);
        self._i -= 1;
        self._i -= 1;
        return .{ .body = .{ .loc = tokenLoc(closing), .nodes = &[0]Node{} } };
    }

    var statements = try std.ArrayList(Node).initCapacity(self.allocator, 4);
    var s = try statement(self);
    const first_loc = s.location();
    try statements.append(self.allocator, s);

    while (self._i + 1 < self.tokens.len) {
        if (try self.seek(-1) != .close_brace)
            _ = try self.consume(.semicolon);
        if (try self.peek() == .close_brace) break;
        s = try statement(self);
        try statements.append(self.allocator, s);
    }

    return .{ .body = .{
        .loc = first_loc,
        .nodes = try statements.toOwnedSlice(self.allocator),
    } };
}

fn parameter(self: *Parser) !Node.FnDecl.Param {
    const name = try self.consume(.identifier);
    _ = try self.consume(.colon);
    const typ = try self.doAlloc(expression);
    return .{
        .loc = tokenLoc(name),
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
        peeked = try self.peek();
        if (peeked == .period) {
            _ = try self.consume(.period);
            node = try object_invoke_or_field_access(self, try self.alloc(node));
            continue;
        }

        const op_kind: Node.BinaryOp.Op = switch (peeked) {
            .operator_mul => .mul,
            .operator_div => .div,
            else => break,
        };
        _ = try self.consume(peeked);

        const lhs = node;
        const rhs = try self.doAlloc(factor);

        node = .{ .binary_op = .{
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } };
    }

    return node;
}

fn expression(self: *Parser) anyerror!Node {
    std.debug.print("parsing expression\n", .{});
    var node = try term(self);
    var peeked = self.peek() catch |e| {
        if (e == Parser.Error.UnexpectedEndOfFile) return node else return e;
    };
    if (peeked == .keyword_fn) return try function_decl(self);

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
            .lhs = try self.alloc(lhs),
            .op = op_kind,
            .rhs = rhs,
        } };

        if (self._i >= self.tokens.len) break;
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
    const node = try lexAndParse(alloc, "const var test = 1.0 * 2 + (3 - 4)");

    const root_node = node.type_decl.fields[0];
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

    const node = try lexAndParse(alloc, "pub var start = fn()->int = 1;");

    const root_node = node.type_decl;
    const field = root_node.fields[0];
    try expect(field == Node.@"var");
    const decl = field.@"var";
    try expect(std.mem.eql(u8, decl.name, "start"));
    try expect(decl.value.* == Node.fn_decl);
    const fun = decl.value.fn_decl;
    try expect(fun.params.len == 0);
    const return_type_name = fun.return_type.*.field_access.name;
    std.debug.print("return type = '{s}'\n", .{ return_type_name });
    try expect(std.mem.eql(u8, return_type_name, "int"));
    // No body, the function just contains the literal integer. That is the implicit return value.
    const return_value = fun.body.integer.data;
    try expect(return_value == 1);
}

test "parse function body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var start = fn()->int { return SUCCESS; }");

    const root_node = node.type_decl;
    const field = root_node.fields[0];
    try expect(field == Node.@"var");
    const decl = field.@"var";
    try expect(std.mem.eql(u8, decl.name, "start"));
    try expect(decl.value.* == Node.fn_decl);
    const fun = decl.value.fn_decl;
    try expect(fun.params.len == 0);
    const return_type_name = fun.return_type.*.field_access.name;
    std.debug.print("return type = '{s}'\n", .{ return_type_name });
    try expect(std.mem.eql(u8, return_type_name, "int"));
    const return_statement = fun.body.body.nodes[0];
    try expect(return_statement == Node.@"return");
    const return_var_name = return_statement.@"return".?.field_access.name;
    try expect(std.mem.eql(u8, return_var_name, "SUCCESS"));
}

test "parse type declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub const var MyType = type { var x = 1\n var y = 2\n }");
    const root_node = node.type_decl;
    try expect(root_node.fields.len == 1);
    const decl = root_node.fields[0].@"var";
    try expect(std.mem.eql(u8, decl.name, "MyType"));
    const inner = decl.value.type_decl;
    try expect(inner.fields.len == 2);
}

test "parse field access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var start = fn()->void { System.out.println(); }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    const stmt = fun.body.body.nodes[0];
    try expect(stmt == .fn_invoke);
    try expect(std.mem.eql(u8, stmt.fn_invoke.name, "println"));
}

test "parse if statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn()->void { if (1) { return; } }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    const stmt = fun.body.body.nodes[0];
    try expect(stmt == .@"if");
    try expect(stmt.@"if".condition.* == .integer);
}

test "parse if-else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn()->void { if (1) { return; } else { return; } }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    const stmt = fun.body.body.nodes[0];
    try expect(stmt == .@"if");
    try expect(stmt.@"if".condition.* == .integer);
    try expect(stmt.@"if".branch_true.* == .body);
    try expect(stmt.@"if".branch_false != null);
    try expect(stmt.@"if".branch_false.?.* == .body);
}

test "parse elseif chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn()->void { if (1) { return; } elseif (2) { return; } else { return; } }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    const stmt = fun.body.body.nodes[0];
    try expect(stmt == .@"if");
    // elif is parsed as a nested if in branch_false
    const elif = stmt.@"if".branch_false.?;
    try expect(elif.* == .@"if");
    try expect(elif.@"if".condition.* == .integer);
    try expect(elif.@"if".condition.integer.data == 2);
    // the else is the elif's branch_false
    try expect(elif.@"if".branch_false != null);
}

test "parse multiple parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn(a: int, b: float)->void { return; }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    try expect(fun.params.len == 2);
    try expect(std.mem.eql(u8, fun.params[0].name, "a"));
    try expect(std.mem.eql(u8, fun.params[1].name, "b"));
}

test "parse return expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn()->int { return 42; }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    const stmt = fun.body.body.nodes[0];
    try expect(stmt == .@"return");
    try expect(stmt.@"return".?.* == .integer);
    try expect(stmt.@"return".?.integer.data == 42);
}

test "parse string literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "const var x = \"hello world\"");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    try expect(decl.value.* == .string);
    try expect(std.mem.eql(u8, decl.value.string.data, "hello world"));
}

test "parse array type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "pub var f = fn(args: []String)->void { return; }");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    const fun = decl.value.fn_decl;
    try expect(fun.params.len == 1);
    try expect(fun.params[0].type.* == .array_of);
}

test "parse builtin invocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const node = try lexAndParse(alloc, "const var S = [import](\"java/lang/String.class\")");
    const root_node = node.type_decl;
    const decl = root_node.fields[0].@"var";
    try expect(decl.value.* == .fn_invoke);
    try expect(decl.value.fn_invoke.builtin);
    try expect(std.mem.eql(u8, decl.value.fn_invoke.name, "import"));
}