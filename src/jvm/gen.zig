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
    const Self = @This();
    allocator: std.mem.Allocator,
    types: std.StringHashMap(Type),

    pub fn importClass(self: *Self, class: *Class) !void {
        const t = try Type.ofClass(self.allocator, class);
        const name = t.@"struct".name;
        try self.types.put(name, type);
    }
};

/// Create jvm from a type
pub fn generate(
    program: *ProgramContext,
    /// 'objective' type
    owner: Node.VarDecl,
) !Class {
    const gpa = program.allocator;
    var class = Class {};
    var constant_pool = try ConstantPool.init(gpa, &class);

    class.constant_pool = try std.ArrayList(Class.Constant).initCapacity(gpa, 16);
    class.fields = try std.ArrayList(Class.FieldInfo).initCapacity(gpa, 16);
    class.methods = try std.ArrayList(Class.MethodInfo).initCapacity(gpa, 16);
    class.attributes = try std.ArrayList(Class.Attribute).initCapacity(gpa, 16);

    const class_constant = try constant_pool.add_class(owner.name);
    const super_class_constant = try constant_pool.add_class("java/lang/Object");
    const type_decl = owner.value.type_decl;

    for (type_decl.fields) |n| {
        const field = n.@"var";
        std.debug.print("generate: Generating field {s}.\n", .{ field.name });
        const field_type = field.type;

        if (field_type) |nn_field_type| switch (nn_field_type.*) {
            .type_decl => {
                std.debug.print("Inline type declarations are currently unsupported.\n", .{});
                return error.Unsupported;
            },
            else => {}
        };
        const name_h = try constant_pool.add_utf8(field.name);
        switch (field.value.*) {
            .fn_decl => |fun| {
                const r_jvm_name: []const u8 = try jvmTypeName(program, null, fun.return_type);
                const params = try program.allocator.alloc([]const u8, fun.params.len);
                for (fun.params, 0..) |p, i| {
                    const param_type_name = try jvmTypeName(program, null, p.type);
                    params[i] = try program.allocator.dupe(u8, param_type_name);
                }
                const desc_index = try constant_pool.add_utf8(try assembleMethodDesc(program, params, r_jvm_name));
                var code = try CodeContext.init(gpa, &constant_pool);
                switch (fun.body.*) {
                    .body => |b| {
                        try code.create(program, b.nodes);
                    },
                    else => {
                        try code.create(program, &.{ fun.body.* });
                    }
                }

                var flags = Class.MethodAccessFlags{};
                flags.public = field.mods.public;
                flags.static = false;
                flags.private = !field.mods.public;
                flags.protected = false;
                flags.final = field.mods.constant;

                try class.methods.append(program.allocator, .{
                    .name_index = @intCast(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = flags,
                    .attributes = attrs: {
                        const attrs = try program.allocator.alloc(Class.Attribute, 1);
                        attrs[0] = try code.toOwnedCode();
                        break :attrs attrs;
                    },
                });
            },
            .type_decl => {
                std.debug.print("Type declarations are unhandled, need support for emitting multiple .class files and then synthetically importing them.\n", .{});
                return error.Unsupported;
            },
            else => {
                const inferred = try bytecode.inferType(program, field.type) orelse try bytecode.inferType(program, null, field.value);
                const desc_index = try constant_pool.add_utf8(try jvmTypeName(program, null, ));
                var flags = Class.FieldAccessFlags{};
                flags.public = field.mods.public;
                flags.static = false;
                flags.private = !field.mods.public;
                flags.protected = false;
                flags.final = field.mods.constant;
                try class.fields.append(program.allocator, .{
                    .name_index = @truncate(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = flags,
                    .attributes = &[0]Class.Attribute{}
                });
            }
        }
    }

    class.this_class = @truncate(class_constant);
    class.super_class = @truncate(super_class_constant);

    return class;
}

pub fn assembleMethodDesc(program: *ProgramContext, params: [][]const u8, return_name: []const u8) ![]const u8 {
    var desc_len: usize = 2; // both parenthesis at either side is two chars no matter what.
    desc_len += return_name.len;
    for (params) |param| desc_len += param.len;
    const descriptor = try program.allocator.alloc(u8, desc_len);
    descriptor[0] = '(';
    var i: usize = 1; // start after first paren.
    for (params) |param| {
        @memcpy(descriptor[i..(i + param.len)], param);
        i += param.len;
    }
    descriptor[i] = ')';
    i += 1;
    @memcpy(descriptor[i..], return_name);
    return descriptor;
}

fn jvmTypeName(program: *ProgramContext, code: ?*CodeContext, node: *Node) ![]const u8 {
    switch (node.*) {
        .type_decl => {
            std.debug.print("Inline type declarations are currently unsupported.\n", .{});
            return error.Unsupported;
        },
        .field_access => |f| {
            const instance = f.instance.?;
            const this = try bytecode.inferType(program, code.?, instance);
            const field = this.@"struct".fieldByName(f.name) orelse return error.FieldNotFound;
            return try field.type.jvmName(program.allocator);
        },
        else => {
            return error.Unhandled;
        }
    }
}