const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

pub const std_options: std.Options = .{
  .fmt_max_depth = 100
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
            i: i32
        } = null,
    } = null,
};

pub fn compile(source: STRING) !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = gpa.allocator();
    defer {
        std.log.info("Freeing compiling memory\n", .{});
        _ = gpa.deinit();
    }

    var l: lexer.Lexer = .{
        .source = source,
        .i = 0,
        .position_row = 0,
        .position_col = 0,
        .allocator = alloc
    };

    std.debug.print("Tokenizing...\n", .{});

    var tokens = try l.tokenize();
    defer tokens.deinit(l.allocator);

    printTokens(tokens);

    //std.debug.print("Alignment of token = {}\n", .{ @alignOf(lexer.Token) });

    const my_tokens = tokens.items;

    var p: parser.Parser = .{
        .allocator = alloc,
        .source = my_tokens,
    };

    const node = try p.parse();

    std.debug.print("Parsed tokens.\n", .{});
    printNode(node);

    freeNode(node, p.allocator);
}

fn freeNode(node: *parser.Node, alloc: std.mem.Allocator) void {
    switch (node.value) {
        .binary_op => {
            alloc.destroy(node.value.binary_op.lhs);
            alloc.destroy(node.value.binary_op.rhs);
        },
        else => {}
    }

    alloc.destroy(node);
}

fn printNode(node: *parser.Node) void {
    switch (node.value) {
        .binary_op => {
            std.debug.print("(", .{});
            printNode(node.value.binary_op.lhs);
            std.debug.print(" {s} ", .{ @tagName(node.value.binary_op.op) });
            printNode(node.value.binary_op.rhs);
            std.debug.print(")", .{});
        },
        .unary_op => {
            std.debug.print("(", .{});
            std.debug.print("{s} ", .{ @tagName(node.value.unary_op.op) });
            printNode(node.value.unary_op.rhs);
            std.debug.print(")", .{});
        },
        .integer => {
            std.debug.print("{}", .{ node.value.integer });
        },
        else => std.debug.print("{any} ", .{ node.value })
    }
}

fn printTokens(tokens: std.ArrayList(lexer.Token)) void {
    std.debug.print("Tokens: ", .{});
    for (tokens.items) |token| {
        std.debug.print("{s}", .{ @tagName(token.kind) });
        switch (token.data) {
            .heap_string => {
                const str = token.data.heap_string.slice;
                std.debug.print("={s} (", .{ str });
                for (str) |c| {
                    std.debug.print("{} ", .{ c });
                }
                std.debug.print(")", .{});
            },
            .source_string => {
                const str = token.data.source_string;
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

test "include lexer" {
    _ = lexer.Lexer;
}