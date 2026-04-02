const std = @import("std");
const format = @import("format.zig");
const Class = format.Class;
const Op = format.Op;
const Type = @import("../type.zig").Type;
const Node = @import("../AST.zig").Node;
const Stack = @import("util").Stack;
const ConstantPool = @import("../ConstantPool.zig");
const disasm = @import("disasm.zig");
const import = @import("import.zig");
const infer = @import("infer.zig");

pub const Primitive = enum {
    int, float, long, double,
    int_array, float_array, long_array, double_array,
    object, class_ref, method_ref, field_ref,
    object_array,
};

pub const Variable = struct {
    index: u16,
    name: []const u8,
    type: *const Type,
};

fn findVariable(items: []const Variable, name: []const u8) ?Variable {
    for (items) |v| {
        if (std.mem.eql(u8, v.name, name)) return v;
    }
    return null;
}

// ── GlobalContext ────────────────────────────────────────────────────────
// Shared across all compilation units within a single compiler invocation.
// Owns the import cache and JDK classpath.
pub const GlobalContext = struct {
    allocator: std.mem.Allocator,
    jdk_path: []const u8,
    imported: std.StringHashMap(*Type),

    pub fn init(gpa: std.mem.Allocator, jdk_path: []const u8) !GlobalContext {
        var self = GlobalContext{
            .allocator = gpa,
            .jdk_path = jdk_path,
            .imported = std.StringHashMap(*Type).init(gpa),
        };
        try import.prepImports(&self);
        return self;
    }

    pub fn getImport(self: *GlobalContext, path: []const u8) ?*Type {
        return self.imported.get(path);
    }

    pub fn importClassName(self: *GlobalContext, class_name: []const u8) import.ImportError!*Type {
        return import.importClassName(self, class_name);
    }
};

// ── FileContext ──────────────────────────────────────────────────────────
// One per source file / compilation unit. Holds file-level declarations
// (imports, type aliases, static fields) that are visible to all classes
// defined in the file.
pub const FileContext = struct {
    global: *GlobalContext,
    statics: StaticScope,

    pub fn init(global: *GlobalContext) !FileContext {
        var self = FileContext{
            .global = global,
            .statics = try StaticScope.init(global.allocator),
        };
        try self.registerPrimitives();
        return self;
    }

    fn registerPrimitives(self: *FileContext) !void {
        try self.putStatic("int", &@as(Type, Type.int));
        try self.putStatic("float", &@as(Type, Type.float));
        try self.putStatic("long", &@as(Type, Type.long));
        try self.putStatic("double", &@as(Type, Type.double));
        try self.putStatic("void", &@as(Type, Type.void));
    }

    pub fn putStatic(self: *FileContext, name: []const u8, t: *const Type) !void {
        try self.statics.put(self.global.allocator, name, t);
    }

    pub fn getStatic(self: *FileContext, name: []const u8) ?Variable {
        return self.statics.get(name);
    }
};

// ── ClassContext ─────────────────────────────────────────────────────────
// One per class being generated. Owns the JVM Class structure, constant
// pool, and class-level metadata. Multiple ClassContexts can exist within
// a single FileContext (inner classes, multiple top-level classes).
pub const ClassContext = struct {
    file: *FileContext,
    class: *Class,
    cpool: *ConstantPool,
    name: []const u8,

    pub fn init(file: *FileContext, name: []const u8) !ClassContext {
        const gpa = file.global.allocator;
        const class = try gpa.create(Class);
        const cpool = try gpa.create(ConstantPool);
        class.* = Class{};
        cpool.* = try ConstantPool.init(gpa);
        return .{
            .file = file,
            .class = class,
            .cpool = cpool,
            .name = name,
        };
    }

    pub fn allocator(self: *ClassContext) std.mem.Allocator {
        return self.file.global.allocator;
    }
};

