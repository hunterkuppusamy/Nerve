const std = @import("std");
const root = @import("root.zig");
const testing = std.testing;
const expect = testing.expect;
const NotificationList = @import("notification.zig").NotificationList;

pub const Token = struct {
    source_data: SourceData,
    data: TokenData,
    kind: TokenKind,
};

pub const SourceData = struct {
    line: usize,
    column: usize,
    index: usize,
};

pub const StringData = struct {
    /// A slice only containing the characters of the string
        slice: root.STRING,
    /// The raw allocated array. Should be freed when finished.
        raw: ?root.HEAP_STRING = null,
};

pub const TokenData = union(enum) {
    /// An allocated string slice, typically for literal_strings.
    /// This is because escape sequences lead to more than just
    /// source slices.
    string: StringData,
    integer: root.INTEGER,
    u_integer: root.U_INTEGER,
    float: root.FLOAT,
    char: root.CHAR,
    bool: bool,
    none,
};

pub const TokenKind = enum(u8) {
    identifier,

    literal_string,
    literal_integer,
    literal_float,
    literal_bool,

    open_paren,
    close_paren,
    open_brace,
    close_brace,
    open_bracket,
    close_bracket,

    period,
    comma,
    colon,
    semicolon,
    equals, // assignment and equality, depending on number of occurrences

    right_arrow,

    keyword_pub, // declaration modifier
    keyword_const, // type or expression modifier
    keyword_static,

    keyword_struct,
    keyword_enum,

    keyword_fn, // declare function
    keyword_var, // declare variable
    keyword_type, // declare type

    keyword_if,
    keyword_elseif,
    keyword_else,
    // keyword_switch

    keyword_while,
    keyword_for,
    keyword_break,
    keyword_continue,

    keyword_return,

    operator_add,
    operator_add_assign,
    operator_sub,
    operator_sub_assign,
    operator_mul,
    operator_mul_assign,
    operator_div,
    operator_div_assign,

    operator_less_than,
    operator_greater_than,
};

