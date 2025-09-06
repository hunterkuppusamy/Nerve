const std = @import("std");
const lexer = @import("lexer.zig");

pub fn compile(source: []const u8) !void {
    const alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc.deinit();

    var l: lexer.Lexer = .{
        .source = source,
        .i = 0,
        .position_row = 0,
        .position_col = 0,
        .allocator = alloc
    };

    std.debug.print("Tokenizing...\n", .{});

    const tokens = try l.tokenize();

    const kinds = @typeInfo(lexer.TokenKind).@"enum".fields;

    std.debug.print("Kinds: ", .{});
    inline for (0..kinds.len) |i| {
        std.debug.print("{s} = {}, ", .{kinds[i].name, kinds[i].value});
    }

    std.debug.print("\n", .{});
    std.debug.print("Tokens: ", .{});
    for (tokens) |token| {
        std.debug.print("{s}", .{ @tagName(token.kind) });
        switch (token.kind) {
            .literal_string,
            .identifier => {
                const str = token.data.source_string;
                std.debug.print("={s} (", .{ str });
                for (str) |c| {
                    std.debug.print("{} ", .{ c });
                }
                std.debug.print(")", .{});
            },
            .literal_integer => {
                const i = token.data.signed_int;
                std.debug.print("={}", .{ i });
            },
            .literal_float => {
                const f = token.data.float;
                std.debug.print("={}", .{ f });
            },
            // no other data to print
            else => {}
        }
        std.debug.print(", ", .{});
    }
    std.debug.print("\n", .{});
}

test "include lexer" {
    _ = lexer.Lexer;
}