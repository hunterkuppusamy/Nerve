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
const ProgramContext = @import("gen.zig").ProgramContext;

pub const CodeContext = struct {
    allocator: std.mem.Allocator,
    /// String Variable Name -> Local Variable Index
    data: std.Io.Writer.Allocating,
    /// Constant Class ref index -> Type
    imported: std.AutoHashMap(u16, Type),
    locals: Stack(Local),
    cpool: *ConstantPool,
    stack: Stack(JvmStackType),

    pub const JvmStackType = enum {
        int,         float,       long,       double,
        int_array,   float_array, long_array, double_array,
        object,      class_ref,   method_ref, field_ref,
        object_array,
    };

    pub const Local = struct {
        index: u16,
        name: []const u8,
        type: Type,
    };

    pub fn init(allocator: std.mem.Allocator, cpool: *ConstantPool) !CodeContext {
        return CodeContext {
            .allocator = allocator,
            .data = std.Io.Writer.Allocating.init(allocator),
            .cpool = cpool,
            .locals = try Stack(Local).init(allocator),
            .imported = std.AutoHashMap(u16, Type).init(allocator),
            .stack = try Stack(JvmStackType).init(allocator),
        };
    }

    pub fn toOwnedCode(self: *CodeContext) !Class.Attribute {
        defer self.locals.deinit();
        defer self.data.deinit();
        const byte_code = try self.data.toOwnedSlice();
        std.debug.print("Created bytecode\n", .{});
        try print(byte_code, self.cpool.class);
        const code = Class.Attribute.Code {
            .code = byte_code,
            .max_locals = @intCast(self.locals.list.items.len + 2),
            .max_stack = 32,
            .exception_table = &[0]Class.Attribute.Code.Exception{},
            .attributes = &[0]Class.Attribute{},
        };
        const name_h = try self.cpool.add_utf8("Code");
        const attr_len = 12 + code.code.len + (code.exception_table.len * 8);
        std.debug.print("toOwnedCode: CodeAttr code len = {any}.\n", .{ code.code.len });
        return .{
            .attribute_name_index = @intCast(name_h),
            .attribute_length = @intCast(attr_len),
            .info = .{
                .code = code
            }
        };
    }

    pub fn getOrCreateLocal(self: *CodeContext, name: []const u8, typ: Type) !Local {
        var l: ?Local = self.getLocal(name);
        if (l) |ret| return ret;
        const idx: u16 = @intCast(self.locals.list.items.len);
        l = Local {
            .index = idx,
            .name = name,
            .type = typ,
        };
        try self.locals.push(l.?);
        return l.?;
    }

    pub fn loadLocal(self: *CodeContext, local: Local) !void {
        try switch (local.type) {
            .int => self.writeOp(Op.Code.ILOAD, local.index),
            .float => self.writeOp(Op.Code.FLOAD, local.index),
            else => self.writeOp(Op.Code.ALOAD, local.index),
        };
    }

    pub fn getLocal(self: *CodeContext, name: []const u8) ?Local {
        const len = self.locals.list.items.len;
        std.debug.print("Local len = {d}\n", .{ len });
        if (len <= 0) return null;
        var i = len - 1;
        while (i >= 0) : (i -= 1) {
            const l = self.locals.list.items[i];
            std.debug.print("Local '{s}'\n", .{ l.name });
            if (std.mem.eql(u8, l.name, name)) return l;
            if (i == 0) break;
        }
        return null;
    }

    pub fn writeOp(self: *CodeContext, code: Op.Code, operand: anytype) !void {
        std.debug.print("writeOp: writing op '{s}' {any}.\n", .{ @tagName(code), operand });
        const inf = Op.meta(code)  orelse return error.NoOpCodeMeta;
        // Write opcode
        //try self.buffer.append(self.allocator, @intFromEnum(code));
        try self.data.writer.writeInt(u8, @intFromEnum(code), .big);
        // Write params.
        switch (inf.operand_form) {
            .none => {},
            .U8, .I8, .local, .U8_constant, => try self.data.writer.writeInt(u8,  @intCast(operand), .big),
            .U16, .U16_constant =>        try self.data.writer.writeInt(u16, @intCast(operand), .big),
            .I16, .branch_offset =>   try self.data.writer.writeInt(i16, @intCast(operand), .big), // branch offsets stored as bi-endian signed 16
            .offset_w =>        try self.data.writer.writeInt(u32, @intCast(operand), .big),
            .contextual => @panic("cannot emit variable-length opcode generically"),
            .local_index_const => {
                // iinc: two bytes (index, const)
                // const ind = @field(operand, "0"); // or use a specialized struct
                // const c = @field(operand, "1");
                // try self.data.writer.writeInt(u16, ind, .big);
                // try self.data.writer.writeInt(u16, c, .big);
            },
        }
    }

    pub fn pushConstant(self: *CodeContext, h: usize) !void {
        const c = self.cpool.class.constant_pool.items[h - 1];
        switch (c) {
            .long_info, .double_info => {
                try self.writeOp(Op.Code.LDC2_W, h);
                return;
            },
            else => {}
        }
        if (h <= std.math.maxInt(u8)) {
            try self.writeOp(Op.Code.LDC, h);
        } else {
            try self.writeOp(Op.Code.LDC_W, h);
        }
    }

    pub fn create(code: *CodeContext, program: *ProgramContext, body: []const Node) !void {
        std.debug.print("createCode: Creating code for {any} nodes.\n", .{ body.len });
        for (body) |node| {
            try createCode0(program, code, node);
        }
    }
};

