const std = @import("std");
const Stack = @import("util").Stack;
const ConstantPool = @import("../ConstantPool.zig");
const Type = @import("../type.zig").Type;
const format = @import("format.zig");
const Op = format.Op;
const Code = Op.Code;
const Node = @import("../AST.zig").Node;
const Class = format.Class;
const read = @import("read.zig");

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

    pub fn create(context: *CodeContext, body: []const Node) !void {
        std.debug.print("createCode: Creating code for {any} nodes.\n", .{ body.len });
        for (body) |node| {
            try createCode0(context, node);
        }
    }
};

fn inferType(context: *CodeContext, node: Node) !Type {
    switch (node) {
        .@"var" => |n| {
            if (n.type) |ret| return try inferType(context, ret.*);
        },
        .integer => return Type.int,
        .float => return Type.float,
        .fn_decl => |n| {
            var nodes: []Node = undefined;
            if (n.body.* == Node.body) { nodes = n.body.body.nodes; } else {
                nodes = try context.allocator.alloc(Node, 1);
                nodes[0] = n.body.*;
            }
            var params = try std.ArrayList(Type.Fn.Param).initCapacity(context.allocator, 2);
            for (n.params) |p| {
                const type_ptr = try context.allocator.create(Type);
                type_ptr.* = try Type.typeFromNamespace(context.allocator, p.type.namespace);
                try params.append(context.allocator, Type.Fn.Param {
                    .name = p.name,
                    .type = type_ptr
                });
            }
            return Type {
                .@"fn" = .{
                    .body = try context.allocator.dupe(Node, nodes),
                    .params = try params.toOwnedSlice(context.allocator),
                    .return_type = n.return_type,
                }
            };
        },
        .fn_invoke => |n| {
            if (n.builtin) {
                const ns = n.namespace.namespace.data;
                const name = ns[ns.len - 1];
                if (std.mem.eql(u8, name, "import")) return Type {
                    .@"extern" = .{
                        .jvm_class = n.args[0].string.data
                    }
                } else if (std.mem.eql(u8, name, "asm")) {
                    return switch (context.stack.peek() orelse return Type.void) {
                        .int => Type.int,
                        .float => Type.float,
                        else => error.CannotInferType,
                    };
                }
            }
        },
        .namespace => |n| {
            const data = n.data;
            if (data.len == 1) return context.getLocal(data[0]).?.type;
        },
        else => {}
    }
    std.debug.print("Cannot infer type of {any}.\n", .{ node });
    return error.CannotInferType;
}

fn createCode0(context: *CodeContext, node: Node) !void {
    std.debug.print("createCode0: Creating {s}\n", .{ @tagName(node) });
    switch (node) {
        .@"var" => |n| {
            std.debug.print("Varname = '{s}'\n", .{ n.name });
            try createCode0(context, n.value.*);
            const this = try context.getOrCreateLocal(n.name, try inferType(context, n.value.*));
            switch (this.type) {
                .int => try context.writeOp(Op.Code.ISTORE, this.index),
                .float => try context.writeOp(Op.Code.FSTORE, this.index),
                else => try context.writeOp(Op.Code.ASTORE, this.index),
            }
        },
        .integer => |n| {
            const i = n.data;
            const abs = std.math.sign(i) * i;
            if (abs <= std.math.maxInt(i8)) {
                try context.writeOp(Op.Code.BIPUSH, n.data);
            } else if (abs <= std.math.maxInt(i16)) {
                try context.writeOp(Op.Code.SIPUSH, n.data);
            } else {
                const h = try context.cpool.add_integer(n.data);
                try context.pushConstant(h);
            }
            try context.stack.push(.int);
        },
        .namespace => |n| {
            const name = try n.fullName(context.allocator);
            const local = context.getLocal(name);
            if (local) |l| {
                try context.loadLocal(l);
            } else {
                std.debug.print("Unknown variable '{s}'.\n", .{ name });
                return error.UnknownVariable;
            }
        },
        .@"return" => |n| {
            if (n == null) {
                try context.writeOp(Op.Code.RETURN, 0);
                return;
            }
            try createCode0(context, n.?.*);
            switch (context.stack.peek() orelse return error.NothingToReturn) {
                .int => try context.writeOp(Op.Code.IRETURN, 0),
                .float => try context.writeOp(Op.Code.FRETURN, 0),
                else => try context.writeOp(Op.Code.ARETURN, 0),
            }
        },
        .fn_invoke => |n| {
            // if ns[0] is local, do field access until method and invoke
            // otherwise ns[0] is a class ref, then same as above
            const full = n.namespace.namespace.data;
            // assert full is at least len 1 from the parser.
            const name = full[full.len - 1];
            const prior = full[1..full.len];

            if (n.builtin) return try createBuiltin(context, name, n.args);

            if (prior.len == 0) return error.UnexpectedFunction;

            const local = context.getLocal(prior[0]) orelse return error.UnexpectedFunction;
            try context.loadLocal(local);
            for (prior[1..]) |field| {
                try createFieldAccess(context, field, undefined);
            }
        },
        else => {
            std.debug.print("Unhandled node {any}\n", .{ node });
            return error.UnhandledNode;
        }
    }
}

fn createBuiltin(context: *CodeContext, name: []const u8, args: []Node) !void {
    if (std.mem.eql(u8, name, "import")) {
        const class = args[0].string.data;
        const class_h = try context.cpool.add_class(class);
        try context.pushConstant(class_h);
        var split = std.mem.splitScalar(u8, class, ':');
        const mode = split.next() orelse "undefined";
        var import: Type = undefined;
        if (std.mem.eql(u8, mode, "jvm")) {
            import = try read.readClass(context.allocator, split.rest());
        } else {
            import = Type.lookup().?;
        }
        try context.imported.put(class_h, import);
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
                .char => |c| try context.writeOp(code, c.data),
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