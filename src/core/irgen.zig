// ir_parser.zig
const std = @import("std");
const Ast = @import("ast.zig").Node; // adjust path as needed
const Ir = @import("ir.zig").Node;
const op = @import("util").op;
const Stack = @import("util").Stack;
const SourceSpan = @import("SourceSpan.zig");

pub const IrElevator = struct {
    allocator: std.mem.Allocator,
    compile_time_stack: Stack(Ir.TypeRef),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) IrElevator {
        return IrElevator{ .allocator = allocator };
    }

    pub fn lowerType(self: *Self, name: []const u8, type_decl: *const Ast.TypeDecl) !Ir.TypeDef {
        var list = try std.ArrayList(Ir).initCapacity(self.allocator, 2);
        defer list.deinit();

        for (type_decl.fields) |field| {
            const ir = try self.lowerVarDecl(field);
            try list.append(ir);
        }

        return .{
            .fields = try list.toOwnedSlice(),
            .name = name,
            .source = type_decl.source,
        };
    }

    fn lowerVarDecl(self: *Self, var_decl: Ast.VarDecl) !Ir {
        const block = try self.allocator.create(Ir.Code);
        switch (var_decl.value.*) {
            .type_decl => |t| {
                return Ir { .type_def = try self.lowerType(var_decl.name, &t) };
            },
            .fn_decl => |f| {
                return Ir { .function_def =  try self.parseFnDecl(f) };
            },
            .fn_invoke => |i| {
                block.* = Ir { .block = try self.exprToCode(i) };
            },
            .string, .integer, .float, .bool, .byte => |_| {
                const code = try self.exprToCode(var_decl.value);
                block.* = Ir { .block = code };
            },
            else => return error.Unhandled,
        }
        return Ir.FieldDef {
            .flags = .{
                .constant = var_decl.mods.constant,
                .public = var_decl.mods.public,
                .static = var_decl.mods.static,
            },
            .type = .{
            },
            .value = block
        };
    }

/// convert a function declaration AST node into Ir.FunctionDef
    fn parseFnDecl(self: *IrElevator, name: []const u8, a: Ast.FnDecl) !Ir.FunctionDef {
        var params = std.ArrayList(Ir.FunctionDef.Param).init(self.allocator);
        for (a.params) |p| {
            // create placeholder StaticCode for param type (to be resolved later)
            const type_code = try self.createEmptyStaticCode(p.type.loc);
            try params.append(Ir.FunctionDef.Param{
                .name = p.name,
                .type = type_code,
                .source = p.loc,
            });
        }
        const params_slice = try params.toOwnedSlice();

        // return type placeholder (value)
        const ret_code: []Ir.StaticCode = &.{};

        // body: if body is `body` node produce code, else null (shouldn't be)
        var body_code: ?*Ir.Code = null;
        if (a.body.* == Ast.body) {
            body_code = try self.nodesToCode(a.body.body.nodes, a.body.body.source);
        }

        return Ir.FunctionDef{
            .name = name, // depends on AST organization (adjust accordingly)
            .params = params_slice,
            .ret = ret_code,
            .body = body_code.?,
            .source = a.source,
        };
    }

    fn varDeclToFieldDef(self: *IrElevator, v: Ast.VarDecl) !Ir.FieldDef {
        var type_code: ?*Ir.StaticCode = null;
        if (v.type) |t| {
            type_code = try self.allocator.create(Ir.StaticCode);
            type_code.?.* = try self.createEmptyStaticCode(t.loc);
        }
        var value_code: ?*Ir.Code = null;
        if (v.value) |val| {
            value_code = try self.allocator.create(Ir.Code);
            value_code.?.* = try self.exprToCode(val);
        }
        return Ir.FieldDef{
            .name = v.name,
            .type = type_code,
            .flags = Ir.FieldDef.Flags{
                .public = v.mods.public,
                .constant = v.mods.constant,
                .static = (v.scope != Ast.VarDecl.Scope.local),
            },
            .initializer = value_code,
            .source = v.source,
        };
    }

