const std = @import("std");
const Class = @import("format.zig").Class;

pub fn writeClass(w: *std.Io.Writer, class: Class) !void {
    try w.writeInt(u32, class.magic, .big);
    try w.writeInt(u16, class.minor_version, .big);
    try w.writeInt(u16, class.major_version, .big);
    try w.writeInt(u16, @truncate(class.constant_pool.items.len + 1), .big);
    for (class.constant_pool.items) |c| try writeConstant(w, c);
    const acc_flags: u16 = @bitCast(class.access_flags);
    std.debug.print("writeClassFile: Class Access Flags: {b:0>16}\n", .{acc_flags});
    try w.writeInt(u16, acc_flags, .big);
    std.debug.print("writeClassFile: This class = {s}\n", .{class.constant_pool.items[class.constant_pool.items[class.this_class - 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.this_class, .big);
    std.debug.print("writeClassFile: Super class = {s}\n", .{class.constant_pool.items[class.constant_pool.items[class.super_class - 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.super_class, .big);

    std.debug.print("writeClassFile: Number of interfaces {d}\n", .{class.interfaces.len});
    try w.writeInt(u16, @intCast(class.interfaces.len), .big);
    for (class.interfaces) |interface| try w.writeInt(u16, interface, .big);

    std.debug.print("writeClassFile: Number of fields {d}\n", .{class.fields.items.len});
    try w.writeInt(u16, @truncate(class.fields.items.len), .big);
    for (class.fields.items) |field| try writeMethodOrField(w, .field, field);

    std.debug.print("writeClassFile: Number of methods {d}\n", .{class.methods.items.len});
    try w.writeInt(u16, @intCast(class.methods.items.len), .big);
    for (class.methods.items) |method| try writeMethodOrField(w, .method, method);

    std.debug.print("writeClassFile: Number of attributes {d}\n", .{class.attributes.items.len});
    try w.writeInt(u16, @intCast(class.attributes.items.len), .big);
    for (class.attributes.items) |attr| try writeAttribute(w, attr);
}

fn writeMethodOrField(w: *std.Io.Writer, comptime mode: enum { field, method }, m: switch (mode) { .field => Class.FieldInfo, .method => Class.MethodInfo }, ) !void {
    std.debug.print("writeMethodOrField: Emitting {s}.\n", .{ @typeName(@TypeOf(m)) });
    const acc_flags: u16 = @bitCast(m.access_flags);
    std.debug.print("writeMethodOrField: Access Flags: {b:0>16}\n", .{ acc_flags });
    try w.writeInt(u16, acc_flags, .big);
    try w.writeInt(u16, m.name_index, .big);
    try w.writeInt(u16, m.descriptor_index, .big);
    std.debug.print("writeMethodOrField: Number of attributes {any}\n", .{m.attributes.len});
    try w.writeInt(u16, @intCast(m.attributes.len), .big);
    for (m.attributes) |attribute| try writeAttribute(w, attribute);
}

fn writeAttribute(w: *std.Io.Writer, a: Class.Attribute) !void {
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
            for (code.attributes) |attribute| try writeAttribute(w, attribute);
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

fn writeConstant(w: *std.Io.Writer, c: Class.Constant) !void {
    switch (c) {
        .utf_8_info => |utf| {
            try w.writeByte(utf.tag);
            try w.writeInt(u16, @intCast(utf.bytes.len), .big);
            try w.writeAll(utf.bytes);
        },
        .class_info => |class| {
            try w.writeByte(class.tag);
            try writeConstantIndex(w, class.name_index);
        },
        .double_info => |double| {
            try w.writeByte(double.tag);
            try w.writeInt(u32, double.high_bytes, .big);
            try w.writeInt(u32, double.low_bytes, .big);
        },
        .field_ref_info => |field| {
            try w.writeByte(field.tag);
            try writeConstantIndex(w, field.class_index);
            try writeConstantIndex(w, field.name_and_type_index);
        },
        .float_info => |float| {
            try w.writeByte(float.tag);
            try w.writeInt(u32, float.bytes, .big);
        },
        .integer_info => |int| {
            try w.writeByte(int.tag);
            try w.writeInt(u32, int.bytes, .big);
        },
        .interface_ref_info => |interface| {
            try w.writeByte(interface.tag);
            try writeConstantIndex(w, interface.class_index);
            try writeConstantIndex(w, interface.name_and_type_index);
        },
        .invoke_dynamic => {},
        .long_info => |long| {
            try w.writeByte(long.tag);
            try w.writeInt(u32, long.high_bytes, .big);
            try w.writeInt(u32, long.low_bytes, .big);
        },
        .method_handle_info => |handle| {
            try w.writeByte(handle.tag);
            try writeConstantIndex(w, handle.reference_index);
            try w.writeByte(@intFromEnum(handle.reference_kind));
        },
        .method_ref_info => |method| {
            try w.writeByte(method.tag);
            try writeConstantIndex(w, method.class_index);
            try writeConstantIndex(w, method.name_and_type_index);
        },
        .method_type_info => |typ| {
            try w.writeByte(typ.tag);
            try writeConstantIndex(w, typ.descriptor_index);
        },
        .name_and_type_info => |name| {
            try w.writeByte(name.tag);
            try writeConstantIndex(w, name.name_index);
            try writeConstantIndex(w, name.descriptor_index);
        },
        .string_info => |str| {
            try w.writeByte(str.tag);
            try writeConstantIndex(w, str.string_index);
        },
        .placeholder => {}
    }
}