const std = @import("std");
const parser = @import("parser.zig");
const Class = @import("jvm/format.zig").Class;
const Node = @import("AST.zig").Node;
const ProgramContext = @import("jvm/gen.zig").ProgramContext;

pub const Type = union(enum) {
    // Primitives with no meta-data.
    int,
    float,
    long,
    double,
    void,

    @"struct": Struct,
    @"fn": Fn,
    /// Not currently parsable, but exists to implement `Main.main([]String args){}`
    array: Array,

    pub fn jvmName(self: *const Type, gpa: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .int => "I",
            .float => "F",
            .long => "J",
            .double => "D",
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

    fn classToDesc(gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
        const len = path.len;
        const new = try gpa.alloc(u8, len + 2);
        @memcpy(new[1..(new.len - 1)], path);
        new[0] = 'L';
        new[new.len - 1] = ';';
        return new;
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
};