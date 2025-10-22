const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;

pub fn readClass(gpa: std.mem.Allocator, r: *std.Io.Reader, class: *Class) !void {

    var constants = try std.ArrayList(Class.Constant).initCapacity(gpa, 16);
    var fields = try std.ArrayList(Class.FieldInfo).initCapacity(gpa, 16);
    var methods = try std.ArrayList(Class.MethodInfo).initCapacity(gpa, 1);
    var attributes = try std.ArrayList(Class.Attribute).initCapacity(gpa, 6);

    class.magic = try r.takeInt(u32, .big);
    if (class.magic != format.class_format_header) return error.WrongMagic;
    class.minor_version = try r.takeInt(u16, .big);
    class.major_version = try r.takeInt(u16, .big);
    const constants_len = try r.takeInt(u16, .big);
    var i: usize = 1;
    while (i < constants_len) : (i += 1) {
        const c = try readConstant(gpa, r);
        //std.debug.print("Read constant #{} - {s}\n", .{ i, @tagName(c) });
        try constants.append(gpa, c);

        switch (c) {
            .long_info, .double_info => {
                try constants.append(gpa, .placeholder);
                i += 1; // skip long slot.
            },
            else => {},
        }
    }
    // std.debug.print("constant pool parsed items = {}, expected {}\n",.{ constants.items.len, constants_len - 1 });
    if (constants.items.len != constants_len - 1) {
        return error.IllegalConstantPool;
    }
    class.constant_pool = try constants.toOwnedSlice(gpa);

    class.access_flags = @bitCast(try r.takeInt(u16, .big));
    class.this_class = try r.takeInt(u16, .big);
    class.super_class = try r.takeInt(u16, .big);
    //const this_name = class.constant_pool[class.this_class - 1].class_info.name_index;
    //std.debug.print("this = '{s}'\n", .{ class.constant_pool[this_name - 1].utf_8_info.bytes });
    const interfaces_len = try r.takeInt(u16, .big);
    // std.debug.print("# of Interfaces = {}\n", .{ interfaces_len });
    for (0..interfaces_len) |_| {
        _ = try r.takeInt(u16, .big);
    }
    const fields_len = try r.takeInt(u16, .big) ;
    //std.debug.print("# of fields = {}\n", .{ fields_len });
    for (0..fields_len) |_| {
        try fields.append(gpa, try readMethodOrField(r, class, .field));
    }
    const methods_len = try r.takeInt(u16, .big);
    //std.debug.print("# of methods = {}\n", .{ methods_len });
    for (0..methods_len) |_| {
        try methods.append(gpa, try readMethodOrField(r, class, .method));
    }
    const attrs_len = try r.takeInt(u16, .big);
    //std.debug.print("# of attrs = {}\n", .{ attrs_len });
    for (0..attrs_len) |_| {
        try attributes.append(gpa, try readAttr(r, class));
    }

    class.fields = try fields.toOwnedSlice(gpa);
    class.methods = try methods.toOwnedSlice(gpa);
    class.attributes = try attributes.toOwnedSlice(gpa);
}

fn readMethodOrField(r: *std.Io.Reader, classfile: *Class, comptime mode: enum { field, method }) !t: {
    switch (mode) {
        .field => break :t (Class.FieldInfo),
        .method => break :t (Class.MethodInfo),
    }
} {
    const T: type = comptime switch (mode) {
        .field => (Class.FieldInfo),
        .method => (Class.MethodInfo),
    };
    const flags = try r.takeInt(u16, .big);
    const name_index = try r.takeInt(u16, .big);
    const desc_index = try r.takeInt(u16, .big);
    const attr_len = try r.takeInt(u16, .big);
    const ret: T = .{
        .access_flags = @bitCast(flags),
        .descriptor_index = desc_index,
        .name_index = name_index,
        .attributes = &.{},
    };
    // std.debug.print("static={}, name={}, desc={}, attrs={}\n", .{ ret.access_flags.static, name_index, desc_index, attr_len });
    // switch (mode) {
    //     .field => std.debug.print("Field ", .{}),
    //     .method => std.debug.print("Method ", .{})
    // }
    // std.debug.print("'{s}' has {} attrs\n", .{ classfile.constant_pool[name_index - 1].utf_8_info.bytes, attr_len });
    for (0..attr_len) |_| {
        _ = try readAttr(r, classfile);
    }
    return ret;
}

