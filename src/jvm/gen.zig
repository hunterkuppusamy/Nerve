const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Op = format.Op;
const root = @import("root");
const Type = @import("../type.zig").Type;
const Node = @import("../AST.zig").Node;
const Stack = @import("util").Stack;
const Tokenizer = @import("../tokenizer.zig").Tokenizer;
const Parser = @import("../parser.zig").Parser;
const ConstantPool = @import("../ConstantPool.zig");
const bytecode = @import("bytecode.zig");
const read = @import("read.zig");
const util = @import("util");

const selectVariableName = struct {
    fn invoke(v: CodegenContext.Variable) []const u8 {
        return v.name;
    }
}.invoke;

const strCompare = struct {
    fn invoke(s1: []const u8, s2: []const u8) bool {
        return std.mem.eql(u8, s1, s2);
    }
}.invoke;

pub const CodegenContext = struct {
    allocator: std.mem.Allocator,
    imported: std.StringHashMap(Type),
    class: *Class,
    cpool: *ConstantPool,
    static: StaticContext,
    function: FunctionContext,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator) !Self {
        const class = try gpa.create(Class);
        const cpool = try gpa.create(ConstantPool);
        class.* = Class{};
        cpool.* = try ConstantPool.init(gpa);

        const self = Self {
            .allocator = gpa,
            .imported = std.StringHashMap(Type).init(gpa),
            .cpool = cpool,
            .class = class,
            .static = .{
                .decls = try std.ArrayList(Variable).initCapacity(gpa, 16),
            },
            .function = try FunctionContext.init(gpa),
        };

        return self;
    }

    fn prepImports(self: *Self) void {
        inline for (@typeInfo(Type).@"union".fields) |f| {
            if (std.mem.eql(u8, f.name, "int")) {
                self.imported.put(f.name, Type.int);
            } else if (std.mem.eql(u8, f.name, "float")) {
                self.imported.put(f.name, Type.float);
            } else if (std.mem.eql(u8, f.name, "long")) {
                self.imported.put(f.name, Type.long);
            } else if (std.mem.eql(u8, f.name, "double")) {
                self.imported.put(f.name, Type.double);
            } else if (std.mem.eql(u8, f.name, "void")) {
                self.imported.put(f.name, Type.void);
            }
        }
        // Add my std
    }

    /// Returns either a pointer to the existing type from the class's name,
    /// or a pointer to the new type created which is owned by context.imported.
    pub fn getImport(self: *Self, path: []const u8) ?*Type {
        return self.imported.getPtr(path);
    }

    pub fn importPath(self: *Self, path: []const u8) !*Type {
        const class = try read.readClassFile(self.allocator, path);
        return self.importClass(&class);
    }

    pub fn importClass(self: *Self, class: *const Class) !*Type {
        const gpa = self.allocator;
        const path = class.constant_pool[class.this_class - 1].utf_8_info.bytes;

        var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 16);
        try self.imported.put(path, Type {
            .@"struct" = .{
                .name = try gpa.dupe(u8, path),
                .fields = undefined,
            }
        });

        for (class.fields) |f| {
            const fname = class.constant_pool[f.name_index - 1].utf_8_info.bytes;
            const field_type_ptr = self.imported.getPtr(class.constant_pool[f.descriptor_index - 1].utf_8_info.bytes).?;
            try fields.append(gpa, .{
                .access = f.access_flags,
                .name = try gpa.dupe(u8, fname),
                .type = field_type_ptr,
            });
        }

        for (class.methods) |m| {
            const fname = class.constant_pool[m.name_index - 1].utf_8_info.bytes;
            const method_desc_ptr = self.imported.getPtr(class.constant_pool[m.descriptor_index - 1].utf_8_info.bytes).?;
            var access = Class.FieldAccessFlags{};
            access.public = m.access_flags.public;
            access.static = m.access_flags.static;
            access.private = m.access_flags.public;
            access.protected = m.access_flags.protected;
            access.final = m.access_flags.final;

            try fields.append(gpa, .{
                .access = access,
                .name = try gpa.dupe(u8, fname),
                .type = method_desc_ptr,
            });
        }

        // Found existing should always be false atp.
        const ptr = (try self.imported.getOrPut(path)).value_ptr;

        ptr.* = Type {
            .@"struct" = .{
                .name = path,
                .fields = try fields.toOwnedSlice(gpa),
            }
        };

        return ptr;
    }

    pub fn inferType(self: *Self, node: *const Node) !*const Type {
        const gpa = self.allocator;
        switch (node.*) {
            .@"var" => |n| {
                if (n.type) |ret| return try inferType(self, ret);
            },
            .integer => return &@as(Type, Type.int),
            .float => return &@as(Type, Type.float),
            .type_decl => |n| {
                const name: []const u8 = undefined;

                var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 8);

                for (n.fields) |f| {
                    const decl = f.@"var";
                    const mods = decl.mods;
                    var flags = Class.FieldAccessFlags{};
                    flags.public = mods.public;
                    flags.private = !mods.public;
                    flags.final = mods.constant;
                    try fields.append(gpa, .{
                        .access = .{},
                        .name = decl.name,
                        .type = if (decl.type) |explicit| try self.inferType(explicit) else try self.inferType(decl.value),
                    });
                }

                const ptr = try gpa.create(Type);
                ptr.* = Type {
                    .@"struct" = .{ .name = name, .fields = try fields.toOwnedSlice(gpa) }
                };
                return ptr;
            },
            .fn_decl => |n| {
                var nodes: []const Node = undefined;
                if (n.body.* == Node.body) { nodes = n.body.body.nodes; } else {
                    const var_nodes = try gpa.alloc(Node, 1);
                    var_nodes[0] = n.body.*;
                    nodes = var_nodes;
                }
                var params = try std.ArrayList(Type.Fn.Param).initCapacity(gpa, 2);
                for (n.params) |p| {
                    const type_ptr = try inferType(self, p.type);
                    try params.append(gpa, Type.Fn.Param {
                        .name = p.name,
                        .type = type_ptr
                    });
                }
                const rtype = try inferType(self, n.return_type);
                const ptr = try gpa.create(Type);
                ptr.* = Type {
                    .@"fn" = .{
                        .body = try gpa.dupe(Node, nodes),
                        .params = try params.toOwnedSlice(gpa),
                        .return_type = rtype,
                    }
                };
                return ptr;
            },
            .fn_invoke => |n| {
                if (n.builtin) {
                    const name = n.name;
                    if (std.mem.eql(u8, name, "import")) {
                        const path = n.args[0].string.data;
                        return self.getImport(path) orelse try self.importPath(path);
                    } else if (std.mem.eql(u8, name, "asm")) {
                        return switch (self.function.op_stack.peek() orelse return &@as(Type, Type.void)) {
                            .int => &@as(Type, Type.int),
                            .float => &@as(Type, Type.float),
                            else => error.CannotInferType,
                        };
                    }
                    std.debug.print("Unknown builtin '{s}'.\n", .{ name });
                    return error.CannotInferType;
                }
                const instance = n.instance;
                if (instance) |this| {
                    const this_type = (try inferType(self, this)).@"struct";
                    for (this_type.fields) |f| {
                        if (std.mem.eql(u8, f.name, n.name)) return f.type.@"fn".return_type;
                    }
                    std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
                    return error.CannotInferType;
                } else {
                    const local = self.function.getLocal(n.name);
                    if (local) |l| return l.type;
                    return self.static.getField(n.name).?.type;
                }
            },
            .field_access => |n| {
                const instance = n.instance;
                if (instance) |this| {
                    const this_type = (try inferType(self, this)).@"struct";
                    for (this_type.fields) |f| {
                        if (std.mem.eql(u8, f.name, n.name)) return f.type;
                    }
                    std.debug.print("Could not find field '{s}' in type '{s}'.\n", .{ n.name, this_type.name });
                    return error.CannotInferType;
                } else if (self.function.getLocal(n.name)) |l| {
                    return l.type;
                } else if (self.static.getField(n.name)) |d| {
                    return d.type;
                } else {
                    std.debug.print("Could not find local or static field '{s}'.\n", .{ n.name });
                    return error.CannotInferType;
                }
            },
            else => {}
        }
        std.debug.print("Cannot infer type of {any}.\n", .{ node });
        return error.CannotInferType;
    }

    pub const StaticContext = struct {
        decls: std.ArrayList(Variable),

        pub fn getField(self: *@This(), name: []const u8) ?Variable {
            return util.findEql(Variable, []const u8, selectVariableName, strCompare, self.decls.items, name);
        }
    };

    pub const FunctionContext = struct {
        bytecode: std.Io.Writer.Allocating,
        locals: std.ArrayList(Variable),
        op_stack: Stack(Primitive),

        pub fn init(gpa: std.mem.Allocator) !FunctionContext {
            return .{
                .locals = try std.ArrayList(Variable).initCapacity(gpa, 16),
                .op_stack = try Stack(Primitive).init(gpa),
                .bytecode = std.Io.Writer.Allocating.init(gpa)
            };
        }

        fn getContext(self: *FunctionContext) *CodegenContext {
            return @fieldParentPtr("function", self);
        }

        pub fn toOwnedCode(self: *FunctionContext) !Class.Attribute {
            const context = self.getContext();
            const byte_code = try self.bytecode.toOwnedSlice();
            std.debug.print("Created bytecode\n", .{});
            try bytecode.print(byte_code, self.getContext().class);
            const code = Class.Attribute.Code {
                .code = byte_code,
                .max_locals = @intCast(self.locals.items.len),
                .max_stack = @intCast(self.op_stack.list.items.len),
                .exception_table = &[0]Class.Attribute.Code.Exception{},
                .attributes = &[0]Class.Attribute{},
            };
            const name_h = try context.cpool.add_utf8("Code");
            const attr_len = 12 + code.code.len + (code.exception_table.len * 8);
            std.debug.print("toOwnedCode: CodeAttr code len = {any}.\n", .{ code.code.len });
            return .{
                .attribute_name_index = @intCast(name_h),
                .attribute_length = @intCast(attr_len),
                .info = .{ .code = code },
            };
        }

        pub fn getOrCreateLocal(self: *FunctionContext, name: []const u8, typ: *const Type) !Variable {
            var l: ?Variable = self.getLocal(name);
            if (l) |ret| return ret;
            const idx: u16 = @intCast(self.locals.items.len);
            l = Variable {
                .index = idx,
                .name = name,
                .type = typ,
            };
            try self.locals.insert(self.getContext().allocator, idx, l.?);
            return l.?;
        }

        pub fn loadLocal(self: *FunctionContext, local: Variable) !void {
            try switch (local.type.*) {
                .int => self.writeOp(Op.Code.ILOAD, local.index),
                .float => self.writeOp(Op.Code.FLOAD, local.index),
                else => self.writeOp(Op.Code.ALOAD, local.index),
            };
        }

        pub fn getLocal(self: *FunctionContext, name: []const u8) ?Variable {
            return util.findEql(Variable, []const u8, selectVariableName, strCompare, self.locals.items, name);
        }

        pub fn writeOp(self: *FunctionContext, code: Op.Code, operand: anytype) !void {
            std.debug.print("writeOp: writing op '{s}' {any}.\n", .{ @tagName(code), operand });
            const inf = Op.meta(code)  orelse return error.NoOpCodeMeta;
            // Write opcode
            //try self.buffer.append(self.allocator, @intFromEnum(code));
            try self.bytecode.writer.writeInt(u8, @intFromEnum(code), .big);
            // Write params.
            switch (inf.operand_form) {
                .none => {},
                .U8, .I8, .local, .U8_constant, => try self.bytecode.writer.writeInt(u8,  @intCast(operand), .big),
                .U16, .U16_constant =>        try self.bytecode.writer.writeInt(u16, @intCast(operand), .big),
                .I16, .branch_offset =>   try self.bytecode.writer.writeInt(i16, @intCast(operand), .big), // branch offsets stored as bi-endian signed 16
                .offset_w =>        try self.bytecode.writer.writeInt(u32, @intCast(operand), .big),
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

        pub fn pushConstant(self: *FunctionContext, h: usize) !void {
            const context = self.getContext();
            const c = context.class.constant_pool[h - 1];
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

        pub fn create(self: *Self, body: []const Node) !void {
            std.debug.print("createCode: Creating code for {any} nodes.\n", .{ body.len });
            for (body) |node| {
                try bytecode.createCode0(self, node);
            }
        }
    };

    pub const Primitive = enum {
        int,         float,       long,       double,
        int_array,   float_array, long_array, double_array,
        object,      class_ref,   method_ref, field_ref,
        object_array,
    };

    pub const Variable = struct {
        index: u16,
        name: []const u8,
        type: *const Type,
    };
};

/// Create jvm from a type
pub fn generate(
    context: *CodegenContext,
    /// 'objective' type
    struct_type: *const Type.Struct,
) !void {
    const gpa = context.allocator;

    const class_constant = try context.cpool.add_class(struct_type.name);
    const super_class_constant = try context.cpool.add_class("java/lang/Object");
    context.class.this_class = @intCast(class_constant);
    context.class.super_class = @intCast(super_class_constant);

    var methods_len: usize = 0;
    var fields_len: usize = 0;

    for (struct_type.fields) |field| if (field.type.* == Type.@"fn") {
        methods_len += 1;
    } else {
        fields_len += 1;
    };

    var methods_index: usize = 0;
    var fields_index: usize = 0;

    context.class.fields = try gpa.alloc(Class.FieldInfo, fields_len);
    context.class.methods = try gpa.alloc(Class.MethodInfo, methods_len);

    for (struct_type.fields) |field| {
        std.debug.print("generate: Generating field {s}.\n", .{ field.name });
        const name_h = try context.cpool.add_utf8(field.name);
        switch (field.type.*) {
            .@"fn" => |fun| {
                const return_type_name = try fun.return_type.jvmName(gpa);
                const param_names = try gpa.alloc([]const u8, fun.params.len);
                for (fun.params, 0..) |p, i| {
                    const param_type_name = try p.type.jvmName(gpa);
                    param_names[i] = try gpa.dupe(u8, param_type_name);
                }
                const desc = try assembleMethodDesc(gpa, param_names, return_type_name);
                const desc_index = try context.cpool.add_utf8(desc);

                context.function.bytecode.deinit();
                context.function.locals.deinit(gpa);
                context.function.op_stack.deinit();
                context.function = try CodegenContext.FunctionContext.init(gpa);

                try bytecode.writeOpsFromNodes(context, fun.body);

                var flags = Class.MethodAccessFlags{};
                flags.public = field.access.public;
                flags.static = field.access.static;
                flags.private = field.access.public;
                flags.protected = field.access.protected;
                flags.final = field.access.final;

                const code = try context.function.toOwnedCode();
                const attributes= try gpa.alloc(Class.Attribute, 1);
                attributes[0] = code;

                context.class.methods[methods_index] = .{
                    .name_index = @intCast(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = flags,
                    .attributes = attributes,
                };
                methods_index += 1;
            },
            else => {
                const desc_index = try context.cpool.add_utf8(try field.type.jvmName(gpa));
                const attributes = &[0]Class.Attribute{};

                context.class.fields[fields_index] = .{
                    .name_index = @truncate(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = field.access,
                    .attributes = attributes,
                };
                fields_index += 1;
            }
        }
    }

    try context.cpool.populate(context.class);
}

pub fn assembleMethodDesc(gpa: std.mem.Allocator, params: [][]const u8, return_name: []const u8) ![]const u8 {
    var desc_len: usize = 2; // both parenthesis at either side is two chars no matter what.
    desc_len += return_name.len;
    for (params) |param| desc_len += param.len;
    const descriptor = try gpa.alloc(u8, desc_len);
    descriptor[0] = '(';
    var i: usize = 1; // start after first paren.
    for (params) |param| {
        @memcpy(descriptor[i..(i + param.len)], param);
        i += param.len;
    }
    descriptor[i] = ')';
    i += 1;
    @memcpy(descriptor[i..], return_name);
    return descriptor;
}