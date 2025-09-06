const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

pub const Lexer = struct {
    const Self = @This();

    // Parameters
    source: []const u8,
    allocator: std.mem.Allocator,

    // State
    i: usize = 0,
    position_row: usize = 1,
    position_col: usize = 1,
    diagnostics: Diagnostics = .{},

    // Testing
    initial_token_size: usize = 16,

    pub fn tokenize(self: *Self) ![]Token {
        var arr = try self.allocator.alloc(Token, self.initial_token_size);
        var i: usize = 0;
        self.i = 0;
        self.position_col = 0;
        self.position_row = 0;

        // While characters remain in the source
        // if there are extra characters some lex fn will throw.
        while (self.i < self.source.len) {
            const token = try self.lex();
            if (i >= arr.len) arr = try self.resizeTokens(arr);
            arr[i] = token;
            std.debug.print("tokenize: Lexed kind {s}\n", .{@tagName(token.kind)});
            i += 1;
        }

        return arr[0..i];
    }

    fn resizeTokens(self: *Self, arr: []Token) ![]Token {
        const ret = try self.allocator.alloc(Token, arr.len * 2);
        @memmove(ret, arr);
        self.allocator.free(arr);
        return ret;
    }

    fn lex(self: *Self) !Token {
        const c: u8 = self.source[self.i];
        // TODO: Seek until no whitespace and then lex; avoid recursion when the next character is guaranteed whitespace.
        if (isNewLineChar(c)) {
            self.position_row += 1;
            self.i += 1;
            return try self.lex();
        } else if (isWhitespace(c)) {
            self.position_col += 1;
            self.i += 1;
            return try self.lex();
        }

        std.debug.print("lex: Lexing {c} (0x{x})...\n", .{ c, c });
        return if (isLetter(c))
            self.lexKeywordOrIdentifier()
        else if (isNumber(c))
            self.lexLiteralNumber()
        else if (c == '"')
            self.lexLiteralString()
        else if (c == '\'')
            self.lexLiteralChar()
        else
            self.lexSpecial();
    }

    fn nextChar(self: *Self) !u8 {
        try self.incrementSourceIndex();
        return self.source[self.i];
    }

    fn incrementSourceIndex(self: *Self) !void {
        self.i += 1;
        if (self.i >= self.source.len) {
            self.diagnostics.err = .{
                .error_type = error.EOF,
                .error_line = self.position_row,
                .error_column = self.position_col,
                .error_message = "Unexpected end of file."
            };
            return error.EOF;
        }
    }

    fn lexKeywordOrIdentifier(self: *Self) !Token {
        var c = self.source[self.i]; // char from lex()
        const start_i = self.i;
        while (isLetter(c)) {
            c = self.nextChar() catch break;
        }

        const str = self.source[start_i..self.i];

        const kind = checkIdentIsKeyword(str) orelse cb: {
            break :cb TokenKind.identifier;
        };
        const ret: Token = .{ .data = .{ .source_string = str }, .kind = kind };
        return ret;
    }

    /// Return the keyword if true
    fn checkIdentIsKeyword(buf: []const u8) ?TokenKind {
        var kinds = [_]?TokenKind{
            .keyword_pub,
            .keyword_const,
            .keyword_struct,
            .keyword_enum,

            .keyword_fn,
            .keyword_var,

            .keyword_if,
            .keyword_else,
            .keyword_elseif,

            .keyword_while,
            .keyword_for,
            .keyword_break,
            .keyword_continue,

            .keyword_return,
        };
        var kindStrs = [_]?[]const u8{undefined} ** kinds.len;
        for (kinds, 0..) |key, i| {
            kindStrs[i] = @tagName(key.?)[8..];
        }

        var lastSeenKind: ?TokenKind = null;
        var nulls: u8 = 0;
        // is the best approach to check each character like this or just
        // linearly traverse the list of keywords...
        for (buf, 0..) |c, i| {
            for (kindStrs, 0..) |nstr, kindNdx| {
                const kindStr = nstr orelse {
                    nulls += 1;
                    continue;
                };
                if (c != 0 and (i >= kindStr.len or c != kindStr[i])) {
                    kindStrs[kindNdx] = null;
                    kinds[kindNdx] = null;
                    continue;
                }
                lastSeenKind = kinds[kindNdx];
            }

            if (kinds.len - nulls == 1) {
                return lastSeenKind;
            } else if (kinds.len - nulls == 0) {
                return null;
            }
        }

        return lastSeenKind;
    }

    fn lexLiteralNumber(self: *Self) !Token {
        var c = self.source[self.i]; // first number
        var decimals: u4 = 0;
        const start_i = self.i;

        while (isNumber(c)) {
            if (c == '.') decimals += 1;
            c = try self.nextChar();
        }

        const str = self.source[start_i..self.i];

        if (decimals > 1) {
            std.debug.print("lexLiteralNumber: Invalid number of decimals {}\n", .{decimals});
            self.diagnostics.err = .{
                .error_type = error.InvalidCharacter,
                .error_line = self.position_row,
                .error_column = self.position_col,
                .data = .{
                    .i = decimals
                }
            };
            return error.InvalidCharacter;
        } else if (decimals == 1) {
            const f = try std.fmt.parseFloat(f32, str);
            return .{ .data = .{
                .float = f,
            }, .kind = TokenKind.literal_float };
        } else {
            const n = try std.fmt.parseInt(i32, str, 10);
            return .{ .data = .{ .signed_int = n }, .kind = TokenKind.literal_integer };
        }
    }

    fn lexLiteralString(self: *Self) !Token {
        var c = self.source[self.i]; // opening quote
        self.i += 1;
        c = self.source[self.i];
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
        const str: []const u8 = buf[0 .. i - 1];

        return .{
            .data = .{ .heap_string = .{
                .slice = str,
                .raw = buf,
            } },
            .kind = TokenKind.literal_string,
        };
    }

    fn lexLiteralChar(self: *Self) Token {
        var c = self.source[self.i];
        self.i += 1;
        c = self.source[self.i];

        return .{ .data = .{ .char = c }, .kind = TokenKind.literal_integer };
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

            '.' => .period,
            ',' => .comma,
            ';' => .semicolon,
            '=' => .equals,
            '-' => arrow: {
                const ch = try self.nextChar();
                if (ch == '>') break :arrow .right_arrow else return error.UnknownSpecialCharacter;
            },
            else => {
                self.diagnostics.err = .{
                    .error_type = error.UnknownSpecialCharacter,
                    .error_line = self.position_row,
                    .error_column = self.position_col,
                    .error_message = "Reached unknown special character"
                };
                return error.UnknownSpecialCharacter;
            },
        };

        self.i += 1;

        return .{
            .data = .none,
            .kind = kind,
        };
    }

    fn isWhitespace(char: u8) bool {
        return char == ' ';
    }

    fn isNumber(char: u8) bool {
        return 0x30 <= char and char <= 0x39;
    }

    fn isLetter(char: u8) bool {
        return (char >= 0x41 and char <= 0x5A) // uppercase
        or (char >= 0x61 and char <= 0x7A); // lowercase
    }

    fn isNewLineChar(char: u8) bool {
        return char == '\n' or char == '\r';
    }

    pub const Diagnostics = struct {
        err: ?struct {
            error_type: anyerror,
            error_line: usize = undefined,
            error_column: usize = undefined,
            error_message: ?[*:0]const u8 = null,
            message_is_allocated: bool = false,
            data: ?union(enum) {
                token_data: TokenData,
                i: i32
            } = null,
        } = null,
    };
};

