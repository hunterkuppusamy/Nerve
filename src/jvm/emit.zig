const std = @import("std");
const Type = @import("../type.zig").Type;
const format = @import("format.zig");
const Op = format.Op;
const Node = @import("../AST.zig").Node;
const ctx = @import("context.zig");
const FunctionContext = ctx.FunctionContext;
const generate = @import("generate.zig");
const infer = @import("infer.zig");

const EmitError = infer.InferError || std.mem.Allocator.Error || std.Io.Writer.Error || error{
    NoSuchField,
    UnknownVariable,
    NothingToReturn,
    FieldNotFound,
    NoSuchFunction,
    UnsupportedBinaryOp,
    UnhandledNode,
    UnexpectedType,
    UndefinedBuiltin,
    NoOpCodeMeta,
};

pub fn bytecodeOf(fctx: *FunctionContext, nodes: []const Node) EmitError!void {
    for (nodes) |node| try emitNode(fctx, node);
}

fn pushInt(fctx: *FunctionContext, comptime T: type, v: anytype) EmitError!void {
    const i: T = std.math.cast(T, v).?;
    const abs = std.math.sign(i) * i;
    if (abs <= std.math.maxInt(i8)) {
        try fctx.writeOp(Op.Code.BIPUSH, i);
    } else if (abs <= std.math.maxInt(i16)) {
        try fctx.writeOp(Op.Code.SIPUSH, i);
    } else {
        const h = try fctx.class.cpool.add_integer(i);
        try fctx.pushConstant(h);
    }
    try fctx.op_stack.push(.int);
}

fn emitNode(fctx: *FunctionContext, node: Node) EmitError!void {
    const gpa = fctx.class.allocator();
    std.debug.print("writeOpsFromNode: Creating {s}\n", .{@tagName(node)});
    defer std.debug.print("writeOpsFromNode: stack = {}\n", .{fctx.op_stack.list});
    switch (node) {
        .@"var" => |n| try emitVar(fctx, n),
        .integer => |n| try pushInt(fctx, i32, n.data),
        .field_access => |n| try emitFieldAccess(fctx, n),
        .@"return" => |n| try emitReturn(fctx, n),
        .fn_invoke => |n| try emitFnInvoke(fctx, n),
        .string => |s| {
            const i = try fctx.class.cpool.add_string(s.data);
            try fctx.pushConstant(i);
        },
        .binary_op => |n| try emitBinaryOp(fctx, gpa, node, n),
        else => {
            std.debug.print("Unhandled node {any}\n", .{node});
            return error.UnhandledNode;
        },
    }
}

fn emitVar(fctx: *FunctionContext, n: Node.VarDecl) EmitError!void {
    std.debug.print("Varname = '{s}'\n", .{n.name});
    try emitNode(fctx, n.value.*);
    const local = try fctx.getOrCreateLocal(n.name, try fctx.inferType(n.value));
    switch (local.type.*) {
        .int => try fctx.writeOp(Op.Code.ISTORE, local.index),
        .float => try fctx.writeOp(Op.Code.FSTORE, local.index),
        else => try fctx.writeOp(Op.Code.ASTORE, local.index),
    }
}

fn emitFieldAccess(fctx: *FunctionContext, n: Node.FieldAccess) EmitError!void {
    const gpa = fctx.class.allocator();
    if (n.instance) |instance| {
        const inferred_type = (try fctx.inferType(instance)).@"struct";
        try emitNode(fctx, instance.*);
        const field = inferred_type.fieldByName(n.name) orelse return error.NoSuchField;
        const field_ref = try fctx.class.cpool.add_field_ref(
            inferred_type.name,
            n.name,
            try field.type.jvmName(gpa),
        );
        if (field.access.static) {
            try fctx.writeOp(.GETSTATIC, field_ref);
        } else {
            try fctx.writeOp(.GETFIELD, field_ref);
        }
        try fctx.op_stack.push(.object);
    } else {
        if (fctx.getLocal(n.name)) |l| {
            try fctx.loadLocal(l);
            try fctx.op_stack.push(.object);
        } else if (fctx.class.file.getStatic(n.name)) |_| {
            // TODO: emit GETSTATIC for file-level statics
        } else {
            std.debug.print("Unknown variable '{s}'.\n", .{n.name});
            return error.UnknownVariable;
        }
    }
}

