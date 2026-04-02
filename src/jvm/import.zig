const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Type = @import("../type.zig").Type;
const read = @import("read.zig");
const GlobalContext = @import("context.zig").GlobalContext;

pub const ImportError = std.fs.File.OpenError || std.mem.Allocator.Error || std.Io.Reader.Error || error{
    WrongMagic,
    UnknownConstantTag,
    AlreadyImported,
    IllegalConstantPool,
};

pub fn prepImports(global: *GlobalContext) !void {
    const gpa = global.allocator;
    const str_ptr = try importClassName(global, "java/lang/String");

    const obj_fields = try gpa.alloc(Type.Struct.Field, 1);
    obj_fields[0] = .{ .access = .{ .public = true }, .name = "toString", .type = str_ptr };

    const obj_ptr = try gpa.create(Type);
    obj_ptr.* = .{ .@"struct" = .{ .name = "java/lang/Object", .fields = obj_fields } };
    try global.imported.put("java/lang/Object", obj_ptr);
}

pub fn importPath(global: *GlobalContext, path: []const u8) ImportError!*Type {
    const class = try read.readClassFile(global.allocator, path);
    defer global.allocator.destroy(class);
    return importClass(global, class);
}

pub fn importClassName(global: *GlobalContext, class_name: []const u8) ImportError!*Type {
    if (global.imported.get(class_name)) |t| return t;
    const file_path = try std.mem.concat(global.allocator, u8, &.{
        global.jdk_path, "/", class_name, ".class",
    });
    defer global.allocator.free(file_path);
    return importPath(global, file_path);
}

pub fn importDescriptor(global: *GlobalContext, descriptor: []const u8, ignore_prefix: bool) ImportError!*const Type {
    const gpa = global.allocator;
    if (descriptor.len == 0) {
        global.report(.{}, "empty type descriptor", .{});
        return ImportError.Unexpected;
    }

    return switch (descriptor[0]) {
        'I' => &@as(Type, Type.int),
        'F' => &@as(Type, Type.float),
        'J' => &@as(Type, Type.long),
        'D' => &@as(Type, Type.double),
        'V' => &@as(Type, Type.void),
        'B', 'Z', 'S', 'C' => &@as(Type, Type.int),
        '[' => blk: {
            const element_type = importDescriptor(global, descriptor[1..], false) catch |e| return e;
            const temp = try gpa.create(Type);
            temp.* = .{ .array = .{ .elements = element_type } };
            break :blk temp;
        },
        'L' => importClassName(global, descriptor[1 .. descriptor.len - 1]),
        else => if (ignore_prefix)
            importClassName(global, descriptor)
        else {
            global.report(.{}, "invalid type descriptor '{s}'", .{descriptor});
            return ImportError.Unexpected;
        },
    };
}

pub fn nextDesc(descriptor: []const u8) ?[]const u8 {
    return switch (descriptor[0]) {
        'I', 'F', 'J', 'D', 'V', 'B', 'C', 'S', 'Z' => descriptor[0..1],
        '[' => blk: {
            const element = nextDesc(descriptor[1..]).?;
            break :blk descriptor[0 .. element.len + 1];
        },
        'L' => blk: {
            for (descriptor, 0..) |c, i| {
                if (c == ';') break :blk descriptor[0 .. i + 1];
            }
            unreachable;
        },
        else => {
            std.debug.print("Got {s}\n", .{descriptor});
            unreachable;
        },
    };
}

pub fn parseMethodDesc(global: *GlobalContext, descriptor: []const u8) !struct {
    ret: *const Type,
    params: []const *const Type,
} {
    var i: usize = 1;
    var params = try std.ArrayList(*const Type).initCapacity(global.allocator, 4);
    var ret: *const Type = undefined;
    while (i < descriptor.len) {
        if (descriptor[i] == ')') {
            const return_desc = nextDesc(descriptor[i + 1 ..]).?;
            ret = try importDescriptor(global, return_desc, false);
            break;
        }
        const param_desc = nextDesc(descriptor[i..]) orelse break;
        i += param_desc.len;
        try params.append(global.allocator, try importDescriptor(global, param_desc, false));
    }
    return .{
        .ret = ret,
        .params = try params.toOwnedSlice(global.allocator),
    };
}

pub fn importClass(global: *GlobalContext, class: *const Class) ImportError!*Type {
    const gpa = global.allocator;
    const cp = class.constant_pool;
    const name = cp[cp[class.this_class - 1].class_info.name_index - 1].utf_8_info.bytes;

    if (global.imported.get(name)) |existing| return existing;

    const ptr = try gpa.create(Type);
    ptr.* = .{ .@"struct" = .{ .name = name, .fields = &.{} } };
    try global.imported.put(name, ptr);

    var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 16);

    for (class.fields) |f| {
        try fields.append(gpa, .{
            .access = f.access_flags,
            .name = try gpa.dupe(u8, cp[f.name_index - 1].utf_8_info.bytes),
            .type = try importDescriptor(global, cp[f.descriptor_index - 1].utf_8_info.bytes, false),
        });
    }

    for (class.methods) |m| {
        const method_desc = try parseMethodDesc(global, cp[m.descriptor_index - 1].utf_8_info.bytes);

        var params = [_]Type.Fn.Param{undefined} ** 32;
        var param_i: u8 = 0;
        for (method_desc.params) |p| {
            params[param_i] = .{
                .name = try std.fmt.allocPrint(gpa, "_{}", .{param_i}),
                .type = p,
            };
            param_i += 1;
        }

        const fn_type = try gpa.create(Type);
        fn_type.* = .{ .@"fn" = .{
            .return_type = method_desc.ret,
            .params = try gpa.dupe(Type.Fn.Param, params[0..param_i]),
            .body = &.{},
        } };

        var access = Class.FieldAccessFlags{};
        access.public = m.access_flags.public;
        access.static = m.access_flags.static;
        access.private = m.access_flags.private;
        access.protected = m.access_flags.protected;
        access.final = m.access_flags.final;

        try fields.append(gpa, .{
            .access = access,
            .name = try gpa.dupe(u8, cp[m.name_index - 1].utf_8_info.bytes),
            .type = fn_type,
        });
    }

    if (class.super_class > 0) {
        const super_name = cp[cp[class.super_class - 1].class_info.name_index - 1].utf_8_info.bytes;
        const super_type = try importClassName(global, super_name);
        switch (super_type.*) {
            .@"struct" => |super_class| {
                for (super_class.fields) |field| try fields.append(gpa, field);
            },
            else => @panic("Super class was a jvm primitive."),
        }
    }

    ptr.*.@"struct".fields = try fields.toOwnedSlice(gpa);
    return ptr;
}