test "lexing identifier" {
    const name = "identifier";
    var lexer = Lexer{ .allocator = std.testing.allocator, .source = name ++ "()" };
    const token = try lexer.lex();
    try expect(token.kind != TokenKind.identifier);
    try expect(std.mem.eql(u8, token.data.source_string, name));
}

test "lexing string" {
    const str = "hello";
    var lexer = Lexer{ .allocator = std.testing.allocator, .source = "\"" ++ str ++ "\"" };
    const token = try lexer.lex();
    defer lexer.allocator.free(token.data.heap_string.raw);
    try expect(token.kind == TokenKind.literal_string);
    try expect(std.mem.eql(u8, token.data.heap_string.slice, str));
}

test "lexing integer" {
    const int = "214";
    var lexer = Lexer{ .allocator = std.testing.allocator, .source = int ++ "()" };
    const token = try lexer.lex();
    try expect(token.kind == TokenKind.literal_integer);
    try expect(token.data.signed_int == try std.fmt.parseInt(i32, int, 10));
}

test "lexing function body" {
    var lexer = Lexer{ .allocator = std.testing.allocator, .source = 
        \\pub fn helloWorld(
        \\    thing: Thing
        \\) -> Thing {
        \\    return thing.mutate();
        \\}
    };
    const tokens = try lexer.tokenize();
    defer lexer.allocator.free(tokens);
    var kinds = [_]TokenKind{undefined} ** 19;

    for (tokens, 0..) |token, i| {
        kinds[i] = token.kind;
    }

    const expected = [_]TokenKind{ .keyword_pub, .keyword_fn, .identifier, .open_paren, .identifier, .semicolon, .identifier, .close_paren, .right_arrow, .identifier, .open_brace, .keyword_return, .identifier, .period, .identifier, .open_paren, .close_paren, .semicolon, .close_brace };
    try expect(std.mem.eql(TokenKind, &kinds, &expected));
}

pub const Token = struct {
    data: TokenData,
    kind: TokenKind,
};

pub const TokenData = union(enum) {
    /// An allocated string slice, typically for literal_strings.
    /// This is because escape sequences lead to more than just
    /// source slices.
    heap_string: struct {
        /// A slice only containing the characters of the string
        slice: []const u8,
        /// The raw allocated array. Should be freed when finished.
        raw: *const [256:0]u8,
    },
    /// A string slice of the source
    source_string: []const u8,
    char: u8,
    signed_int: i32,
    unsigned_int: u32,
    float: f32,
    none,
};

pub const TokenKind = enum(u8) {
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
    semicolon,
    equals,

    right_arrow,

    keyword_pub, // declaration modifier

    keyword_const, // type or expression modifier

    identifier,

    keyword_struct,
    keyword_enum,

    keyword_fn, // declare function
    keyword_var, // declare variable

    keyword_if,
    keyword_else,
    keyword_elseif,
    // keyword_switch

    keyword_while,
    keyword_for,
    keyword_break,
    keyword_continue,

    keyword_return,
};