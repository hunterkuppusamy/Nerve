const std = @import("std");
const Class = @import("class.zig").Class;

pub fn writeClass(w: *std.Io.Writer, class: *const Class) !void {
    try w.writeInt(u32, class.magic, .big);
    try w.writeInt(u16, class.minor_version, .big);
    try w.writeInt(u16, class.major_version, .big);
    try w.writeInt(u16, @truncate(class.constant_pool.len + 1), .big);
    for (class.constant_pool) |c| try writeConstant(w, c);
    const acc_flags: u16 = @bitCast(class.access_flags);
    std.debug.print("writeClassFile: Class Access Flags: {b:0>16}\n", .{acc_flags});
    try w.writeInt(u16, acc_flags, .big);
    std.debug.print("writeClassFile: This class = {s}\n", .{class.constant_pool[class.constant_pool[class.this_class - 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.this_class, .big);
    std.debug.print("writeClassFile: Super class = {s}\n", .{class.constant_pool[class.constant_pool[class.super_class - 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.super_class, .big);

    std.debug.print("writeClassFile: Number of interfaces {d}\n", .{class.interfaces.len});
    try w.writeInt(u16, @intCast(class.interfaces.len), .big);
    for (class.interfaces) |interface| try w.writeInt(u16, interface, .big);

    std.debug.print("writeClassFile: Number of fields {d}\n", .{class.fields.len});
    try w.writeInt(u16, @truncate(class.fields.len), .big);
    for (class.fields) |field| try writeMethodOrField(w, .field, field);

    std.debug.print("writeClassFile: Number of methods {d}\n", .{class.methods.len});
    try w.writeInt(u16, @intCast(class.methods.len), .big);
    for (class.methods) |method| try writeMethodOrField(w, .method, method);

    std.debug.print("writeClassFile: Number of attributes {d}\n", .{class.attributes.len});
    try w.writeInt(u16, @intCast(class.attributes.len), .big);
    for (class.attributes) |attr| try writeAttribute(w, &attr);
}

fn writeMethodOrField(w: *std.Io.Writer, comptime mode: enum { field, method }, m: switch (mode) { .field => Class.FieldInfo, .method => Class.MethodInfo }) !void {
    std.debug.print("writeMethodOrField: Emitting {s}.\n", .{ @typeName(@TypeOf(m)) });
    const acc_flags: u16 = @bitCast(m.access_flags);
    std.debug.print("writeMethodOrField: Access Flags: {b:0>16}\n", .{ acc_flags });
    try w.writeInt(u16, acc_flags, .big);
    try w.writeInt(u16, m.name_index, .big);
    try w.writeInt(u16, m.descriptor_index, .big);
    std.debug.print("writeMethodOrField: Number of attributes {any}\n", .{m.attributes.len});
    try w.writeInt(u16, @intCast(m.attributes.len), .big);
    for (m.attributes) |attribute| try writeAttribute(w, &attribute);
}

fn writeAttribute(w: *std.Io.Writer, a: *const Class.Attribute) !void {
    std.debug.print("writeAttribute: Name_ndx = {d}\n", .{a.attribute_name_index});
    try w.writeInt(u16, a.attribute_name_index, .big);
    try w.writeInt(u32, a.attribute_length, .big);
    switch (a.info) {
        .constant_value_index => |c| try w.writeInt(u16, c, .big),
        .code => |code| {
            try w.writeInt(u16, code.max_stack, .big);
            try w.writeInt(u16, code.max_locals, .big);
            std.debug.print("writeAttribute: Code attr = {any}\n", .{ code });
            try w.writeInt(u32, @intCast(code.code.len), .big);
            try w.writeAll(code.code);
            try w.writeInt(u16, @intCast(code.exception_table.len), .big);
            for (code.exception_table) |e| {
                try w.writeInt(u16, e.start_pc, .big);
                try w.writeInt(u16, e.end_pc, .big);
                try w.writeInt(u16, e.handler_pc, .big);
                try w.writeInt(u16, e.catch_type, .big);
            }
            try w.writeInt(u16, @intCast(code.attributes.len), .big);
            for (code.attributes) |attribute| try writeAttribute(w, &attribute);
        },
        else => {
            std.debug.print("Unhandled attribute {any}.\n", .{ a });
            return error.NotSupported;
        },
    }
}

fn writeConstantIndex(w: *std.Io.Writer, i: u16) !void {
    try w.writeInt(u16, i, .big);
}

fn tagOf(c: Class.Constant) u8 {
    const active_tag = @tagName(c);
    const info = @typeInfo(Class.Constant).@"union";

    inline for (info.fields) |field| {
        if (field.type == void) continue;
        if (std.mem.eql(u8, field.name, active_tag)) {
            return @field(field.type, "tag");
        }
    }
    unreachable;
}

fn writeConstant(w: *std.Io.Writer, c: Class.Constant) !void {
    const tag = tagOf(c);
    try w.writeByte(tag);
    switch (c) {
        .utf_8_info => |utf| {
            try w.writeInt(u16, @intCast(utf.bytes.len), .big);
            try w.writeAll(utf.bytes);
        },
        .class_info => |class| {
            try writeConstantIndex(w, class.name_index);
        },
        .double_info => |double| {
            try w.writeInt(u32, double.high_bytes, .big);
            try w.writeInt(u32, double.low_bytes, .big);
        },
        .field_ref_info => |field| {
            try writeConstantIndex(w, field.class_index);
            try writeConstantIndex(w, field.name_and_type_index);
        },
        .float_info => |float| {
            try w.writeInt(u32, float.bytes, .big);
        },
        .integer_info => |int| {
            try w.writeInt(u32, int.bytes, .big);
        },
        .interface_ref_info => |interface| {
            try writeConstantIndex(w, interface.class_index);
            try writeConstantIndex(w, interface.name_and_type_index);
        },
        .invoke_dynamic => @panic("Cannot write invoke_dynamic."),
        .long_info => |long| {
            try w.writeInt(u32, long.high_bytes, .big);
            try w.writeInt(u32, long.low_bytes, .big);
        },
        .method_handle_info => |handle| {
            try writeConstantIndex(w, handle.reference_index);
            try w.writeByte(@intFromEnum(handle.reference_kind));
        },
        .method_ref_info => |method| {
            try writeConstantIndex(w, method.class_index);
            try writeConstantIndex(w, method.name_and_type_index);
        },
        .method_type_info => |typ| {
            try writeConstantIndex(w, typ.descriptor_index);
        },
        .name_and_type_info => |name| {
            try writeConstantIndex(w, name.name_index);
            try writeConstantIndex(w, name.descriptor_index);
        },
        .string_info => |str| {
            try writeConstantIndex(w, str.string_index);
        },
        .placeholder => {}
    }
}

pub fn writeClassFile(path: []const u8, class: *const Class) !void {
    var buf: [2048]u8 = undefined;
    var file = try std.fs.cwd().createFile(path, .{
        .lock = .exclusive,
        .mode = 0o666 // rw-rw-rw-
    });
    defer file.close();
    var fs = file.writer(&buf);
    var w = &fs.interface;
    try writeClass(w, class);
    try w.flush();
}