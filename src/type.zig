const std = @import("std");
const parser = @import("parser.zig");
const Class = @import("jvm/format.zig").Class;
const Node = @import("AST.zig").Node;

pub const Type = union(enum) {
    int: Int32,
    float: Float32,
    void: void,
    @"struct": Struct,
    @"fn": Fn,
    @"extern": ExternType,
    array: Array,

    pub fn jvmName(self: *const Type, gpa: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .int => "I",
            .float => "F",
            .void => "V",
            .@"fn" => "Ljava/lang/Function;",
            .@"struct" => |str| try classToDesc(gpa, str.name),
            .@"extern" => |ext| try classToDesc(gpa, ext.jvm_class),
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
    
    pub fn typeFromNamespace(alloc: std.mem.Allocator, ns: Node.Namespace) !Type {
        std.debug.print("Getting type from namespace: ", .{});
        const full_name = try ns.fullName(alloc);
        if (std.mem.eql(u8, full_name, "int")) {
            return Type.int;
        } else if (std.mem.eql(u8, full_name, "float")) {
            return Type.float;
        }
        if (full_name[0] == '(') {
            @panic("function types not supported.");
        }
        return Type{
            .@"extern" = .{
                .jvm_class = full_name,
            }
        };
    }

    pub const Struct = struct {
        name: []const u8,
        // fields are functions
        fields: []const Field,

        pub const Field = struct {
            access: Class.FieldAccessFlags,

            name: []const u8,
            type: *const Type,
        };
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