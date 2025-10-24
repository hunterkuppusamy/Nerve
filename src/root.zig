const std = @import("std");
const tokengen = @import("core/tokengen.zig");
const tokenfile = @import("core/token.zig");
const Token = tokenfile.Token;
const astgen = @import("core/astgen.zig");
const gen = @import("jvm/classgen.zig");
const Node = @import("core/ast.zig").Node;
const terminal = @import("util").terminal;
const write = @import("jvm/write.zig");
const Type = @import("type.zig").Type;

pub const INTEGER = i32;
pub const U_INTEGER = u32;
pub const FLOAT = f32;
pub const CHAR = u8;

test {
    _ = @import("core/tokengen.zig");
    _ = @import("core/astgen.zig");
    _ = @import("ConstantPool.zig");
    _ = @import("jvm/bytecode.zig");
    _ = @import("jvm/classgen.zig");
    _ = @import("jvm/class.zig");
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

    var tokenizer = tokengen.Tokenizer.init(gpa, source);
    const tokens = try tokenizer.tokenize();
    var tokenParser = astgen.Parser.init(gpa, tokens, source);
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
            token_data: tokenfile.TokenData,
            i: i32,
            u: usize,
        } = null,
    } = null,
};

pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    jdk_path: []const u8,
    output_path: []const u8
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var tokenizer = @import("core/tokengen.zig").Tokenizer.init(gpa, source);
    const tokens = try tokenizer.tokenize();

    var parser = astgen.Parser.init(gpa, tokens, source);
    const file = try parser.parse();

    const file_name_cut = std.mem.cutScalarLast(u8, file_path, '/');
    const file_name = if (file_name_cut) |f| f.@"1" else file_path;
    var type_name = if (std.mem.endsWith(u8, file_name, ".nerve")) file_name[0..file_name.len - 6] else {
        return terminal.logErr(error.BadFileName, "Nerve source file must end with .nerve (got '{s}').", .{ file_name });
    };

    if (std.mem.eql(u8, type_name, "main")) {
        type_name = "Main";
    }

    const file_owner = Node {
        .@"var" = .{
            .loc = .{ .line = 0, .src_start_ndx = 0, .src_end_ndx = 0 },
            .mods = .{ .constant = true, .public = true, .static = true, },
            .name = type_name,
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
            write.writeClassFile(output_path, context.class) catch |e| {
                return terminal.logErr(e, "Could not write to output file '{s}'.", .{ output_path });
            };
        },
        else => {
            std.debug.print("Cannot generate a class file for a type that is not a struct.\n", .{});
            return error.CannotGenerateClassOfNonStructType;
        }
    }
}