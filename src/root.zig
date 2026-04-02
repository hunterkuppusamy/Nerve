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
    _ = @import("notification.zig");
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

test "compile if statement" {
    const source =
        \\const var String = [import]("java/lang/String")
        \\const var System = [import]("java/lang/System")
        \\pub static const var main = fn(args: []String)->void {
        \\  var out = System.out;
        \\  if (1) {
        \\    out.println("true branch");
        \\  }
        \\  return;
        \\}
        ;
    try compile(source, .{ .output = "test/out/IfStatement.class", .class_name = "IfStatement" });
}

test "compile if-else statement" {
    const source =
        \\const var String = [import]("java/lang/String")
        \\const var System = [import]("java/lang/System")
        \\pub static const var main = fn(args: []String)->void {
        \\  var out = System.out;
        \\  if (1) {
        \\    out.println("yes");
        \\  } else {
        \\    out.println("no");
        \\  }
        \\  return;
        \\}
        ;
    try compile(source, .{ .output = "test/out/IfElse.class", .class_name = "IfElse" });
}

pub const std_options = std.Options{
    .fmt_max_depth = 1000,
};

pub const STRING = []const u8;
pub const HEAP_STRING = *const [256:0]u8;

pub const Notification = @import("notification.zig");

pub const CompileOptions = struct {
    output: []const u8 = "out/Main.class",
    class_name: []const u8 = "Main",
    jdk_path: []const u8 = "test/jdk",
    file_name: []const u8 = "<input>",
};

pub fn compile(source: []const u8, options: CompileOptions) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    try compileWithAllocator(gpa, source, options);
}

pub fn compileWithAllocator(gpa: std.mem.Allocator, source: []const u8, options: CompileOptions) !void {
    var notifications = try Notification.NotificationList.init(gpa, source);

    var tokenizer = lexer.Tokenizer.init(gpa, source);
    tokenizer.notifications = &notifications;
    const tokens = tokenizer.tokenize() catch {
        notifications.dump(options.file_name);
        return error.CompilationFailed;
    };

    var tokenParser = parser.Parser.init(gpa, tokens, source);
    tokenParser.notifications = &notifications;
    const file = tokenParser.parse() catch {
        notifications.dump(options.file_name);
        return error.CompilationFailed;
    };

    const file_owner = Node{
        .@"var" = .{
            .loc = .{},
            .mods = .{ .constant = true, .public = true, .static = true },
            .name = options.class_name,
            .scope = .file,
            .type = null,
            .value = file,
        },
    };

    var global = try gen.GlobalContext.init(gpa, options.jdk_path);
    global.notifications = &notifications;
    var file_ctx = try gen.FileContext.init(&global);
    var class_ctx = try gen.ClassContext.init(&file_ctx, options.class_name);

    var infer_fctx = try gen.FunctionContext.init(&class_ctx);
    defer infer_fctx.deinit();
    const generated = infer_fctx.inferType(&file_owner) catch |e| {
        notifications.err(.{}, "type inference failed: {s}", .{@errorName(e)});
        notifications.dump(options.file_name);
        return error.CompilationFailed;
    };

    switch (generated.*) {
        .@"struct" => |*str| {
            gen.generate(&class_ctx, str) catch |e| {
                notifications.err(.{}, "code generation failed: {s}", .{@errorName(e)});
                notifications.dump(options.file_name);
                return error.CompilationFailed;
            };
            try write.writeClassFile(options.output, class_ctx.class);
        },
        else => {
            notifications.err(.{}, "cannot generate a class file for a non-struct type", .{});
            notifications.dump(options.file_name);
            return error.CompilationFailed;
        },
    }

    if (notifications.items.items.len > 0) {
        notifications.dump(options.file_name);
    }
}