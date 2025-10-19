const std = @import("std");
const parser = @import("parser.zig");
const Class = @import("jvm/format.zig").Class;
const Node = @import("AST.zig").Node;
const ProgramContext = @import("jvm/gen.zig").ProgramContext;

pub const Type = union(enum) {
    int: Int32,
    float: Float32,
    void: void,
    @"struct": Struct,
    @"fn": Fn,
    array: Array,

    pub fn jvmName(self: *const Type, gpa: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .int => "I",
            .float => "F",
            .void => "V",
            .@"fn" => "Ljava/lang/Function;",
            .@"struct" => |str| try classToDesc(gpa, str.name),
            .array => |a| try makeArray(gpa, try a.elements.jvmName(gpa)),
        };
    }

    fn makeArray(gpa: std.mem.Allocator, name: []const u8) ![]const u8 {
        const len = name.len;
        const new = try gpa.alloc(u8, len + 1);
        @memcpy(new[1..new.len], name);
        new[0] = '[';
        return new;
    }

    fn classToDesc(gpa: std.mem.Allocator, bytes: []const u8) ![]const u8 {
        const len = bytes.len;
        const new = try gpa.alloc(u8, len + 2);
        @memcpy(new[1..(new.len - 1)], bytes);
        new[0] = 'L';
        new[new.len - 1] = ';';
        return new;
    }

    pub fn lookup(name: []const u8) ?Type {
        _ = name;
        return null;
    }

    pub fn ofClass(program: *ProgramContext, class: Class) !*Type {
        const name = class.constant_pool.items[class.this_class - 1].utf_8_info.bytes;
        var fields = try std.ArrayList(Struct.Field).initCapacity(program.allocator, 16);
        try program.types.put(name, Type {
            .@"struct" = .{
                .name = try program.allocator.dupe(u8, name),
                .fields = try fields.toOwnedSlice(program.allocator),
            }
        });
        const type_ptr = program.types.getPtr(name).?;
        for (class.fields.items) |f| {
            const fname = class.constant_pool.items[f.name_index - 1].utf_8_info.bytes;
            const field_type_ptr = program.types.getPtr(class.constant_pool.items[f.descriptor_index - 1].utf_8_info.bytes).?;
            try fields.append(program.allocator, .{
                .access = f.access_flags,
                .name = try program.allocator.dupe(u8, fname),
                .type = field_type_ptr,
            });
        }
        return type_ptr;
    }

    pub const Struct = struct {
        name: []const u8,
        // fields are functions
        fields: []const Field,

        const Self = @This();
        pub const Field = struct {
            access: Class.FieldAccessFlags,

            name: []const u8,
            type: *const Type,
        };

        pub fn fieldByName(self: *const Self, name: []const u8) ?Field {
            for (self.fields) |f| if (std.mem.eql(u8, f.name, name)) return f;
            return null;
        }
    };

    // Annotated as '()->void' or '(int32)->java/lang/Object'
    pub const Fn = struct {
        params: []const Param,
        return_type: *const Type,
        body: []const Node,

        pub const Param = struct {
            name: []const u8,
            type: *const Type
        };
    };

    pub const Array = struct {
        elements: *const Type
    };

    /// A JVM object. Not sure how to do this, maybe a small runtime utility in jvm to check this stuff. Self-Hosted?
    pub const ExternType = struct {
        jvm_class: []const u8,
    };

    pub const ExternFn = struct {
        jvm_class: []const u8,
        name: []const u8,
        params: []const Fn.Param,
    };

    // No data
    pub const Int32 = void;
    pub const Float32 = void;
};