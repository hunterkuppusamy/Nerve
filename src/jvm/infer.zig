const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Type = @import("../type.zig").Type;
const Node = @import("../AST.zig").Node;
const ctx = @import("context.zig");
const FunctionContext = ctx.FunctionContext;
const FileContext = ctx.FileContext;
const import = @import("import.zig");

pub const InferError = import.ImportError || error{
    CannotInferType,
    NoSuchFunction,
};

pub fn inferType(fctx: *FunctionContext, node: *const Node) InferError!*const Type {
    const gpa = fctx.class.allocator();
    const file = fctx.class.file;
    const global = file.global;
    switch (node.*) {
        .@"var" => |n| {
            var var_type = if (n.type) |ret| try inferType(fctx, ret)
                else try inferType(fctx, n.value);
            switch (var_type.*) {
                .@"struct" => |t| {
                    const named_ptr = try gpa.create(Type);
                    named_ptr.* = .{ .@"struct" = .{ .name = n.name, .fields = t.fields } };
                    gpa.destroy(var_type);
                    var_type = named_ptr;
                },
                else => {},
            }
            return var_type;
        },
        .integer => return &@as(Type, Type.int),
        .float => return &@as(Type, Type.float),
        .type_decl => |n| return inferTypeDecl(fctx, file, n),
        .fn_decl => |n| return inferFnDecl(fctx, n),
        .fn_invoke => |n| return inferFnInvoke(fctx, file, global, n),
        .field_access => |n| return inferFieldAccess(fctx, file, n),
        .string => return global.getImport("java/lang/String").?,
        .binary_op => |n| {
            const lhs_type = try inferType(fctx, n.lhs);
            return switch (lhs_type.*) {
                .@"struct" => global.getImport("java/lang/String").?,
                else => lhs_type,
            };
        },
        .array_of => |n| {
            const arr = try gpa.create(Type);
            arr.* = .{ .array = .{ .elements = try inferType(fctx, n.element_type) } };
            return arr;
        },
        else => {},
    }
    std.debug.print("Cannot infer type of {any}.\n", .{node});
    return error.CannotInferType;
}

fn inferTypeDecl(fctx: *FunctionContext, file: *FileContext, n: Node.TypeDecl) InferError!*const Type {
    const gpa = fctx.class.allocator();
    var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 8);

    for (n.fields) |f| {
        const decl = f.@"var";
        const mods = decl.mods;
        var flags = Class.FieldAccessFlags{};
        flags.public = mods.public;
        flags.final = mods.constant;
        flags.static = mods.static;
        const type_ptr = if (decl.type) |explicit|
            try inferType(fctx, explicit)
        else
            try inferType(fctx, decl.value);

        std.debug.print("Adding static {s} to context.\n", .{decl.name});
        try file.putStatic(decl.name, type_ptr);
        try fields.append(gpa, .{
            .access = flags,
            .name = decl.name,
            .type = type_ptr,
        });
    }

    const ptr = try gpa.create(Type);
    ptr.* = .{ .@"struct" = .{ .name = undefined, .fields = try fields.toOwnedSlice(gpa) } };
    return ptr;
}

fn inferFnDecl(fctx: *FunctionContext, n: Node.FnDecl) InferError!*const Type {
    const gpa = fctx.class.allocator();
    var nodes: []const Node = undefined;
    if (n.body.* == Node.body) {
        nodes = n.body.body.nodes;
    } else {
        const var_nodes = try gpa.alloc(Node, 1);
        var_nodes[0] = n.body.*;
        nodes = var_nodes;
    }
    var params = try std.ArrayList(Type.Fn.Param).initCapacity(gpa, 2);
    for (n.params) |p| {
        try params.append(gpa, .{ .name = p.name, .type = try inferType(fctx, p.type) });
    }
    const ptr = try gpa.create(Type);
    ptr.* = .{ .@"fn" = .{
        .body = try gpa.dupe(Node, nodes),
        .params = try params.toOwnedSlice(gpa),
        .return_type = try inferType(fctx, n.return_type),
    } };
    return ptr;
}

fn inferFnInvoke(fctx: *FunctionContext, file: *FileContext, global: *ctx.GlobalContext, n: Node.FnInvoke) InferError!*const Type {
    if (n.builtin) {
        if (std.mem.eql(u8, n.name, "import")) {
            const path = n.args[0].string.data;
            return global.getImport(path) orelse try global.importClassName(path);
        } else if (std.mem.eql(u8, n.name, "asm")) {
            return switch (fctx.op_stack.peek() orelse return &@as(Type, Type.void)) {
                .int => &@as(Type, Type.int),
                .float => &@as(Type, Type.float),
                else => error.CannotInferType,
            };
        }
        std.debug.print("Unknown builtin '{s}'.\n", .{n.name});
        return error.CannotInferType;
    }
    if (n.instance) |this| {
        const this_type = (try inferType(fctx, this)).@"struct";
        for (this_type.fields) |f| {
            if (std.mem.eql(u8, f.name, n.name)) return f.type.@"fn".return_type;
        }
        std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
        return error.NoSuchFunction;
    } else {
        const typ = if (fctx.getLocal(n.name)) |l|
            l.type
        else if (file.getStatic(n.name)) |d|
            d.type
        else
            return error.CannotInferType;
        return switch (typ.*) {
            .@"fn" => |f| f.return_type,
            else => typ,
        };
    }
}

fn inferFieldAccess(fctx: *FunctionContext, file: *FileContext, n: Node.FieldAccess) InferError!*const Type {
    if (n.instance) |this| {
        const this_type = (try inferType(fctx, this)).@"struct";
        for (this_type.fields) |f| {
            if (std.mem.eql(u8, f.name, n.name)) return f.type;
        }
        std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
        return error.CannotInferType;
    } else if (fctx.getLocal(n.name)) |l| {
        return l.type;
    } else if (file.getStatic(n.name)) |d| {
        return d.type;
    } else {
        std.debug.print("Could not find local or static field '{s}'.\n", .{n.name});
        return error.CannotInferType;
    }
}