fn emitReturn(fctx: *FunctionContext, n: ?*Node) EmitError!void {
    if (n == null) {
        try fctx.writeOp(Op.Code.RETURN, 0);
        return;
    }
    try emitNode(fctx, n.?.*);
    switch (fctx.op_stack.peek() orelse return error.NothingToReturn) {
        .int => try fctx.writeOp(.IRETURN, 0),
        .float => try fctx.writeOp(.FRETURN, 0),
        .long => try fctx.writeOp(.RETURN, 0),
        else => try fctx.writeOp(.ARETURN, 0),
    }
}

fn emitFnInvoke(fctx: *FunctionContext, n: Node.FnInvoke) EmitError!void {
    if (n.builtin) return try emitBuiltin(fctx, n.name, n.args);
    if (n.instance) |instance| {
        try emitInstanceCall(fctx, instance, n.name, n.args);
    } else {
        try emitStaticCall(fctx, n.name, n.args);
    }
}

fn emitInstanceCall(fctx: *FunctionContext, instance: *const Node, name: []const u8, args: []const Node) EmitError!void {
    const inferred_type = try fctx.inferType(instance);
    const inferred_struct = inferred_type.@"struct";
    var return_type: ?*const Type = null;

    fnloop: for (inferred_struct.fields) |f| {
        if (!std.mem.eql(u8, f.name, name)) continue;
        if (f.type.* != .@"fn") continue;
        const function = f.type.@"fn";
        if (function.params.len != args.len) continue;
        for (function.params, 0..) |p, i| {
            if (try fctx.inferType(&args[i]) != p.type) continue :fnloop;
        }
        std.debug.print("Selected function {s}:{s}\n", .{ inferred_struct.name, f.name });
        return_type = function.return_type;
    }
    if (return_type == null) return error.FieldNotFound;

    const method_ref = try fctx.class.cpool.add_method_ref(
        inferred_struct.name,
        name,
        try createMethodDesc(fctx, args, return_type.?),
    );
    try emitNode(fctx, instance.*);
    for (args) |a| try emitNode(fctx, a);
    try fctx.writeOp(.INVOKEVIRTUAL, method_ref);
    if (return_type) |r| switch (r.*) {
        .void => {},
        else => try fctx.op_stack.push(.object),
    };
}

fn emitStaticCall(fctx: *FunctionContext, name: []const u8, args: []const Node) EmitError!void {
    var return_type: ?*const Type = null;
    for (fctx.class.file.statics.decls.items) |f| {
        if (std.mem.eql(u8, f.name, name) and f.type.* == .@"fn") {
            return_type = f.type.@"fn".return_type;
        }
    }
    if (return_type == null) return error.NoSuchFunction;

    const method_ref = try fctx.class.cpool.add_method_ref(
        fctx.class.name,
        name,
        try createMethodDesc(fctx, args, return_type.?),
    );
    for (args) |a| try emitNode(fctx, a);
    try fctx.writeOp(.INVOKESTATIC, method_ref);
    if (return_type) |r| switch (r.*) {
        .void => {},
        else => try fctx.op_stack.push(.object),
    };
}

fn emitBinaryOp(fctx: *FunctionContext, gpa: std.mem.Allocator, node: Node, n: Node.BinaryOp) EmitError!void {
    const lhs_type = try fctx.inferType(n.lhs);
    switch (lhs_type.*) {
        .int => {
            try emitNode(fctx, n.lhs.*);
            try emitNode(fctx, n.rhs.*);
            try fctx.writeOp(switch (n.op) {
                .add => .IADD, .sub => .ISUB, .mul => .IMUL, .div => .IDIV,
                else => return error.UnsupportedBinaryOp,
            }, 0);
            _ = fctx.op_stack.pop();
        },
        .float => {
            try emitNode(fctx, n.lhs.*);
            try emitNode(fctx, n.rhs.*);
            try fctx.writeOp(switch (n.op) {
                .add => .FADD, .sub => .FSUB, .mul => .FMUL, .div => .FDIV,
                else => return error.UnsupportedBinaryOp,
            }, 0);
            _ = fctx.op_stack.pop();
        },
        .@"struct" => try emitStringConcat(fctx, gpa, node),
        else => return error.UnsupportedBinaryOp,
    }
}