pub const Tokenizer = struct {
    const Self = @This();

    // Parameters
    allocator: std.mem.Allocator,
    source: []const u8,

    // State
    i: usize = 0,
    position_row: usize = 1,
    position_col: usize = 1,
    is_commented: bool = false,
    notifications: ?*NotificationList = null,

    // Testing
    initial_token_size: usize = 16,

    pub fn init(gpa: std.mem.Allocator, source: []const u8) Tokenizer {
        return .{
            .allocator = gpa,
            .source = source,
        };
    }

    pub fn tokenize(self: *Self) ![]Token {
        var arr = try std.ArrayListAligned(Token, null).initCapacity(self.allocator, self.initial_token_size);
        var i: usize = 0;
        self.i = 0;
        self.position_col = 0;
        self.position_row = 0;

        // While characters remain in the source
        // if there are extra characters some lex fn will throw.
        while (self.i < self.source.len) {
            const token = try self.lex() orelse continue;
            try arr.append(self.allocator, token);
            std.debug.print("tokenize: Lexed kind {s}\n", .{@tagName(token.kind)});
            i += 1;
        }

        return arr.toOwnedSlice(self.allocator);
    }

    fn lex(self: *Self) !?Token {
        const c: u8 = self.source[self.i];

        if (c == ' ') {
            self.position_col += 1;
            self.increment();
            return null;
        } else if (std.ascii.isWhitespace(c)) {
            // Is new line.
            self.position_row += 1;
            self.increment();
            self.is_commented = false;
            return null;
        }

        // Comment handling
        if (self.is_commented or (c == '/' and self.source[self.i + 1] == '/')) {
            self.is_commented = true;
            self.increment();
            return null;
        }

        std.debug.print("lex: Lexing {c} ({})...\n", .{ c, c });
        return try if (std.ascii.isAlphabetic(c))
            self.lexKeywordOrIdentifier()
        else if (std.ascii.isDigit(c))
            self.lexLiteralNumber()
        else if (c == '"')
            self.lexLiteralString()
        else if (c == '\'')
            self.lexLiteralChar()
        else
            self.lexSpecial();
    }

    fn nextChar(self: *Self) Error!u8 {
        self.i += 1;
        if (self.i >= self.source.len) return Error.UnexpectedEndOfFile;
        return self.source[self.i];
    }

    fn increment(self: *Self) void {
        self.i += 1;
    }

    fn lexKeywordOrIdentifier(self: *Self) !Token {
        var c = self.source[self.i]; // char from lex()
        const start_i = self.i;
        while (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
            c = self.nextChar() catch break;
        }

        const str = self.source[start_i..self.i];

        if (std.mem.eql(u8, str, "false")) {
            return .{
                .source_data = self.currentSourceData(),
                .kind = .literal_bool,
                .data = .{ .bool = false }
            };
        } else if (std.mem.eql(u8, str, "true")) {
            return .{
                .source_data = self.currentSourceData(),
                .kind = .literal_bool,
                .data = .{ .bool = true }
            };
        }

        const keyword = checkIdentIsKeyword(str);
        if (keyword == null) return .{
            .kind = .identifier,
            .data = .{ .string = .{
                .slice = str,
            }},
            .source_data = self.currentSourceData()
        }
        else return .{ .kind = keyword.?, .data = .none, .source_data = self.currentSourceData() };
    }

    fn currentSourceData(self: *Self) SourceData {
        return .{
            .column = self.position_col,
            .line = self.position_row,
            .index = self.i,
        };
    }

    /// Return the keyword if true
    fn checkIdentIsKeyword(buf: []const u8) ?TokenKind {
        const keywords = comptime select: {
            var keyword_slice = [_]TokenKind{ undefined } ** @typeInfo(TokenKind).@"enum".fields.len;
            var i: usize = 0;
            const keyword_prefix = "keyword_";
            for (@typeInfo(TokenKind).@"enum".fields) |f| {
                if (f.name.len >= keyword_prefix.len and std.mem.eql(u8, keyword_prefix, f.name[0..keyword_prefix.len])) {
                    keyword_slice[i] = @enumFromInt(f.value);
                    i += 1;
                }
            }
            var only_keywords = [_]TokenKind{undefined} ** i;
            @memmove(&only_keywords, keyword_slice[0..i]);
            break :select only_keywords;
        };
        for (keywords) |keyword| {
            const keyword_name = @tagName(keyword)[8..];
            if (std.mem.eql(u8, keyword_name, buf)) return keyword;
        }

        return null;
    }

    fn lexLiteralNumber(self: *Self) !Token {
        var c = self.source[self.i]; // first number
        var decimals: u4 = 0;
        const start_i = self.i;

        while (std.ascii.isDigit(c) or c == '.') {
            if (c == '.') decimals +|= 1;
            c = self.nextChar() catch |e| {
                if (e == Error.UnexpectedEndOfFile) break
                else return e;
            };
        }

        const str = self.source[start_i..self.i];

        if (decimals > 1) {
            if (self.notifications) |n| n.err(
                .{ .line = self.position_row, .column = self.position_col },
                "invalid number literal: too many decimal points",
                .{},
            );
            return error.InvalidCharacter;
        } else if (decimals == 1) {
            const f = try std.fmt.parseFloat(root.FLOAT, str);
            return .{ .data = .{
                .float = f,
            }, .kind = TokenKind.literal_float, .source_data = self.currentSourceData() };
        } else {
            const n = try std.fmt.parseInt(root.INTEGER, str, 10);
            return .{ .data = .{ .integer = n }, .kind = TokenKind.literal_integer, .source_data = self.currentSourceData() };
        }
    }

    fn lexLiteralString(self: *Self) !Token {
        var c = self.source[self.i]; // opening quote
        self.i += 1;
        c = self.source[self.i];
        // mutable HEAP_STRING
        var buf: *[256:0]u8 = @ptrCast((try self.allocator.alloc(u8, 256)).ptr);
        var i: u8 = 0;
        var escaped = false;

        while (true) {
            if (!escaped) switch (c) {
                '\\' => {
                    escaped = true;
                    i -= 1;
                },
                '"' => break,
                else => buf[i] = c,
            } else {
                switch (c) {
                    'n' => buf[i] = '\n',
                    'r' => buf[i] = '\r',
                    else => {},
                }
                // If not a valid escape sequence nothing happens
                escaped = false;
            }

            i += 1;
            self.i += 1;
            c = self.source[self.i];
        }

        // last quote.
        self.i += 1;
        // null terminator
        buf[i] = 0;
        i += 1;

        // doesnt include the null terminator; there is no need
        const str: root.STRING = buf[0 .. i - 1];

        return .{
            .data = .{ .string = .{
                .slice = str,
                .raw = buf,
            } },
            .kind = TokenKind.literal_string,
            .source_data = self.currentSourceData()
        };
    }

    fn lexLiteralChar(self: *Self) Token {
        var c = self.source[self.i];
        self.i += 1;
        c = self.source[self.i];

        return .{ .data = .{ .char = c }, .kind = TokenKind.literal_integer, .source_data = self.currentSourceData() };
    }

    fn lexSpecial(self: *Self) !Token {
        const c = self.source[self.i];
        const kind: TokenKind = switch (c) {
            '(' => .open_paren,
            ')' => .close_paren,
            '{' => .open_brace,
            '}' => .close_brace,
            '[' => .open_bracket,
            ']' => .close_bracket,

            '+' => .operator_add,
            '*' => .operator_mul,
            '/' => .operator_div,

            '.' => .period,
            ',' => .comma,
            ':' => .colon,
            ';' => .semicolon,
            '=' => .equals,
            '<' => .operator_less_than,
            '>' => .operator_greater_than,
            '-' => arrow: {
                const ch = self.source[self.i + 1];
                if (ch == '>') {
                    _ = try self.nextChar();
                    break :arrow .right_arrow;
                }
                else break :arrow .operator_sub;
            },
            else => {
                if (self.notifications) |n| n.err(
                    .{ .line = self.position_row, .column = self.position_col },
                    "unexpected character '{c}'",
                    .{c},
                );
                return error.UnknownSpecialCharacter;
            },
        };

        self.i += 1;

        return .{
            .data = .none,
            .kind = kind,
            .source_data = self.currentSourceData()
        };
    }

    pub const Error = error {
        UnexpectedEndOfFile
    };
};

