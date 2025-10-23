const std = @import("std");
const lexer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const gen = @import("jvm/gen.zig");
const Node = @import("AST.zig").Node;
const terminal = @import("util").terminal;
const write = @import("jvm/write.zig");
const Type = @import("type.zig").Type;

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

test {
    _ = @import("tokenizer.zig");
    _ = @import("parser.zig");
    _ = @import("ConstantPool.zig");
    _ = @import("jvm/bytecode.zig");
    _ = @import("jvm/gen.zig");
    _ = @import("jvm/format.zig");
    _ = @import("jvm/read.zig");
    _ = @import("jvm/write.zig");
}

test "full" {
    const source =
        \\const var System = [import]("test/java/lang/System.class")
        \\const var String = [import]("test/java/lang/String.class")
        \\pub const var MyType = type {
        \\  var int = 1
        \\  var main = fn(args: String)->void {
        \\      var this = MyType();
        \\      System.out.println("hello");
        \\  }
        \\  var fifteen = fn(int:Int)->Int = int + 15
        \\}
        ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var tokenizer = lexer.Tokenizer.init(gpa, source);
    const tokens = try tokenizer.tokenize();
    var tokenParser = parser.Parser.init(gpa, tokens, source);
    const file = try tokenParser.parse();
    const file_owner = Node {
        .@"var" = .{
            .loc = .{ .line = 0, .src_start_ndx = 0, .src_end_ndx = 0 },
            .mods = .{ .constant = true, .public = true, .static = true, },
            .name = "file_name",
            .scope = .file,
            .type = null,
            .value = file
        }
    };
    var context = try gen.CodegenContext.init(gpa, "test/jdk");
    const generated = context.inferType(&file_owner) catch |e| {
        std.debug.print("Error while generating type.\n", .{});
        return e;
    };
    switch (generated.*) {
        .@"struct" => |*str| {
            try gen.generate(&context, str);
            try write.writeClassFile("test/Main.class", context.class);
        },
        else => {
            std.debug.print("Cannot generate a class file for a type that is not a struct.\n", .{});
            return error.CannotGenerateClassOfNonStructType;
        }
    }
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

pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_name: []const u8,
    jdk_path: []const u8,
    output_path: []const u8
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var tokenizer = lexer.Tokenizer.init(gpa, source);
    const tokens = try tokenizer.tokenize();
    var tokenParser = parser.Parser.init(gpa, tokens, source);
    const file = try tokenParser.parse();
    const file_owner = Node {
        .@"var" = .{
            .loc = .{ .line = 0, .src_start_ndx = 0, .src_end_ndx = 0 },
            .mods = .{ .constant = true, .public = true, .static = true, },
            .name = file_name,
            .scope = .file,
            .type = null, // infer / generate from decl
            .value = file
        }
    };
    var context = try gen.CodegenContext.init(gpa, jdk_path);
    const generated = context.inferType(&file_owner) catch |e| {
        std.debug.print("Error while generating type.\n", .{});
        return e;
    };
    switch (generated.*) {
        .@"struct" => |*str| {
            try gen.generate(&context, str);
            try write.writeClassFile(output_path, context.class);
        },
        else => {
            std.debug.print("Cannot generate a class file for a type that is not a struct.\n", .{});
            return error.CannotGenerateClassOfNonStructType;
        }
    }
}