// ── FunctionContext ──────────────────────────────────────────────────────
// One per method body being compiled. Owns the bytecode writer, local
// variable table, and operand stack state. Created fresh for each method.
pub const FunctionContext = struct {
    class: *ClassContext,
    bytecode: std.Io.Writer.Allocating,
    locals: std.ArrayList(Variable),
    op_stack: Stack(Primitive),

    pub fn init(class: *ClassContext) !FunctionContext {
        const gpa = class.allocator();
        return .{
            .class = class,
            .locals = try std.ArrayList(Variable).initCapacity(gpa, 16),
            .op_stack = try Stack(Primitive).init(gpa),
            .bytecode = std.Io.Writer.Allocating.init(gpa),
        };
    }

    pub fn deinit(self: *FunctionContext) void {
        const gpa = self.class.allocator();
        self.bytecode.deinit();
        self.locals.deinit(gpa);
        self.op_stack.deinit();
    }

    pub fn toOwnedCode(self: *FunctionContext) !Class.Attribute {
        const cpool = self.class.cpool;
        const byte_code = try self.bytecode.toOwnedSlice();
        std.debug.print("Created bytecode\n", .{});
        try disasm.print(byte_code, cpool);
        std.debug.print("Locals = {}.\n", .{self.locals});
        std.debug.print("Stack = {}.\n", .{self.op_stack.list});
        const code = Class.Attribute.Code{
            .code = byte_code,
            .max_locals = @intCast(self.locals.items.len),
            .max_stack = @intCast(self.op_stack.max_reached),
            .exception_table = &.{},
            .attributes = &.{},
        };
        const name_h = try cpool.add_utf8("Code");
        const attr_len = 12 + code.code.len + (code.exception_table.len * 8);
        std.debug.print("toOwnedCode: CodeAttr code len = {any}.\n", .{code.code.len});
        return .{
            .attribute_name_index = @intCast(name_h),
            .attribute_length = @intCast(attr_len),
            .info = .{ .code = code },
        };
    }

    pub fn getOrCreateLocal(self: *FunctionContext, name: []const u8, typ: *const Type) !Variable {
        if (self.getLocal(name)) |ret| return ret;
        const idx: u16 = @intCast(self.locals.items.len);
        const l = Variable{ .index = idx, .name = name, .type = typ };
        try self.locals.insert(self.class.allocator(), idx, l);
        return l;
    }

    pub fn loadLocal(self: *FunctionContext, local: Variable) !void {
        try switch (local.type.*) {
            .int => self.writeOp(Op.Code.ILOAD, local.index),
            .float => self.writeOp(Op.Code.FLOAD, local.index),
            else => self.writeOp(Op.Code.ALOAD, local.index),
        };
    }

    pub fn getLocal(self: *FunctionContext, name: []const u8) ?Variable {
        return findVariable(self.locals.items, name);
    }

    pub fn writeOp(self: *FunctionContext, code: Op.Code, operand: anytype) !void {
        std.debug.print("writeOp: writing op '{s}' {any}.\n", .{ @tagName(code), operand });
        const inf = Op.meta(code) orelse return error.NoOpCodeMeta;
        try self.bytecode.writer.writeInt(u8, @intFromEnum(code), .big);
        switch (inf.operand_form) {
            .none => {},
            .U8, .I8, .local, .U8_constant => try self.bytecode.writer.writeInt(u8, @intCast(operand), .big),
            .U16, .U16_constant => try self.bytecode.writer.writeInt(u16, @intCast(operand), .big),
            .I16, .branch_offset => try self.bytecode.writer.writeInt(i16, @intCast(operand), .big),
            .offset_w => try self.bytecode.writer.writeInt(u32, @intCast(operand), .big),
            .contextual => @panic("cannot emit variable-length opcode generically"),
            .local_index_const => {},
        }
    }

    pub fn pushConstant(self: *FunctionContext, h: usize) !void {
        const c = self.class.cpool.constant_list.items[h - 1];
        switch (c) {
            .long_info, .double_info => {
                try self.writeOp(Op.Code.LDC2_W, h);
                return;
            },
            else => {},
        }
        if (h <= std.math.maxInt(u8)) {
            try self.writeOp(Op.Code.LDC, h);
        } else {
            try self.writeOp(Op.Code.LDC_W, h);
        }
        try self.op_stack.push(.object);
    }

    // Convenience: reach through to parent contexts
    pub fn inferType(self: *FunctionContext, node: *const Node) infer.InferError!*const Type {
        return infer.inferType(self, node);
    }
};

// ── StaticScope ─────────────────────────────────────────────────────────
// Reusable name→Variable table for file-level or class-level declarations.
pub const StaticScope = struct {
    decls: std.ArrayList(Variable),

    pub fn init(gpa: std.mem.Allocator) !StaticScope {
        return .{
            .decls = try std.ArrayList(Variable).initCapacity(gpa, 16),
        };
    }

    pub fn put(self: *StaticScope, gpa: std.mem.Allocator, name: []const u8, t: *const Type) !void {
        try self.decls.append(gpa, .{
            .index = @intCast(self.decls.items.len),
            .name = name,
            .type = t,
        });
    }

    pub fn get(self: *StaticScope, name: []const u8) ?Variable {
        return findVariable(self.decls.items, name);
    }
};