test "lexing identifier" {
    const name = "identifier";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = name ++ ";" };
    const token = (try lexer.lex()).?;
    try expect(token.kind == TokenKind.identifier);
    try expect(token.data == TokenData.string);
    try expect(std.mem.eql(u8, token.data.string.slice, name));
}

test "lexing string" {
    const str = "hello";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "\"" ++ str ++ "\"" };
    const token = (try lexer.lex()).?;
    defer lexer.allocator.free(token.data.string.raw.?);
    try expect(token.kind == TokenKind.literal_string);
    try expect(std.mem.eql(u8, token.data.string.slice, str));
}

test "lexing integer" {
    const int = "214";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = int ++ ";" };
    const token = (try lexer.lex()).?;
    try expect(token.kind == TokenKind.literal_integer);
    try expect(token.data.integer == try std.fmt.parseInt(root.INTEGER, int, 10));
}

test "lexing float" {
    const pi = "3.141592";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = pi ++ ";" };
    const token = (try lexer.lex()).?;
    try expect(token.kind == TokenKind.literal_float);
    try expect(token.data.float == try std.fmt.parseFloat(root.FLOAT, pi));
}

test "lexing function body" {
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source =
        \\pub fn helloWorld(
        \\    thing: Thing
        \\) -> Thing {
        \\    return thing.mutate();
        \\}
    };
    const tokens = try lexer.tokenize();
    defer std.testing.allocator.free(tokens);
    var kinds = [_]TokenKind{undefined} ** 19;


    for (tokens, 0..) |token, i| {
        kinds[i] = token.kind;
    }

    const expected = [_]TokenKind{
        .keyword_pub, .keyword_fn, .identifier, .open_paren, .identifier, .colon, .identifier, .close_paren, .right_arrow, .identifier, .open_brace, .keyword_return, .identifier, .period, .identifier, .open_paren, .close_paren, .semicolon, .close_brace };
    try expect(std.mem.eql(TokenKind, &kinds, &expected));
}

test "lexing keywords" {
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "const var if else return static" };
    const tokens = try lexer.tokenize();
    defer std.testing.allocator.free(tokens);
    try expect(tokens.len == 6);
    try expect(tokens[0].kind == .keyword_const);
    try expect(tokens[1].kind == .keyword_var);
    try expect(tokens[2].kind == .keyword_if);
    try expect(tokens[3].kind == .keyword_else);
    try expect(tokens[4].kind == .keyword_return);
    try expect(tokens[5].kind == .keyword_static);
}

test "lexing operators" {
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "a + b - c * d" };
    const tokens = try lexer.tokenize();
    defer std.testing.allocator.free(tokens);
    try expect(tokens.len == 7);
    try expect(tokens[1].kind == .operator_add);
    try expect(tokens[3].kind == .operator_sub);
    try expect(tokens[5].kind == .operator_mul);
}

test "lexing arrow and brackets" {
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "[]()->{}" };
    const tokens = try lexer.tokenize();
    defer std.testing.allocator.free(tokens);
    try expect(tokens.len == 7);
    try expect(tokens[0].kind == .open_bracket);
    try expect(tokens[1].kind == .close_bracket);
    try expect(tokens[2].kind == .open_paren);
    try expect(tokens[3].kind == .close_paren);
    try expect(tokens[4].kind == .right_arrow);
    try expect(tokens[5].kind == .open_brace);
    try expect(tokens[6].kind == .close_brace);
}

test "lexing import expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lexer = Tokenizer{ .allocator = arena.allocator(), .source =
        \\const var System = [import]("java/lang/System.class")
    };
    const tokens = try lexer.tokenize();
    try expect(tokens.len == 10);
    try expect(tokens[0].kind == .keyword_const);
    try expect(tokens[1].kind == .keyword_var);
    try expect(tokens[2].kind == .identifier);
    try expect(tokens[3].kind == .equals);
    try expect(tokens[4].kind == .open_bracket);
    try expect(tokens[5].kind == .identifier);
    try expect(tokens[6].kind == .close_bracket);
    try expect(tokens[7].kind == .open_paren);
    try expect(tokens[8].kind == .literal_string);
    try expect(tokens[9].kind == .close_paren);
}

test "lexing negative integer" {
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "-42;" };
    const tokens = try lexer.tokenize();
    defer std.testing.allocator.free(tokens);
    try expect(tokens[0].kind == .operator_sub);
    try expect(tokens[1].kind == .literal_integer);
    try expect(tokens[1].data.integer == 42);
}