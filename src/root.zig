const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const r = @import("root");

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

test {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
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
        std.log.info("Freeing compiler memory\n", .{});
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
        .source = source,
        .tokens = my_tokens,
    };

    const parse_result = try p.parse();
    std.log.info("Parsed all tokens to one {s}.", .{ @tagName(parse_result.value) });

    // -1 to negate the first body's indent
    printNode(parse_result, -1);
}

fn printIndents(indents: isize) void {
    const v = if (indents < 0) 0 else indents;
    for (0..std.math.cast(usize, v).?) |_| {
        std.debug.print("  ", .{});
    }
}

fn printNode(node: *const parser.Node, indents: isize) void {
    switch (node.value) {
        .binary_op => {
            printNode(node.value.binary_op.lhs, indents);
            const o = switch (node.value.binary_op.op) {
                .add => "+", .adda => "+=",
                .sub => "-", .suba => "-=",
                .div => "/", .diva => "/=",
                .mul => "*", .mula => "*=",

                .gt => ">", .gte => ">=",
                .lt => "<", .lte => "<=",
                //else => "???"
            };
            std.debug.print(" {s} ", .{ o });
            printNode(node.value.binary_op.rhs, indents);
        },
        .unary_op => {
            const o: u8 = switch (node.value.unary_op.op) {
                .negate => '-',
            };
            std.debug.print("{c}", .{ o });
            printNode(node.value.unary_op.rhs, indents);
        },
        .make_var => {
            printIndents(indents);
            const make = node.value.make_var;
            std.debug.print("var ", .{});
            if (make.mods.constant) {
                std.debug.print("const ", .{});
            }
            std.debug.print("{s}", .{ make.name.data.string.slice });
            if (make.typ != null) {
                std.debug.print(": ", .{});
                printNode(make.typ.?, indents);
            } else {
                std.debug.print(": ?", .{});
            }
            std.debug.print(" = ", .{});
            printNode(make.value, indents);
        },
        .function_decl => {
            printIndents(indents);
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
                printNode(p.value.function_param.type, indents);
            }
            std.debug.print(") -> ", .{});
            printNode(fun.return_type, indents);
            if (fun.body.value != parser.NodeValue.body) {
                std.debug.print(" = ", .{});
                printNode(fun.body, indents);
                return;
            }
            std.debug.print(" {{", .{});
            printNode(fun.body, indents);
            std.debug.print("\n}}", .{});
        },
        .return_expr => {
            printIndents(indents);
            std.debug.print("return ", .{});
            printNode(node.value.return_expr, indents);
        },
        .body => {
            printIndents(indents);
            const body = node.value.body;
            std.debug.print("\n", .{});
            for (body.nodes, 0..) |n, i| {
                printNode(&n, indents + 1);
                if (body.nodes.len - 1 == i) {
                    std.debug.print(";", .{});
                } else {
                    std.debug.print(";\n", .{});
                }
            }
        },
        ._if => {
            printIndents(indents);
            const _if = node.value._if;
            std.debug.print("if (", .{});
            printNode(_if.condition, indents + 1);
            std.debug.print(") {{", .{});
            printNode(_if.if_true, indents);
            std.debug.print("\n", .{});
            printIndents(indents);
            std.debug.print("}}", .{});
            if (_if.if_false == null) return;
            std.debug.print(" else ", .{});
            if (_if.if_false.?.*.value == parser.NodeValue.body) {
                std.debug.print("{{", .{});
                printNode(_if.if_false.?, indents);
                std.debug.print("\n", .{});
                printIndents(indents);
                std.debug.print("}}", .{});
            } else {
                printNode(_if.if_false.?, indents);
            }
        },
        .function_invoke => {
            const f = node.value.function_invoke;
            printNode(f.namespace, indents);
            std.debug.print("(", .{});
            for (f.args) |a| {
                printNode(&a, indents);
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