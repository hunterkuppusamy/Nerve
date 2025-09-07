const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const r = @import("root");

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

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

}

fn printNode(node: *const parser.Node) void {
    switch (node.value) {
        .binary_op => {
            printNode(node.value.binary_op.lhs);
            const o: u8 = switch (node.value.binary_op.op) {
                .add => '+',
                .sub => '-',
                .div => '/',
                .mul => '*'
            };
            std.debug.print(" {c} ", .{ o });
            printNode(node.value.binary_op.rhs);
        },
        .unary_op => {
            const o: u8 = switch (node.value.unary_op.op) {
                .negate => '-',
            };
            std.debug.print("{c}", .{ o });
            printNode(node.value.unary_op.rhs);
        },
        .make_var => {
            const make = node.value.make_var;
            std.debug.print("var ", .{});
            if (make.mods.constant) {
                std.debug.print("const ", .{});
            }
            std.debug.print("{s}", .{ make.name.data.string.slice });
            if (make.typ != null) {
                std.debug.print(": ", .{});
                printNode(make.typ.?);
            } else {
                std.debug.print(": ?", .{});
            }
            std.debug.print(" = ", .{});
            printNode(make.value);
        },
        .function_decl => {
            const fun = node.value.function_decl;
            if (fun.mods.public) {
                std.debug.print("pub ", .{});
            }
            if (fun.mods.constant) {
                std.debug.print("const ", .{});
            }
            std.debug.print("fn {s}(", .{fun.name.data.string.slice});
            for (fun.params) |p| {
                std.debug.print("{s}: ", .{p.value.function_param.name.data.string.slice});
                printNode(p.value.function_param.type);
            }
            std.debug.print(") -> ", .{});
            printNode(fun.return_type);
            if (fun.body.value != parser.NodeValue.body) {
                std.debug.print(" = ", .{});
                printNode(fun.body);
                return;
            }
            std.debug.print(" {{", .{});
            for (fun.body.value.body.nodes) |line| {
                std.debug.print("\n", .{});
                printNode(&line);
                std.debug.print(";", .{});
            }
            std.debug.print("\n}}\n", .{});
        },
        .return_expr => {
            std.debug.print("return ", .{});
            printNode(node.value.return_expr);
        },
        .function_invoke => {
            const f = node.value.function_invoke;
            printNode(f.namespace);
            std.debug.print("(", .{});
            for (f.args) |a| {
                printNode(&a);
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
        .integer => {
            std.debug.print("{}", .{ node.value.integer });
        },
        else => std.debug.print("|{any}|", .{ node.value })
    }
}

fn printTokens(tokens: std.ArrayList(lexer.Token)) void {
    std.debug.print("Tokens: ", .{});
    for (tokens.items) |token| {
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

test "include lexer" {
    _ = lexer.Lexer;
}