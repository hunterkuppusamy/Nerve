const std = @import("std");
const root = @import("../root.zig");
const testing = std.testing;
const Diagnostics = root.Diagnostics;
const expect = testing.expect;
const tokenfile = @import("token.zig");
const Token = tokenfile.Token;
const SourceData = tokenfile.SourceData;
const TokenKind = tokenfile.TokenKind;
const TokenData = tokenfile.TokenData;

const log = std.log.scoped(.tokenizer);

pub const Tokenizer = struct {
    const Self = @This();

    // Parameters
    allocator: std.mem.Allocator,
    source: []const u8,

    // State
    i: usize = 0,
    position_row: usize = 1,
    position_col: usize = 1,
    diagnostics: Diagnostics = .{},
    is_commented: bool = false,

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
            const tok = try self.lex() orelse continue;
            try arr.append(self.allocator, tok);
            log.debug("tokenize: Lexed kind {s}.", .{@tagName(tok.kind)});
            i += 1;
        }

        return arr.toOwnedSlice(self.allocator);
    }

    fn lex(self: *Self) !?Token {
        const c: u8 = self.source[self.i];

        if (c == ' ') {
            self.position_col += 1;
            try self.increment();
            return null;
        } else if (std.ascii.isWhitespace(c)) {
            // Is new line.
            self.position_row += 1;
            try self.increment();
            self.is_commented = false;
            return null;
        }

        // Comment handling
        if (self.is_commented or (c == '/' and self.source[self.i + 1] == '/')) {
            self.is_commented = true;
            try self.increment();
            return null;
        }

        log.debug("lex: Lexing {c} ({})...", .{ c, c });
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

    fn nextChar(self: *Self) !u8 {
        try self.increment();
        return self.source[self.i];
    }

    fn increment(self: *Self) !void {
        self.i += 1;
        if (self.source.len < self.i) {
            self.diagnostics.err = .{
                .error_type = error.EOF,
                .error_line = self.position_row,
                .error_column = self.position_col,
                .error_message = "Unexpected end of file."
            };
            return Error.UnexpectedEndOfFile;
        }
    }

    fn lexKeywordOrIdentifier(self: *Self) !Token {
        var c = self.source[self.i]; // char from lex()
        const start_i = self.i;
        while (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
            c = self.nextChar() catch break;
        }

        const str = self.source[start_i..self.i];

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
    fn checkIdentIsKeyword(buf: root.STRING) ?TokenKind {
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
            log.debug("lexLiteralNumber: Invalid number of decimals {}.", .{decimals});
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
        // Stack alloc string buffer
        var buf: [1024]u8 = undefined;
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
                    else => buf[i] = '\\',
                }
                // Probably should be an error
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

        return .{
            .data = .{ .string = .{
                .slice = try self.allocator.dupe(u8, buf[0..i]),
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
                self.diagnostics.err = .{
                    .error_type = error.UnknownSpecialCharacter,
                    .error_line = self.position_row,
                    .error_column = self.position_col,
                    .error_message = "Reached unknown special character"
                };
                log.err("Unknown special char '{c}'\n", .{ c });
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
    const tok = (try lexer.lex()).?;
    try expect(tok.kind == TokenKind.identifier);
    try expect(tok.data == TokenData.string);
    try expect(std.mem.eql(u8, tok.data.string.slice, name));
}

test "lexing string" {
    const str = "hello";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = "\"" ++ str ++ "\"" };
    const tok = (try lexer.lex()).?;
    defer lexer.allocator.free(tok.data.string.raw.?);
    try expect(tok.kind == TokenKind.literal_string);
    try expect(std.mem.eql(u8, tok.data.string.slice, str));
}

test "lexing integer" {
    const int = "214";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = int ++ ";" };
    const tok = (try lexer.lex()).?;
    try expect(tok.kind == TokenKind.literal_integer);
    try expect(tok.data.integer == try std.fmt.parseInt(root.INTEGER, int, 10));
}

test "lexing float" {
    const pi = "3.141592";
    var lexer = Tokenizer{ .allocator = std.testing.allocator, .source = pi ++ ";" };
    const tok = (try lexer.lex()).?;
    try expect(tok.kind == TokenKind.literal_float);
    try expect(tok.data.float == try std.fmt.parseFloat(root.FLOAT, pi));
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


    for (tokens, 0..) |tok, i| {
        kinds[i] = tok.kind;
    }

    const expected = [_]TokenKind{
        .keyword_pub, .keyword_fn, .identifier, .open_paren, .identifier, .colon, .identifier, .close_paren, .right_arrow, .identifier, .open_brace, .keyword_return, .identifier, .period, .identifier, .open_paren, .close_paren, .semicolon, .close_brace };
    // check token data here too?
    try expect(std.mem.eql(TokenKind, &kinds, &expected));
}