pub fn inferType(program: *ProgramContext, code: *CodeContext, node: *const Node) !Type {
    switch (node.*) {
        .@"var" => |n| {
            if (n.type) |ret| return try inferType(program, code, ret);
        },
        .integer => return Type.int,
        .float => return Type.float,
        .fn_decl => |n| {
            var nodes: []const Node = undefined;
            if (n.body.* == Node.body) { nodes = n.body.body.nodes; } else {
                const var_nodes = try code.allocator.alloc(Node, 1);
                var_nodes[0] = n.body.*;
                nodes = var_nodes;
            }
            var params = try std.ArrayList(Type.Fn.Param).initCapacity(code.allocator, 2);
            for (n.params) |p| {
                const type_ptr = try code.allocator.create(Type);
                type_ptr.* = try inferType(program, code, p.type);
                try params.append(code.allocator, Type.Fn.Param {
                    .name = p.name,
                    .type = type_ptr
                });
            }
            const rtype = try code.allocator.create(Type);
            rtype.* = try inferType(program, code, n.return_type);
            return Type {
                .@"fn" = .{
                    .body = try code.allocator.dupe(Node, nodes),
                    .params = try params.toOwnedSlice(code.allocator),
                    .return_type = rtype,
                }
            };
        },
        .fn_invoke => |n| {
            if (n.builtin) {
                const name = n.name;
                if (std.mem.eql(u8, name, "import")) {
                    const path = n.args[0].string.data;
                    const class = try read.readClass(program.allocator, path);
                    const imported = try Type.ofClass(program, class);
                    const ret = imported.*;
                    program.allocator.destroy(imported);
                    return ret;
                } else if (std.mem.eql(u8, name, "asm")) {
                    return switch (code.stack.peek() orelse return Type.void) {
                        .int => Type.int,
                        .float => Type.float,
                        else => error.CannotInferType,
                    };
                }
                std.debug.print("Unknown builtin '{s}'.\n", .{ name });
                return error.CannotInferType;
            }
            const instance = n.instance;
            if (instance) |this| {
                const this_type = (try inferType(program, code, this)).@"struct";
                for (this_type.fields) |f| {
                    if (std.mem.eql(u8, f.name, n.name)) return f.type.@"fn".return_type.*;
                }
                std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
                return error.CannotInferType;
            } else {
                return code.getLocal(n.name).?.type;
            }
        },
        .field_access => |n| {
            const instance = n.instance;
            if (instance) |this| {
                const this_type = (try inferType(program, code, this)).@"struct";
                for (this_type.fields) |f| {
                    if (std.mem.eql(u8, f.name, n.name)) return f.type.*;
                }
                std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
                return error.CannotInferType;
            } else {
                return code.getLocal(n.name).?.type;
            }
        },
        else => {}
    }
    std.debug.print("Cannot infer type of {any}.\n", .{ node });
    return error.CannotInferType;
}