fn readAttr(r: *std.Io.Reader, class: *Class) !Class.Attribute {
    const name_index = try r.takeInt(u16, .big);
    const len = try r.takeInt(u32, .big);
    const name = class.constant_pool[name_index - 1].utf_8_info.bytes;
    // std.debug.print("Reading attr '{s}', len = {}\n", .{
    //      name,
    //      len
    // });
    var attr: Class.Attribute = .{
        .attribute_name_index = name_index,
        .attribute_length = len,
        .info = .undefined
    };
    if (std.mem.eql(u8, name, "Code")) {
        const max_stack = try r.takeInt(u16, .big);
        const max_locals = try r.takeInt(u16, .big);
        const code_len = try r.takeInt(u32, .big);
        // bytecode, discorded.
        try r.discardAll(code_len);
        const exception_table_len = try r.takeInt(u16, .big);
        try r.discardAll(8 * exception_table_len);
        const attr_count = try r.takeInt(u16, .big);
        var attrs_len: usize = 0;
        for (0..attr_count) |_| {
            const a = try readAttr(r, class);
            attrs_len += 6; // their name and length fields... oops.
            attrs_len += a.attribute_length;
        }
        // Should be
        // u2 max_stack +
        // u2 max_locals +
        // u4 code_len +
        // u1[] code +
        // u2 exc_len +
        // u8[] exc_table +
        // u2 attrs_count +
        // attr[] attrs
        const discovered_len = 2 + 2 + 4 + code_len + 2 + (exception_table_len * 8) + 2 + attrs_len;
        if (discovered_len != len) {
            std.debug.print("code_len={},ex_tabl_len={},attr_count={},attr_len={},total_guess={}\nneeded {}\n", .{
                code_len, exception_table_len, attr_count, attrs_len, discovered_len, len
            });
            unreachable;
        }
        const print_bytecode = false;
        if (print_bytecode) {
            std.debug.print("Disassembled bytecode;\n", .{});
            //try @import("bytecode.zig").print(bytecode, class);
        }
        attr.info = .{ .code = .{
            .max_locals = max_locals,
            .max_stack = max_stack,
            .code = &.{},
            .attributes = &.{},
            .exception_table = &.{},
        } };
    } else {
        try r.discardAll(len);
    }
    return attr;
}

fn readConstant(gpa: std.mem.Allocator, r: *std.Io.Reader) !Class.Constant {
    const tag_value = try r.takeInt(u8, .big);
    const tag: Class.Constant.Tag = std.enums.fromInt(Class.Constant.Tag, tag_value) orelse {
        std.debug.print("Enum value '{}' not a valid constant tag.\n", .{ tag_value });
        return error.UnknownConstantTag;
    };
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
        .dynamic => {
            _ = try r.takeInt(u16, .big); // bootstrap_method_attr_index
            _ = try r.takeInt(u16, .big); // name_and_type_index
        },
        .invoke_dynamic => {
            _ = try r.takeInt(u16, .big);
            _ = try r.takeInt(u16, .big);
        },
        .module => _ = try r.takeInt(u16, .big),
        .package => _ = try r.takeInt(u16, .big)
    }
    return .placeholder;
}

pub fn readClassFile(gpa: std.mem.Allocator, path: []const u8) !Class {
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |e| {
        switch (e) {
            error.FileNotFound => {
                std.debug.print("Could not find class file at '{s}'.\n", .{ path });
                return e;
            },
            else => return e,
        }
    };
    defer file.close();
    var buf: [2048]u8 = undefined;
    var reader = file.reader(&buf);
    const r = &reader.interface;
    var class = Class{};
    try readClass(gpa, r, &class);
    return class;
}

test "read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const gpa = arena.allocator();
    defer arena.deinit();

    const class = try readClassFile(gpa, "test/jdk/java/lang/String.class");
    _ = class;
}