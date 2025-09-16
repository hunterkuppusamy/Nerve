const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const terminal = @import("util/terminal.zig");
const r = @import("root");

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

test {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("bytecode_gen.zig");
    _ = @import("typechecker.zig");
}

pub const std_options = std.Options {
  .fmt_max_depth = 1000
};

// Im not convinced I want these for the string types...
pub const STRING = []const u8;
pub const HEAP_STRING = *const [256:0]u8;

pub const Diagnostics = struct {
    err: ?struct {
        error_type: anyerror,
        error_line: usize = undefined,
        error_column: usize = undefined,
        error_message: ?[*:0]const u8 = null,
        message_is_allocated: bool = false,
        data: ?union(enum) {
            token_data: lexer.TokenData,
            i: i32,
            u: usize,
        } = null,
    } = null,
};

pub fn compile(source: STRING) !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = gpa.allocator();
    defer {
        terminal.setColor(.foreground, .{ .attribute = .reset });
        std.log.info("Freeing compiler memory\n", .{});
        _ = gpa.deinit();
    }
    terminal.setColor(.underline, .{ .color = .black });
    terminal.setColor(.underline, .{ .color = .black });
    terminal.setColor(.foreground, .{ .color = .blue });

    var l: lexer.Lexer = .{
        .source = source,
        .i = 0,
        .position_row = 0,
        .position_col = 0,
        .allocator = alloc
    };

    std.debug.print("Tokenizing...\n", .{});

    const tokens = try l.tokenize();
    defer l.allocator.free(tokens);

    printTokens(tokens);

    //std.debug.print("Alignment of token = {}\n", .{ @alignOf(lexer.Token) });

    var p: parser.Parser = .{
        .allocator = alloc,
        .source = source,
        .tokens = tokens,
    };

    const parse_result = try p.parse();

    std.log.info("Parsed all tokens to one {s}.", .{ @tagName(parse_result.value) });

    terminal.setColor(.background, .{ .attribute = .italic });
    terminal.setColor(.foreground, .{ .color = .green });

    // -1 to negate the first body's indent
    parse_result.print(-1);
    std.debug.print("\n", .{});
}

fn printIndents(indents: isize) void {
    const v = if (indents < 0) 0 else indents;
    for (0..std.math.cast(usize, v).?) |_| {
        std.debug.print("  ", .{});
    }
}


fn printTokens(tokens: []lexer.Token) void {
    std.debug.print("Tokens: ", .{});
    for (tokens) |token| {
        std.debug.print("{s}", .{ @tagName(token.kind) });
        switch (token.data) {
            .string => {
                const str = token.data.string.slice;
                std.debug.print("={s} (", .{ str });
                for (str) |c| {
                    std.debug.print("{} ", .{ c });
                }
                std.debug.print(")", .{});
            },
            .char => std.debug.print("={c}", .{ token.data.char }),
            .float => std.debug.print("={any}", .{ token.data.float }),
            .integer => std.debug.print("={any}", .{ token.data.integer }),
            .u_integer => std.debug.print("={any}", .{ token.data.u_integer }),
            else => {},
        }
        std.debug.print(", ", .{});
    }
    std.debug.print("\n", .{});
}