const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Op = format.Op;
const root = @import("root");
const Type = @import("../type.zig").Type;
const Node = @import("../AST.zig").Node;
const Stack = @import("util").Stack;
const Tokenizer = @import("../tokenizer.zig").Tokenizer;
const Parser = @import("../parser.zig").Parser;
const ConstantPool = @import("../ConstantPool.zig");
const bytecode = @import("bytecode.zig");
const CodeContext = bytecode.CodeContext;

pub const ProgramContext = struct {
    allocator: std.mem.Allocator,
    types: std.StringHashMap(Type),

    pub fn submitBytecode(bytes: []const u8) !void {
        _ = bytes;
    }
};

/// Create jvm from a type
pub fn generate(
    allocator: std.mem.Allocator,
    /// 'objective' type
    typ: Type.Struct
) !Class {
    var class = Class {};
    var constant_pool = try ConstantPool.init(allocator, &class);

    class.constant_pool = try std.ArrayList(Class.Constant).initCapacity(allocator, 16);
    class.fields = try std.ArrayList(Class.FieldInfo).initCapacity(allocator, 16);
    class.methods = try std.ArrayList(Class.MethodInfo).initCapacity(allocator, 16);
    class.attributes = try std.ArrayList(Class.Attribute).initCapacity(allocator, 16);

    const class_constant = try constant_pool.add_class(typ.name);
    const super_class_constant = try constant_pool.add_class("java/lang/Object");

    for (typ.fields) |field| {
        std.debug.print("generate: Generating field {s}.\n", .{ field.name });
        const field_type = field.type;
        const name_h = try constant_pool.add_utf8(field.name);
        switch (field_type.*) {
            .@"fn" => |fun| {
                const params = try allocator.alloc([]const u8, fun.params.len);
                var d_size: usize = 2; // both parenthesis at either side is two chars no matter what.
                const r_jvm_name = try fun.return_type.jvmName(allocator);
                d_size += r_jvm_name.len;
                for (fun.params, 0..) |p, i| {
                    const jvm_name = try p.type.jvmName(allocator);
                    d_size += jvm_name.len;
                    params[i] = jvm_name;
                }
                const descriptor = try allocator.alloc(u8, d_size);
                descriptor[0] = '(';
                var i: usize = 1; // start after first paren.
                for (params) |d_e| {
                    @memcpy(descriptor[i..(i + d_e.len)], d_e);
                    i += d_e.len;
                }
                descriptor[i] = ')';
                i += 1;
                @memcpy(descriptor[i..], r_jvm_name);
                const d_h = try constant_pool.add_utf8(descriptor);
                var code = try CodeContext.init(allocator, &constant_pool);
                try code.create(fun.body);

                var flags = Class.MethodAccessFlags{};
                flags.public = field.access.public;
                flags.static = field.access.static;
                flags.private = field.access.private;
                flags.protected = field.access.protected;
                flags.final = field.access.final;

                try class.methods.append(allocator, .{
                    .name_index = @intCast(name_h),
                    .descriptor_index = @intCast(d_h),
                    .access_flags = flags,
                    .attributes = attrs: {
                        const attrs = try allocator.alloc(Class.Attribute, 1);
                        attrs[0] = try code.toOwnedCode();
                        break :attrs attrs;
                    },
                });
            },
            else => {
                const d_h = try constant_pool.add_utf8(try field_type.jvmName(allocator));
                try class.fields.append(allocator, .{
                    .name_index = @truncate(name_h),
                    .descriptor_index = @intCast(d_h),
                    .access_flags = @bitCast(field.access),
                    .attributes = &[0]Class.Attribute{}
                });
            }
        }
    }

    class.this_class = @truncate(class_constant);
    class.super_class = @truncate(super_class_constant);

    return class;
}


test "generation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const source = \\fn fake_main() -> void {
                   \\var a = 13249320;
                   \\var class = [import]("java/lang/System");
                   \\return;
                   \\}
    ;
    var token = Tokenizer.init(alloc, source);
    const tokens = try token.tokenize();
    var parse = Parser.init(alloc, tokens, source);
    const nodes = try parse.parse();

    const int_type: Type = Type.int;
    const void_type: Type = Type.void;
    const main_fn = Type {
        .@"fn" = .{
            .params = &[_]Type.Fn.Param{
                Type.Fn.Param {
                    .name = "args",
                    .type = &Type {
                        .array = .{
                            .elements = &Type { .@"extern" = .{
                                .jvm_class = "java/lang/String"
                            } }
                        }
                    }
                }
            },
            .return_type = &void_type,
            .body = nodes.body.nodes[0].fn_decl.body.body.nodes,
        }
    };
    const strct = Type.Struct {
        .name = "Main",
        .fields = &[_]Type.Struct.Field{
            Type.Struct.Field{
                .name = "my_field",
                .type = &int_type,
                .access = .{
                    .public = true,
                }
            },
            Type.Struct.Field{
                .name = "main",
                .type = &main_fn,
                .access = .{
                    .public = true,
                    .static = true,
                }
            },
        }
    };

    const cf = try generate(alloc, strct);

    var buf: [2048]u8 = undefined;
    var file = try std.fs.cwd().createFile("test/Main.class", .{.lock = .exclusive,});
    defer file.close();
    var fs = file.writer(&buf);
    var w = &fs.interface;
    try @import("write.zig").writeClass(w, cf);
    try w.flush();
}