const std = @import("std");
const Stack = @import("util").Stack;
const ConstantPool = @import("../ConstantPool.zig");
const Type = @import("../type.zig").Type;
const format = @import("format.zig");
const Op = format.Op;
const gen = @import("gen.zig");
const Code = Op.Code;
const Node = @import("../AST.zig").Node;
const Class = format.Class;
const read = @import("read.zig");
const Context = @import("gen.zig").CodegenContext;

pub fn writeOpsFromNodes(context: *Context, nodes: []const Node) !void {
    for (nodes) |node| {
        try writeOpsFromNode(context, node);
    }
}

fn writeOpsFromNode(context: *Context, node: Node) !void {
    const gpa = context.allocator;
    std.debug.print("createCode0: Creating {s}\n", .{ @tagName(node) });
    switch (node) {
        .@"var" => |n| {
            std.debug.print("Varname = '{s}'\n", .{ n.name });
            try writeOpsFromNode(context, n.value.*);
            const this = try context.function.getOrCreateLocal(n.name, try context.inferType(n.value));
            switch (this.type.*) {
                .int => try context.function.writeOp(Op.Code.ISTORE, this.index),
                .float => try context.function.writeOp(Op.Code.FSTORE, this.index),
                else => try context.function.writeOp(Op.Code.ASTORE, this.index),
            }
        },
        .integer => |n| {
            const i = n.data;
            const abs = std.math.sign(i) * i;
            if (abs <= std.math.maxInt(i8)) {
                try context.function.writeOp(Op.Code.BIPUSH, n.data);
            } else if (abs <= std.math.maxInt(i16)) {
                try context.function.writeOp(Op.Code.SIPUSH, n.data);
            } else {
                const h = try context.cpool.add_integer(n.data);
                try context.function.pushConstant(h);
            }
            try context.function.op_stack.push(.int);
        },
        .field_access => |n| {
            const name = n.name;
            if (n.instance) |instance| {
                const inferred_type = try context.inferType(instance);
                try writeOpsFromNode(context, instance.*);
                var return_type: ?*const Type = null;
                for (inferred_type.@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, name)) return_type = f.type;
                }
                if (return_type == null) return error.FieldNotFound;
                const field_ref = try context.cpool.add_field_ref(
                    try inferred_type.jvmName(gpa),
                    name,
                    try return_type.?.jvmName(gpa)
                );
                try context.function.writeOp(.GETFIELD, field_ref);
            } else {
                if (context.function.getLocal(name)) |l| {
                    try context.function.loadLocal(l);
                } else if (context.static.getField(name)) |d| {
                    try context.function.writeOp(.GETSTATIC, d.index);
                } else {
                    std.debug.print("Unknown variable '{s}'.\n", .{ name });
                    return error.UnknownVariable;
                }
            }
        },
        .@"return" => |n| {
            if (n == null) {
                try context.function.writeOp(Op.Code.RETURN, 0);
                return;
            }
            // push the return value to the stack.
            try writeOpsFromNode(context, n.?.*);
            // Found out the specific return instruction we need.
            switch (context.function.op_stack.peek() orelse return error.NothingToReturn) {
                .int => try context.function.writeOp(.IRETURN, 0),
                .float => try context.function.writeOp(.FRETURN, 0),
                .long => try context.function.writeOp(.RETURN, 0),
                else => try context.function.writeOp(.ARETURN, 0),
            }
        },
        .fn_invoke => |n| {
            const name = n.name;
            const args = n.args;
            if (n.builtin) return try createBuiltinBytecode(context, name, args);
            if (n.instance) |instance| {
                const inferred_type = try context.inferType(instance);
                var return_type: ?*const Type = null;
                for (inferred_type.@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, name)) return_type = f.type;
                }
                if (return_type == null) return error.FieldNotFound;
                const method_ref = try context.cpool.add_method_ref(
                    try inferred_type.jvmName(gpa),
                    name,
                    try createMethodDesc(context, args, return_type.?)
                );
                // Pushes instance 'objectref' on the stack
                try writeOpsFromNode(context, instance.*);
                for (args) |a| {
                    // Pushes args on the stack
                    try writeOpsFromNode(context, a);
                }
                try context.function.writeOp(.INVOKEVIRTUAL, method_ref);
            } else {
                std.debug.print("Cannot find a function '{s}'.\n", .{ n.name });
                return error.CannotInferType;
            }
        },
        else => {
            std.debug.print("Unhandled node {any}\n", .{ node });
            return error.UnhandledNode;
        }
    }
}

