const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;

fn readClassFile(allocator: std.mem.Allocator, r: *std.Io.Reader, classfile: *Class) !void {
    classfile.magic = try r.takeInt(u32, .big);
    if (classfile.magic != format.class_format_header) return error.WrongMagic;
    classfile.minor_version = try r.takeInt(u16, .big);
    classfile.major_version = try r.takeInt(u16, .big);
    for (1..try r.takeInt(u16, .big)) |_| {
        const c = try readConstant(allocator, r);
        std.debug.print("Read constant {s}\n", .{ @tagName(c) });
        try classfile.constant_pool.append(allocator, c);
        switch (c) {
            .long_info, .double_info => try classfile.constant_pool.append(allocator, .placeholder),
            else => {}
        }
    }
    classfile.access_flags = @bitCast(try r.takeInt(u16, .big));
    classfile.this_class = try r.takeInt(u16, .big);
    classfile.super_class = try r.takeInt(u16, .big);
    const this_name = classfile.constant_pool.items[classfile.this_class - 1].class_info.name_index;
    std.debug.print("this = '{s}'\n", .{ classfile.constant_pool.items[this_name - 1].utf_8_info.bytes });
    const interfaces_len = try r.takeInt(u16, .big);
    std.debug.print("# of Interfaces = {}\n", .{ interfaces_len });
    if (interfaces_len > 0) for (1..interfaces_len) |_| {
        _ = try r.takeInt(u16, .big);
    };
    const fields_len = try r.takeInt(u16, .big) ;
    std.debug.print("# of fields = {}\n", .{ fields_len });
    for (0..fields_len) |_| {
        try classfile.fields.append(allocator, try readMethodOrField(r, classfile, .field));
    }
    const methods_len = try r.takeInt(u16, .big);
    std.debug.print("# of methods = {}\n", .{ methods_len });
    for (0..methods_len) |_| {
        try classfile.methods.append(allocator, try readMethodOrField(r, classfile, .method));
    }
    const attrs_len = try r.takeInt(u16, .big);
    std.debug.print("# of attrs = {}\n", .{ attrs_len });
    for (0..attrs_len) |_| {
        try classfile.attributes.append(allocator, try readAttr(r, classfile));
    }
}

fn readMethodOrField(r: *std.Io.Reader, classfile: *Class, comptime mode: enum { field, method }) !t: {
    switch (mode) {
        .field => break :t (Class.FieldInfo),
        .method => break :t (Class.MethodInfo),
    }
} {
    const flags = try r.takeInt(u16, .big);
    const name_index = try r.takeInt(u16, .big);
    const desc_index = try r.takeInt(u16, .big);
    const attr_len = try r.takeInt(u16, .big);
    std.debug.print("flags={}, name={}, desc={}, attrs={}\n", .{ flags, name_index, desc_index, attr_len });
    std.debug.print("Field '{s}' has {} attrs\n", .{ classfile.constant_pool.items[name_index - 1].utf_8_info.bytes, attr_len });
    for (0..attr_len) |_| {
        _ = try readAttr(r, classfile);
    }
    return .{
        .access_flags = @bitCast(flags),
        .descriptor_index = desc_index,
        .name_index = name_index,
        .attributes = &[0]Class.Attribute{ },
    };
}

fn readAttr(r: *std.Io.Reader, classfile: *Class) !Class.Attribute {
    const name_index = try r.takeInt(u16, .big);
    const len = try r.takeInt(u32, .big);
    const name = classfile.constant_pool.items[name_index - 1].utf_8_info.bytes;
    std.debug.print("Reading attr '{s}', len = {}\n", .{
        name,
        len
    });
    const bytes= try r.take(len);
    if (std.mem.eql(u8, name, "Code")) {
        try @import("bytecode.zig").print(bytes, classfile);
    }
    return .{ .attribute_length = len, .attribute_name_index = name_index, .info = .undefined };
}

fn readConstant(gpa: std.mem.Allocator, r: *std.Io.Reader) !Class.Constant {
    const tag: Class.Constant.Tag = @enumFromInt(try r.takeInt(u8, .big));
    switch (tag) {
        .class => return .{ .class_info = .{
            .name_index = try r.takeInt(u16, .big)
        } },
        .fieldref => return .{ .field_ref_info = .{
            .class_index = try r.takeInt(u16, .big),
            .name_and_type_index = try r.takeInt(u16, .big),
        } },
        .methodref => return .{ .method_ref_info = .{
            .class_index = try r.takeInt(u16, .big),
            .name_and_type_index = try r.takeInt(u16, .big),
        } },
        .interface_methodref => return .{ .interface_ref_info = .{
            .class_index = try r.takeInt(u16, .big),
            .name_and_type_index = try r.takeInt(u16, .big),
        } },
        .string => return .{ .string_info = .{
            .string_index = try r.takeInt(u16, .big),
        } },
        .integer => return .{ .integer_info = .{
            .bytes = try r.takeInt(u32, .big),
        } },
        .float => return .{ .float_info = .{
            .bytes = try r.takeInt(u32, .big),
        } },
        .long => return .{ .long_info = .{
            .high_bytes = try r.takeInt(u32, .big),
            .low_bytes = try r.takeInt(u32, .big),
        } },
        .double => return .{ .double_info = .{
            .high_bytes = try r.takeInt(u32, .big),
            .low_bytes = try r.takeInt(u32, .big),
        } },
        .name_and_type => return .{ .name_and_type_info = .{
            .name_index = try r.takeInt(u16, .big),
            .descriptor_index = try r.takeInt(u16, .big),
        } },
        .utf8 => {
            const len = try r.takeInt(u16, .big);
            const bytes = try r.take(len);
            return .{ .utf_8_info = .{
                .bytes = try gpa.dupe(u8, bytes),
            } };
        },
        .method_handle => return .{ .method_handle_info = .{
            .reference_kind = @enumFromInt(try r.takeInt(u8, .big)),
            .reference_index = try r.takeInt(u16, .big),
        } },
        .method_type => return .{ .method_type_info = .{
            .descriptor_index = try r.takeInt(u16, .big),
        } },
        .dynamic => _ = try r.takeInt(u32, .big),
        .invoke_dynamic => _ = try r.takeInt(u32, .big),
        .module => _ = try r.takeInt(u16, .big),
        .package => _ = try r.takeInt(u16, .big)
    }
    return .placeholder;
}

test "read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const gpa = arena.allocator();
    defer arena.deinit();

    const file = try std.fs.cwd().openFile("test/ToRead.class", .{ .mode = .read_only });
    defer file.close();
    var buf: [2048]u8 = undefined;
    var reader = file.reader(&buf);
    const r = &reader.interface;
    var class = Class{
        .constant_pool = try std.ArrayList(Class.Constant).initCapacity(gpa, 16),
        .fields = try std.ArrayList(Class.FieldInfo).initCapacity(gpa, 16),
        .methods = try std.ArrayList(Class.MethodInfo).initCapacity(gpa, 16),
        .attributes = try std.ArrayList(Class.Attribute).initCapacity(gpa, 16),
    };
    try readClassFile(gpa, r, &class);
}