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
    _ = @import("jvm/gen.zig");
    _ = @import("jvm/context.zig");
    _ = @import("jvm/import.zig");
    _ = @import("jvm/infer.zig");
    _ = @import("jvm/emit.zig");
    _ = @import("jvm/generate.zig");
    _ = @import("jvm/disasm.zig");
    _ = @import("jvm/format.zig");
    _ = @import("jvm/read.zig");
    _ = @import("jvm/write.zig");
    _ = @import("type.zig");
}

test "compile hello world" {
    const source =
        \\const var System = [import]("java/lang/System")
        \\const var String = [import]("java/lang/String")
        \\pub static const var main = fn(args: []String)->void {
        \\  var out = System.out;
        \\  out.println(out.toString());
        \\  out.println("hello");
        \\  return;
        \\}
        ;
    try compile(source, .{ .output = "test/out/Test.class" });
}

test "compile minimal" {
    const source =
        \\const var String = [import]("java/lang/String")
        \\pub static const var main = fn(args: []String)->void {
        \\  return;
        \\}
        ;
    try compile(source, .{ .output = "test/out/Minimal.class", .class_name = "Minimal" });
}

test "compile static functions" {
    const source =
        \\static const var Stringt = [import]("java/lang/String")
        \\static const var SystemOut = [import]("java/lang/System").out
        \\pub static const var main = fn(args: []Stringt)->void {
        \\  var string = get_string();
        \\  SystemOut.println(string.toString());
        \\  return;
        \\}
        \\pub static const var get_string = fn () -> Stringt {
        \\  return "String";
        \\}
        ;
    try compile(source, .{ .output = "test/out/StaticFunctions.class", .class_name = "StaticFunctions" });
}

pub const std_options = std.Options{
    .fmt_max_depth = 1000,
};

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

pub const CompileOptions = struct {
    output: []const u8 = "out/Main.class",
    class_name: []const u8 = "Main",
    jdk_path: []const u8 = "test/jdk",
};

pub fn compile(source: []const u8, options: CompileOptions) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try compileWithAllocator(gpa, source, options);
}

pub fn compileWithAllocator(gpa: std.mem.Allocator, source: []const u8, options: CompileOptions) !void {
    var tokenizer = lexer.Tokenizer.init(gpa, source);
    const tokens = try tokenizer.tokenize();
    var tokenParser = parser.Parser.init(gpa, tokens, source);
    const file = try tokenParser.parse();
    const file_owner = Node{
        .@"var" = .{
            .loc = .{ .line = 0, .src_start_ndx = 0, .src_end_ndx = 0 },
            .mods = .{ .constant = true, .public = true, .static = true },
            .name = options.class_name,
            .scope = .file,
            .type = null,
            .value = file,
        },
    };

    var global = try gen.GlobalContext.init(gpa, options.jdk_path);
    var file_ctx = try gen.FileContext.init(&global);
    var class_ctx = try gen.ClassContext.init(&file_ctx, options.class_name);

    // Type inference runs in a temporary FunctionContext (no bytecode emitted)
    var infer_fctx = try gen.FunctionContext.init(&class_ctx);
    defer infer_fctx.deinit();
    const generated = try infer_fctx.inferType(&file_owner);

    switch (generated.*) {
        .@"struct" => |*str| {
            try gen.generate(&class_ctx, str);
            try write.writeClassFile(options.output, class_ctx.class);
        },
        else => return error.CannotGenerateClassOfNonStructType,
    }
}