fn createCode0(program: *ProgramContext, code: *CodeContext, node: Node) !void {
    std.debug.print("createCode0: Creating {s}\n", .{ @tagName(node) });
    switch (node) {
        .@"var" => |n| {
            std.debug.print("Varname = '{s}'\n", .{ n.name });
            try createCode0(program, code, n.value.*);
            const this = try code.getOrCreateLocal(n.name, try inferType(program, code, n.value));
            switch (this.type) {
                .int => try code.writeOp(Op.Code.ISTORE, this.index),
                .float => try code.writeOp(Op.Code.FSTORE, this.index),
                else => try code.writeOp(Op.Code.ASTORE, this.index),
            }
        },
        .integer => |n| {
            const i = n.data;
            const abs = std.math.sign(i) * i;
            if (abs <= std.math.maxInt(i8)) {
                try code.writeOp(Op.Code.BIPUSH, n.data);
            } else if (abs <= std.math.maxInt(i16)) {
                try code.writeOp(Op.Code.SIPUSH, n.data);
            } else {
                const h = try code.cpool.add_integer(n.data);
                try code.pushConstant(h);
            }
            try code.stack.push(.int);
        },
        .field_access => |n| {
            const name = n.name;
            if (n.instance) |instance| {
                const inferred_type = try inferType(program, code, instance);
                try createCode0(program, code, instance.*);
                var return_type: ?*const Type = null;
                for (inferred_type.@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, name)) return_type = f.type;
                }
                if (return_type == null) return error.FieldNotFound;
                const field_ref = try code.cpool.add_field_ref(try inferred_type.jvmName(code.allocator), name, try return_type.?.jvmName(code.allocator));
                try code.writeOp(Op.Code.GETFIELD, field_ref);
            } else {
                const local = code.getLocal(name);
                if (local) |l| {
                    try code.loadLocal(l);
                } else {
                    std.debug.print("Unknown variable '{s}'.\n", .{ name });
                    return error.UnknownVariable;
                }
            }
        },
        .@"return" => |n| {
            if (n == null) {
                try code.writeOp(Op.Code.RETURN, 0);
                return;
            }
            try createCode0(program, code, n.?.*);
            switch (code.stack.peek() orelse return error.NothingToReturn) {
                .int => try code.writeOp(Op.Code.IRETURN, 0),
                .float => try code.writeOp(Op.Code.FRETURN, 0),
                else => try code.writeOp(Op.Code.ARETURN, 0),
            }
        },
        .fn_invoke => |n| {
            const name = n.name;
            const args = n.args;
            if (n.builtin) return try createBuiltin(program, code, name, args);
            if (n.instance) |instance| {
                const inferred_type = try inferType(program, code, instance);
                var return_type: ?*const Type = null;
                for (inferred_type.@"struct".fields) |f| {
                    if (std.mem.eql(u8, f.name, name)) return_type = f.type;
                }
                if (return_type == null) return error.FieldNotFound;
                const method_ref = try code.cpool.add_method_ref(
                    try inferred_type.jvmName(code.allocator),
                    name,
                    try createMethodDesc(program, code, args, return_type.?)
                );
                // Pushes instance 'objectref' on the stack
                try createCode0(program, code, instance.*);
                for (args) |a| {
                    // Pushes args on the stack
                    try createCode0(program, code, a);
                }
                try code.writeOp(Op.Code.INVOKEVIRTUAL, method_ref);
            } else {

            }
        },
        else => {
            std.debug.print("Unhandled node {any}\n", .{ node });
            return error.UnhandledNode;
        }
    }
}

fn createMethodDesc(program: *ProgramContext, code: *CodeContext, args: []const Node, ret: *const Type) ![]const u8 {
    const params = try program.allocator.alloc([]const u8, args.len);
    for (args, 0..) |a, i| {
        const typ = try inferType(program, code, &a);
        const name = try typ.jvmName(program.allocator);
        params[i] = name;
    }
    return try gen.assembleMethodDesc(program, params, try ret.jvmName(program.allocator));
}

fn createBuiltin(program: *ProgramContext, context: *CodeContext, name: []const u8, args: []Node) !void {
    if (std.mem.eql(u8, name, "import")) {
        const class = args[0].string.data;
        const class_h = try context.cpool.add_class(class);
        try context.pushConstant(class_h);
        var split = std.mem.splitScalar(u8, class, ':');
        const mode = split.next() orelse "undefined";
        var import: *Type = undefined;
        if (std.mem.eql(u8, mode, "jvm")) {
            import = try Type.ofClass(program, try read.readClass(context.allocator, split.rest()));
        } else {
            import = program.types.getPtr(class).?;
        }
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
                .integer => |i| try context.writeOp(code, i.data),
                .byte => |c| try context.writeOp(code, c.data),
                else => return error.UnexpectedType,
            }
        }
    } else {
        return error.UndefinedBuiltin;
    }
}

fn createFieldAccess(context: *CodeContext, field: []const u8, typ: Type) !void {
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
        const cp = pool.constant_pool.items;
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