const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Type = @import("../type.zig").Type;
const ctx = @import("context.zig");
const ClassContext = ctx.ClassContext;
const FunctionContext = ctx.FunctionContext;
const emit = @import("emit.zig");

pub fn generate(cctx: *ClassContext, struct_type: *const Type.Struct) !void {
    const gpa = cctx.allocator();

    const class_constant = try cctx.cpool.add_class(struct_type.name);
    const super_class_constant = try cctx.cpool.add_class("java/lang/Object");
    cctx.name = struct_type.name;
    cctx.class.this_class = @intCast(class_constant);
    cctx.class.super_class = @intCast(super_class_constant);

    var methods_len: usize = 0;
    var fields_len: usize = 0;
    for (struct_type.fields) |field| {
        if (field.synthetic) continue;
        if (field.type.* == .@"fn") methods_len += 1 else fields_len += 1;
    }

    var methods_index: usize = 0;
    var fields_index: usize = 0;
    cctx.class.fields = try gpa.alloc(Class.FieldInfo, fields_len);
    cctx.class.methods = try gpa.alloc(Class.MethodInfo, methods_len);

    for (struct_type.fields) |field| {
        if (field.synthetic) continue;
        std.debug.print("generate: Generating field {s}.\n", .{field.name});
        const name_h = try cctx.cpool.add_utf8(field.name);

        switch (field.type.*) {
            .@"fn" => |fun| {
                const desc = try buildMethodDescriptor(gpa, fun);
                const desc_index = try cctx.cpool.add_utf8(desc);

                var fctx = try FunctionContext.init(cctx);
                defer fctx.deinit();

                for (fun.params, 0..) |p, i| {
                    try fctx.locals.append(gpa, .{
                        .index = @intCast(i),
                        .name = p.name,
                        .type = p.type,
                    });
                }
                if (!field.access.static) {
                    const this_ptr = try gpa.create(Type);
                    this_ptr.* = .{ .@"struct" = struct_type.* };
                    try fctx.locals.append(gpa, .{
                        .index = @intCast(fctx.locals.items.len),
                        .name = "this",
                        .type = this_ptr,
                    });
                }

                try emit.bytecodeOf(&fctx, fun.body);

                const code = try fctx.toOwnedCode();
                const attributes = try gpa.alloc(Class.Attribute, 1);
                attributes[0] = code;

                cctx.class.methods[methods_index] = .{
                    .name_index = @intCast(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = fieldToMethodAccess(field.access),
                    .attributes = attributes,
                };
                methods_index += 1;
            },
            else => {
                const desc_index = try cctx.cpool.add_utf8(try field.type.jvmName(gpa));
                cctx.class.fields[fields_index] = .{
                    .name_index = @truncate(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = field.access,
                    .attributes = &.{},
                };
                fields_index += 1;
            },
        }
    }

    cctx.class.attributes = &.{};
    try cctx.cpool.populate(cctx.class);
}

fn buildMethodDescriptor(gpa: std.mem.Allocator, fun: Type.Fn) ![]const u8 {
    const param_names = try gpa.alloc([]const u8, fun.params.len);
    for (fun.params, 0..) |p, i| {
        param_names[i] = try gpa.dupe(u8, try p.type.jvmName(gpa));
    }
    return assembleMethodDesc(gpa, param_names, try fun.return_type.jvmName(gpa));
}

fn fieldToMethodAccess(field_access: Class.FieldAccessFlags) Class.MethodAccessFlags {
    var flags = Class.MethodAccessFlags{};
    flags.public = field_access.public;
    flags.private = field_access.private;
    flags.protected = field_access.protected;
    flags.static = field_access.static;
    flags.final = field_access.final;
    return flags;
}

pub fn assembleMethodDesc(gpa: std.mem.Allocator, params: [][]const u8, return_name: []const u8) ![]const u8 {
    var desc_len: usize = 2 + return_name.len;
    for (params) |param| desc_len += param.len;

    const descriptor = try gpa.alloc(u8, desc_len);
    descriptor[0] = '(';
    var i: usize = 1;
    for (params) |param| {
        @memcpy(descriptor[i..][0..param.len], param);
        i += param.len;
    }
    descriptor[i] = ')';
    @memcpy(descriptor[i + 1 ..], return_name);
    return descriptor;
}
