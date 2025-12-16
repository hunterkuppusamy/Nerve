const std = @import("std");
const format = @import("class.zig");
const log = std.log.scoped(.typegen);
const Class = format.Class;
const Op = format.Op;
const root = @import("root");
const Type = @import("../type.zig").Type;
const Node = @import("../core/ast.zig").Node;
const Stack = @import("util").Stack;
const Tokenizer = @import("../core/tokengen.zig").Tokenizer;
const Parser = @import("../core/astgen.zig").Parser;
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
    jdk_path: []const u8,
    imported: std.StringHashMap(Type),
    class: *Class,
    cpool: *ConstantPool,
    static: StaticContext,
    function: FunctionContext,

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, jdk_path: []const u8) !Self {
        const class = try gpa.create(Class);
        const cpool = try gpa.create(ConstantPool);
        class.* = Class{};
        cpool.* = try ConstantPool.init(gpa);

        var self = Self {
            .allocator = gpa,
            .jdk_path = jdk_path,
            .imported = std.StringHashMap(Type).init(gpa),
            .cpool = cpool,
            .class = class,
            .static = .{
                .funs = try std.ArrayList(StaticContext.FnDef).initCapacity(gpa, 8),
                .vars = try std.ArrayList(Variable).initCapacity(gpa, 16),
            },
            .function = try FunctionContext.init(gpa),
        };

        try self.prepImports();

        return self;
    }

    fn prepImports(self: *Self) !void {
        inline for (@typeInfo(Type).@"union".fields) |f| {
            if (std.mem.eql(u8, f.name, "int")) {
                try self.static.putStatic(f.name, &@as(Type, Type.int));
            } else if (std.mem.eql(u8, f.name, "float")) {
                try self.static.putStatic(f.name, &@as(Type, Type.float));
            } else if (std.mem.eql(u8, f.name, "long")) {
                try self.static.putStatic(f.name, &@as(Type, Type.long));
            } else if (std.mem.eql(u8, f.name, "double")) {
                try self.static.putStatic(f.name, &@as(Type, Type.double));
            } else if (std.mem.eql(u8, f.name, "void")) {
                try self.static.putStatic(f.name, &@as(Type, Type.void));
            }
        }
        // Add my std
    }

    /// Returns either a pointer to the existing type from the class's name, or null
    pub fn getImport(self: *Self, qualified_name: []const u8) ?*Type {
        return self.imported.getPtr(qualified_name);
    }

    const ImportError = std.fs.File.OpenError || std.mem.Allocator.Error || std.Io.Reader.Error || error {
        WrongMagic,
        UnknownConstantTag,
        AlreadyImported,
        IllegalConstantPool,
    };

    /// Imports a .class file at the specified path.
    pub fn importPath(self: *Self, path: []const u8) ImportError!*Type {
        const class = try read.readClassFile(self.allocator, path);
        return self.importClass(&class);
    }

    /// Creates a type from a jvm type descriptor.
    fn importDescriptor(self: *Self, descriptor: []const u8) ImportError!Type {
        const gpa = self.allocator;
        if (descriptor.len == 0) return ImportError.Unexpected;
        var ret: Type = undefined;
        if (std.mem.eql(u8, descriptor, "I")) {
            ret = @as(Type, Type.int);
        } else if (std.mem.eql(u8, descriptor, "F")) {
            ret = @as(Type, Type.float);
        } else if (std.mem.eql(u8, descriptor, "J")) {
            ret = @as(Type, Type.long);
        } else if (std.mem.eql(u8, descriptor, "D")) {
            ret = @as(Type, Type.double);
        } else if (std.mem.eql(u8, descriptor, "V")) {
            ret = @as(Type, Type.void);
        } else if (std.mem.eql(u8, descriptor, "B")) {
            // BYTE
            ret = @as(Type, Type.int);
        } else if (std.mem.eql(u8, descriptor, "Z")) {
            // BOOLEAN
            ret = @as(Type, Type.int);
        } else if (std.mem.eql(u8, descriptor, "S")) {
            // SHORT
            ret = @as(Type, Type.int);
        } else if (std.mem.eql(u8, descriptor, "C")) {
            // CHAR
            ret = @as(Type, Type.int);
        } else if (std.mem.startsWith(u8, descriptor, "[")) {
            const element_type = self.importDescriptor(descriptor[1..]) catch |e| {
                switch (e) {
                    ImportError.Unexpected => log.err("Error while importing descriptor '{s}'.", .{ descriptor[1..] }),
                    else => {}
                }
                return e;
            };

            const e_ptr = try gpa.create(Type);
            e_ptr.* = element_type;
            ret = .{
                .array = .{
                    .elements = e_ptr,
                }
            };
        } else if (std.mem.startsWith(u8, descriptor, "L")) {
            const class_name = descriptor[1..descriptor.len - 1];
            const file_path = try std.mem.concat(gpa, u8, &.{
                self.jdk_path, "/", class_name, ".class"
            });
            // If already imported yank it, otherwise import the class.
            //std.debug.print("Checking class import of '{s}'.\n", .{ class_name });
            var found = self.getImport(class_name);
            if (found) |f| {
                ret = f.*;
                gpa.destroy(f);
            } else {
                log.debug("Importing class at path '{s}'.", .{ file_path });
                found = (try self.importPath(file_path));
                ret = found.?.*;
                try self.imported.put(class_name, ret);
                gpa.destroy(found.?);
            }
        } else {
            log.err("Cannot import {s}: invalid descriptor.", .{ descriptor });
            return ImportError.Unexpected;
        }
        return ret;
    }

    fn nextDesc(descriptor: []const u8) ?[]const u8 {
        switch (descriptor[0]) {
            'I', 'F', 'J', 'D', 'V', 'B', 'C', 'S', 'Z' => {
                return descriptor[0..1];
            },
            '[' => {
                const element = nextDesc(descriptor[1..]).?;
                return descriptor[0..element.len + 1];
            },
            'L' => {
                var len: usize = 0;
                for (descriptor) |c| {
                    if (c == ';') {
                        //std.debug.print("Nextdesc = {s}.\n", .{ descriptor[0..len + 1] });
                        return descriptor[0..len + 1];
                    } else len += 1;
                }
            },
            else => {
                std.debug.print("Got {s}\n", .{ descriptor });
                unreachable;
            },
        }
        unreachable;
    }

    fn parseMethodDesc(self: *Self, descriptor: []const u8) !struct {
        ret: Type,
        params: []Type
    } {
        //std.debug.print("Parsing method desc {s}.\n", .{ descriptor });
        var i: usize = 1; // opening paren
        var params = try std.ArrayList(Type).initCapacity(self.allocator, 4);
        var ret: Type = undefined;
        while (i < descriptor.len) {
            const char = descriptor[i];
            if (char == ')') {
                // Has to be a return type.
                const ret_name = nextDesc(descriptor[(i + 1)..]).?;
                const entry = try self.imported.getOrPut(ret_name);
                if (!entry.found_existing) {
                    //std.debug.print("Importing method return type {s}\n", .{ ret_name });
                    ret = try self.importDescriptor(ret_name);
                    entry.value_ptr.* = ret;
                }
                else ret = entry.value_ptr.*;

                break;
            }
            const param_desc = nextDesc(descriptor[i..]) orelse break;
            i += param_desc.len;
            var param_type: Type = undefined;
            const entry = try self.imported.getOrPut(param_desc);
            if (!entry.found_existing) entry.value_ptr.* = param_type;
            //std.debug.print("Importing method param type {s}\n", .{ param_desc });
            param_type = try self.importDescriptor(param_desc);
            try params.append(self.allocator, param_type);
        }
        return .{
            .ret = ret,
            .params = try params.toOwnedSlice(self.allocator),
        };
    }

    /// Imports a class to the native Type.
    pub fn importClass(self: *Self, class: *const Class) ImportError!*Type {
        const gpa = self.allocator;
        const name = class.constant_pool[class.constant_pool[class.this_class - 1].class_info.name_index - 1].utf_8_info.bytes;
        //std.debug.print("Importing class '{s}'\n", .{ name });

        var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 16);
        const entry = try self.imported.getOrPut(name);
        if (entry.found_existing) return entry.value_ptr;

        for (class.fields) |f| {
            const fname = class.constant_pool[f.name_index - 1].utf_8_info.bytes;
            const descriptor = class.constant_pool[f.descriptor_index - 1].utf_8_info.bytes;
            //std.debug.print("Importing field type {s}\n", .{ descriptor });
            const field_type = try self.importDescriptor(descriptor);
            const field_type_ptr = try gpa.create(Type);
            field_type_ptr.* = field_type;
            try fields.append(gpa, .{
                .access = f.access_flags,
                .name = try gpa.dupe(u8, fname),
                .type = field_type_ptr,
            });
        }

        for (class.methods) |m| {
            const fname = class.constant_pool[m.name_index - 1].utf_8_info.bytes;
            const descriptor = class.constant_pool[m.descriptor_index - 1].utf_8_info.bytes;
            const method_desc = try self.parseMethodDesc(descriptor);

            var params = [_]Type.Fn.Param{ undefined } ** 32;
            var param_i: u8 = 0;
            for (method_desc.params) |p| {
                const p_ptr = try gpa.create(Type);
                p_ptr.* = p;
                params[param_i] = Type.Fn.Param {
                    .name = try std.fmt.allocPrint(gpa, "_{}", .{ param_i }),
                    .type = p_ptr,
                };
                param_i += 1;
            }

            const fn_type = try gpa.create(Type);
            const ret_type_ptr = try gpa.create(Type);
            ret_type_ptr.* = method_desc.ret;
            fn_type.* = .{
                .@"fn" = .{
                    .return_type = ret_type_ptr,
                    .params = try gpa.dupe(Type.Fn.Param, params[0..param_i]),
                }
            };
            var access = Class.FieldAccessFlags{};
            access.public = m.access_flags.public;
            access.static = m.access_flags.static;
            access.private = m.access_flags.public;
            access.protected = m.access_flags.protected;
            access.final = m.access_flags.final;

            try fields.append(gpa, .{
                .access = access,
                .name = try gpa.dupe(u8, fname),
                .type = fn_type,
            });
        }

        const ptr = entry.value_ptr;

        ptr.* = Type {
            .@"struct" = .{
                .name = name,
                .fields = try fields.toOwnedSlice(gpa),
            }
        };

        if (self.imported.get(name) == null) unreachable;

        return ptr;
    }

    pub fn resolveType(self: *Self, node: *const Node) !*const Type {
        const gpa = self.allocator;
        log.debug("Current allocation size {}.", .{ @as(*std.heap.ArenaAllocator, @alignCast(@ptrCast(gpa.ptr))).queryCapacity() });
        switch (node.*) {
            .integer => return &@as(Type, Type.int),
            .float => return &@as(Type, Type.float),
            .string => {
                const str_type = self.getImport("java/lang/String") orelse {
                    return error.NotImported;
                };
                switch (str_type.*) {
                    .@"struct" => {},
                    else => {
                        log.err("String type was not a struct.", .{});
                        return error.Unexpected;
                    }
                }
                return str_type;
            },
            .var_decl => |v| {
                log.debug("Declaring variable {s}.", .{ v.name });
                const var_type = if (v.type) |ret|
                    try resolveType(self, ret)
                    else try self.declare(v);
                return var_type;
            },
            .fn_invoke => |n| {
                if (n.builtin) {
                    const name = n.name;
                    if (std.mem.eql(u8, name, "import")) {
                        const path = n.args[0].string.data;
                        return self.getImport(path) orelse r: {
                            log.debug("Import builtin called for '{s}'.", .{ path });
                            break :r try self.importPath(path);
                        };
                    } else if (std.mem.eql(u8, name, "asm")) {
                        return switch (self.function.op_stack.peek() orelse return &@as(Type, Type.void)) {
                            .int => &@as(Type, Type.int),
                            .float => &@as(Type, Type.float),
                            else => error.CannotInferType,
                        };
                    }
                    log.err("Unknown builtin '{s}'.", .{ name });
                    return error.CannotInferType;
                }
                const instance = n.instance;
                if (instance) |this| {
                    const this_type = (try resolveType(self, this)).@"struct";
                    for (this_type.fields) |f| {
                        if (std.mem.eql(u8, f.name, n.name)) return f.type.@"fn".return_type;
                    }
                    log.debug("Could not find field '{s}' in type '{s}'.", .{ n.name, this_type.name });
                    return error.CannotInferType;
                } else {
                    return util.terminal.logErr(error.CannotInferType, "Local functions not supported.", .{});
                }
            },
            .field_access => |n| {
                if (n.instance) |this| {
                    const this_type = (try resolveType(self, this)).@"struct";
                    for (this_type.fields) |f| {
                        if (std.mem.eql(u8, f.name, n.name)) return f.type;
                    }
                    log.debug("Could not find field '{s}' in type '{s}'.", .{ n.name, this_type.name });
                    return error.CannotInferType;
                } else if (self.function.getLocal(n.name)) |l| {
                    return l.type;
                } else if (self.static.getStatic(n.name)) |d| {
                    return d.type;
                } else {
                    std.debug.print("Could not find local or static field '{s}'.\n", .{ n.name });
                    return error.CannotInferType;
                }
            },
            .array_of => |n| {
                const arr = try gpa.create(Type);
                const elem = try self.resolveType(n.element_type);
                arr.* = Type {
                    .array = .{
                        .elements = elem,
                    }
                };
                return arr;
            },
            else => {}
        }
        log.err("Cannot infer type of {any}.", .{ node });
        return error.CannotInferType;
    }

    pub fn declare(self: *Self, var_node: Node.VarDecl) anyerror!*const Type {
        const gpa = self.allocator;
        switch (var_node.value.*) {
            .type_decl => |decl| {
                var fields = try std.ArrayList(Type.Struct.Field).initCapacity(gpa, 8);

                for (decl.fields) |f| {
                    const field_decl = f.var_decl;
                    const mods = field_decl.mods;
                    var flags = Class.FieldAccessFlags{};
                    flags.public = mods.public;
                    flags.final = mods.constant;
                    flags.static = mods.static;
                    const type_ptr = if (field_decl.type) |explicit|
                        try self.resolveType(explicit) else try self.resolveType(field_decl.value);

                    log.debug("Adding static {s} to context.", .{ field_decl.name });
                    try self.static.putStatic(field_decl.name, type_ptr);
                    try fields.append(gpa, .{
                        .access = flags,
                        .name = field_decl.name,
                        .type = type_ptr,
                    });
                }

                const ptr = try gpa.create(Type);
                ptr.* = Type {
                    .@"struct" = .{
                        .name = var_node.name,
                        .fields = try fields.toOwnedSlice(gpa)
                    }
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
                    const type_ptr = try resolveType(self, p.type);
                    try params.append(gpa, Type.Fn.Param {
                        .name = p.name,
                        .type = type_ptr
                    });
                }
                const rtype = try resolveType(self, n.return_type);
                const ptr = try gpa.create(Type);
                ptr.* = Type {
                    .@"fn" = .{
                        .params = try params.toOwnedSlice(gpa),
                        .return_type = rtype,
                    }
                };
                var body = try std.ArrayList(Node).initCapacity(gpa, 1);
                switch (n.body.*) {
                    .body => |b| {
                        try body.appendSlice(gpa, b.nodes);
                    },
                    else => |b| try body.append(gpa, b),
                }
                try self.static.funs.append(gpa, .{
                    .type = ptr,
                    .name = var_node.name,
                    .body = try body.toOwnedSlice(gpa),
                });
                return ptr;
            },
            else => return util.terminal.logErr(error.CannotDeclare, "Cannot declare node '{s}'.", .{ @tagName(var_node.value.*) }),
        }
    }

    pub const StaticContext = struct {
        vars: std.ArrayList(Variable),
        funs: std.ArrayList(FnDef),

        pub const FnDef = struct {
            name: []const u8,
            type: *const Type,
            body: []Node,
        };

        fn getContext(self: *StaticContext) *CodegenContext {
            return @fieldParentPtr("static", self);
        }

        pub fn putStatic(self: *StaticContext, name: []const u8, t: *const Type) !void {
            try self.vars.append(self.getContext().allocator, .{
                .index = @intCast(self.vars.items.len),
                .name = name,
                .type = t,
            });
        }

        pub fn getStatic(self: *StaticContext, name: []const u8) ?Variable {
            return util.findEql(Variable, []const u8, selectVariableName, strCompare, self.vars.items, name);
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
            log.debug("Created bytecode", .{});
            //try bytecode.print(byte_code, context.cpool);
            log.debug("Locals = {}.", .{ self.locals });
            log.debug("Stack = {}.", .{ self.op_stack.list });
            const code = Class.Attribute.Code {
                .code = byte_code,
                .max_locals = @intCast(self.locals.items.len),
                .max_stack = @intCast(self.op_stack.list.items.len),
                .exception_table = &.{},
                .attributes = &.{},
            };
            const name_h = try context.cpool.add_utf8("Code");
            const attr_len = 12 + code.code.len + (code.exception_table.len * 8);
            log.debug("toOwnedCode: CodeAttr code len = {any}.", .{ code.code.len });
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
            log.debug("writeOp: writing op '{s}' {any}.", .{ @tagName(code), operand });
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
            const c = context.cpool.constant_list.items[h - 1];
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
            try self.op_stack.push(.object);
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
        log.debug("generate: Generating field {s}.", .{ field.name });
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

                for (fun.params, 0..) |p, i| {
                    try context.function.locals.append(gpa, .{
                        .index = @intCast(i),
                        .name = p.name,
                        .type = p.type,
                    });
                }

                if (!field.access.static) {
                    const this_ptr = try gpa.create(Type);
                    this_ptr.* = Type {
                        .@"struct" = struct_type.*,
                    };
                    try context.function.locals.append(gpa, .{
                        .index = @intCast(context.function.locals.items.len),
                        .name = "this",
                        .type = this_ptr,
                    });
                }

                try bytecode.bytecodeOf(context, unreachable);

                var flags = Class.MethodAccessFlags{};
                flags.public = field.access.public;
                flags.private = field.access.private;
                flags.protected = field.access.protected;
                flags.static = field.access.static;
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
                context.class.fields[fields_index] = .{
                    .name_index = @truncate(name_h),
                    .descriptor_index = @intCast(desc_index),
                    .access_flags = field.access,
                    .attributes = &.{},
                };
                fields_index += 1;
            }
        }
    }

    context.class.attributes = &.{};
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