/// Convert a Body's nodes into a Code (sequence of stack-style instructions)
    fn nodesToCode(self: *IrElevator, nodes: []const Ast, src: SourceSpan) !Ir.Code {
        var code_list = try std.ArrayList(Ir.Instruction).initCapacity(self.allocator, 2);

        for (nodes) |node| {
            try self.emitNodeAsInstructions(node, &code_list);
        }

        const code = try code_list.toOwnedSlice();
        return Ir.Code{
            .instructions = code,
            .source = src,
        };
    }

    fn createEmptyCode(self: *IrElevator, src: SourceSpan) !Ir.Code {
        _ = self;
        return Ir.Code{ .instructions = &.{}, .source = src };
    }

    fn createEmptyStaticCode(self: *IrElevator, src: SourceSpan) !Ir.StaticCode {
        const c = try self.createEmptyCode(src);
        return c; // StaticCode is an alias of Code by value
    }

    /// Convert an expression node into a single Code block (useful for top-level exprs)
    fn exprToCode(self: *IrElevator, expr: *const Ast) !Ir.Code {
        var list = try std.ArrayList(Ir.Instruction).initCapacity(self.allocator, 2);
        try self.emitNodeAsInstructions(expr, &list);
        const slice = try list.toOwnedSlice();
        return Ir.Code{ .instructions = slice, .source = expr.source() };
    }

    /// Emit instructions for a single AST node into the provided instruction list.
    fn emitNodeAsInstructions(self: *IrElevator, node: *const Ast, out: std.ArrayList(Ir.Instruction)) !void {
        switch (node.*) {
            .integer => |i| {
                const p = try self.allocator.create(Ir.Instruction.PushInt);
                p.* = Ir.Instruction.PushInt{ .value = i.data, .source = i.source };
                try out.append(Ir.Instruction{ .push_int = p });
            },
            .float => |f| {
                const p = try self.allocator.create(Ir.Instruction.PushFloat);
                p.* = Ir.Instruction.PushFloat{ .value = @intFromFloat(f.data), .source = f.source };
                try out.append(Ir.Instruction{ .push_float = p });
            },
            .bool => |b| {
                const p = try self.allocator.create(Ir.Instruction.PushBool);
                p.* = Ir.Instruction.PushBool { .value = b.data, .source = b.source };
                try out.append(Ir.Instruction{ .push_bool = p });
            },
            .string => |s| {
                const p = try self.allocator.create(Ir.Instruction.PushString);
                p.* = Ir.Instruction.PushString { .value = s.data, .source = s.source };
                try out.append(Ir.Instruction{ .push_string = p });
            },
            .binary_op => |b| {
                try self.emitNodeAsInstructions(b.lhs, out);
                try self.emitNodeAsInstructions(b.rhs, out);
                const bo = try self.allocator.create(Ir.Instruction.BinaryOp);
                bo.* = Ir.Instruction.BinaryOp{ .op = b.op, .source = b.source };
                try out.append(Ir.Instruction{ .binary_op = bo });
            },
            .field_access => |f| {
                const is_static = f.instance == null;
                if (is_static) {
                    const ll = try self.allocator.create(Ir.Instruction.LoadLocal);
                    ll.* = Ir.Instruction.LoadLocal { .name = f.name, .source = f.source };
                    try out.append(Ir.Instruction { .load_local = ll });
                    return;
                }

                try self.emitNodeAsInstructions(f.instance.?, out);

                const lf = try self.allocator.create(Ir.Instruction.LoadField);
                lf.* = Ir.Instruction.LoadField { .name = f.name, .source = f.source };
                try out.append(Ir.Instruction{ .load_field = lf });
            },
            .fn_invoke => |call| {
                for (call.args) |arg| {
                    try self.emitNodeAsInstructions(&arg, out);
                }
                const c = try self.allocator.create(Ir.Instruction.Invoke);
                c.* = Ir.Instruction.Invoke {
                    .name = call.name,
                    .arg_len = @intCast(call.args.len),
                    .source = call.source
                };
                try out.append(Ir.Instruction{ .invoke = c });
            },
            .var_decl => |v| {
                try self.emitNodeAsInstructions(v.value, out);
                const s = try self.allocator.create(Ir.Instruction.StoreLocal);
                s.* = Ir.Instruction.StoreLocal{ .name = v.name, .source = v.source };
                try out.append(Ir.Instruction{ .store_local = s });
            },
            .@"return" => |r| {
                const ret = try self.allocator.create(Ir.Instruction.Return);
                if (r) |val| {
                    try self.emitNodeAsInstructions(val, out);
                    ret.* = Ir.Instruction.Return{ .valued = true, .source = node.source() };
                    try out.append(Ir.Instruction{ .ret = ret });
                } else {
                    ret.* = Ir.Instruction.Return{ .valued = false, .source = node.source() };
                    try out.append(Ir.Instruction{ .ret = ret });
                }
            },
            .body => |b| {
                for (b.nodes) |sub| {
                    try self.emitNodeAsInstructions(&sub, out);
                }
            },
            .@"if" => |i| {
                try self.emitNodeAsInstructions(i.condition, out);
                const n = try self.allocator.create(Ir.Instruction.Nop);
                n.* = Ir.Instruction.Nop{ .source = i.source };
                try out.append(Ir.Instruction{ .nop = n });

                try self.emitNodeAsInstructions(i.branch_true, out);
                if (i.branch_false) |bf| {
                    const n2 = try self.allocator.create(Ir.Instruction.Nop);
                    n2.* = Ir.Instruction.Nop{ .source = i.source };
                    try out.append(Ir.Instruction{ .nop = n2 });
                    try self.emitNodeAsInstructions(bf, out);
                }
            },

            else => |_| {

            },
        }
    }
};