fn emitStringConcat(fctx: *FunctionContext, gpa: std.mem.Allocator, node: Node) EmitError!void {
    const cpool = fctx.class.cpool;
    const sb_class = try cpool.add_class("java/lang/StringBuilder");
    const init_ref = try cpool.add_method_ref("java/lang/StringBuilder", "<init>", "()V");
    const append_string = try cpool.add_method_ref(
        "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;",
    );
    const append_int = try cpool.add_method_ref(
        "java/lang/StringBuilder", "append", "(I)Ljava/lang/StringBuilder;",
    );
    const to_string = try cpool.add_method_ref(
        "java/lang/StringBuilder", "toString", "()Ljava/lang/String;",
    );

    try fctx.writeOp(.NEW, sb_class);
    try fctx.writeOp(.DUP, 0);
    try fctx.writeOp(.INVOKESPECIAL, init_ref);
    try fctx.op_stack.push(.object);

    var parts = try std.ArrayList(Node).initCapacity(gpa, 4);
    collectConcatParts(gpa, node, &parts);

    for (parts.items) |part| {
        try emitNode(fctx, part);
        const part_type = try fctx.inferType(&part);
        try fctx.writeOp(.INVOKEVIRTUAL, switch (part_type.*) {
            .int => append_int,
            else => append_string,
        });
        _ = fctx.op_stack.pop();
    }

    try fctx.writeOp(.INVOKEVIRTUAL, to_string);
}

fn collectConcatParts(gpa: std.mem.Allocator, node: Node, parts: *std.ArrayList(Node)) void {
    switch (node) {
        .binary_op => |n| if (n.op == .add) {
            collectConcatParts(gpa, n.lhs.*, parts);
            collectConcatParts(gpa, n.rhs.*, parts);
            return;
        },
        else => {},
    }
    parts.append(gpa, node) catch @panic("OOM");
}

fn emitBuiltin(fctx: *FunctionContext, name: []const u8, args: []Node) EmitError!void {
    if (std.mem.eql(u8, name, "import")) {
        const arg = args[0].string.data;
        var split = std.mem.splitScalar(u8, arg, ':');
        _ = split.next() orelse "undefined";
        const path = split.rest();
        const class_ref_index = try fctx.class.cpool.add_class(path);
        try fctx.pushConstant(class_ref_index);
    } else if (std.mem.eql(u8, name, "asm")) {
        const codes = @typeInfo(Op.Code).@"enum".fields;
        const getCode = struct {
            pub fn codeFromName(cname: []const u8) Op.Code {
                inline for (codes) |code| {
                    if (std.mem.eql(u8, code.name, cname)) return @enumFromInt(code.value);
                }
                @panic("Unknown op code.");
            }
        }.codeFromName;
        var code: Op.Code = undefined;
        for (args) |arg| switch (arg) {
            .string => |str| code = getCode(str.data),
            .integer => |i| try fctx.writeOp(code, i.data),
            .byte => |c| try fctx.writeOp(code, c.data),
            else => return error.UnexpectedType,
        };
    } else {
        return error.UndefinedBuiltin;
    }
}

fn createMethodDesc(fctx: *FunctionContext, args: []const Node, ret: *const Type) EmitError![]const u8 {
    const gpa = fctx.class.allocator();
    const params = try gpa.alloc([]const u8, args.len);
    for (args, 0..) |a, i| {
        params[i] = try (try fctx.inferType(&a)).jvmName(gpa);
    }
    return generate.assembleMethodDesc(gpa, params, try ret.jvmName(gpa));
}