// TODO move to gen
fn createMethodDesc(context: *Context, args: []const Node, ret: *const Type) ![]const u8 {
    const params = try context.allocator.alloc([]const u8, args.len);
    for (args, 0..) |a, i| {
        const typ = try context.inferType(&a);
        const name = try typ.jvmName(context.allocator);
        params[i] = name;
    }
    return try gen.assembleMethodDesc(context.allocator, params, try ret.jvmName(context.allocator));
}

fn createBuiltinBytecode(context: *Context, name: []const u8, args: []Node) !void {
    if (std.mem.eql(u8, name, "import")) {
        const arg = args[0].string.data;
        var split = std.mem.splitScalar(u8, arg, ':');
        _ = split.next() orelse "undefined";
        const path = split.rest();
        const class_ref_index = try context.cpool.add_class(path);
        // var import: ?*Type = context.getImport(path);
        // if (import) |_| {
        //     return;
        // } else if (std.mem.eql(u8, mode, "jvm")) {
        //     import = context.importPath(path);
        // } else {
        //     std.debug.print("Unknown import mode '{s}'.\n", .{ mode });
        //     return error.UnknownMode;
        // }
        try context.function.pushConstant(class_ref_index);
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
        for (args) |arg| {
            switch (arg) {
                .string => |str| {
                    code = getCode(str.data);
                },
                .integer => |i| try context.function.writeOp(code, i.data),
                .byte => |c| try context.function.writeOp(code, c.data),
                else => return error.UnexpectedType,
            }
        }
    } else {
        return error.UndefinedBuiltin;
    }
}

fn createFieldAccess(context: *Context, field: []const u8, typ: Type) !void {
    _ = field; _ = typ;
    switch (context.stack.peek().?) {
    // getstatic
        .class_ref => {
    },
        // getfield
        else => {

        }
    }
}

const sout = std.debug.print;

pub fn print(bytecode: []const u8, print_constants: ?*Class) !void {
    var fixedReader = std.Io.Reader.fixed(bytecode);
    const r = &fixedReader;
    while (r.seek < r.end) {
        var code: ?Op.Code = null;
        const op_byte = try r.takeByte();
        inline for (@typeInfo(Op.Code).@"enum".fields) |op| {
            if (op.value == op_byte) {
                code = @enumFromInt(op.value);
            }
        }
        if (code == null) {
            std.debug.print("Unknown op code {}.\n", .{ op_byte });
            return error.UnknownOpCode;
        }
        printOp(r, print_constants, code.?) catch |e| {
            sout("\nError while printing op {?}.\n", .{ code });
            return e;
        };
    }
}

fn printConstant(comptime width: type, r: *std.Io.Reader, maybePool: ?*Class) !void {
    const indx = try r.takeInt(width, .big);
    sout(", {any}", .{ indx });
    if (maybePool) |pool| {
        const cp = pool.constant_pool;
        sout(" ({s} ", .{ @tagName(cp[indx - 1]) });
        switch (cp[indx - 1]) {
            .utf_8_info => |c| sout("'{s}'", .{ c.bytes }),
            .class_info => |c| sout("{s}", .{ cp[c.name_index - 1].utf_8_info.bytes }),
            .integer_info => |c| sout("{d}", .{ std.math.cast(i32, c.bytes).? }),
            .name_and_type_info => |c| sout("{s} {s}", .{
                cp[c.name_index - 1].utf_8_info.bytes,
                cp[c.descriptor_index - 1].utf_8_info.bytes }
            ),
            else => |c| sout("{any}", .{ c }),
        }
        sout(")\n", .{});
    } else sout("\n", .{});
}

fn printOp(r: *std.Io.Reader, class: ?*Class, op: Op.Code) !void {
    const meta = Op.meta(op) orelse return error.UndefinedMeta;
    sout(" | {s}", .{ meta.mnemonic });
    switch (meta.operand_form) {
        .none => sout("\n", .{}),
        .I8, => sout(", {any}\n", .{ try r.takeInt(i8, .big) }),
        .U8, .local => sout(", {any}\n", .{ try r.takeInt(u8, .big) }),
        .U16 => sout(", {any}\n", .{ try r.takeInt(u16, .big) }),
        .I16 => sout(", {any}\n", .{ try r.takeInt(i16, .big) }),
        .U8_constant => try printConstant(u8, r, class),
        .U16_constant => try printConstant(u16, r, class),
        .branch_offset => sout(", {any}\n", .{ try r.takeInt(i16, .big) }),
        else => {
            std.debug.print("\nUnhandled operand form '{s}'.\n", .{ @tagName(meta.operand_form) });
            return error.Unhandled;
        }
    }
}