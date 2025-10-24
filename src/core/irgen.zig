const std = @import("std");
const Ast = @import("ast.zig").Node;
const Ir = @import("ir.zig").Node;
const util = @import("util");
const term = util.terminal;
const Stack = util.Stack;

const log = std.log.scoped(.irgen);

pub const IRContext = struct {
    allocator: std.mem.Allocator,
    scopes: Stack(Scope),

    const Self = @This();

    pub const Scope = struct {
        locals: std.ArrayList(Var),
        statics: std.ArrayList(Var),
        pub const Var = struct {
            name: []const u8,
            type: *Ast,
        };
    };

    /// Gets the local, if not static, variable named [name], ordered by distance from declaration.
    pub fn varNamed(self: *Self, name: []const u8) ?Scope.Var {
        const len = self.scopes.list.items.len;
        if (len < 1) return null;
        var i = len - 1;
        while (i >= 0) {
            const scope = self.scopes.list.items[i];
            // Find local by the name, if not find the static, if not then try the outer scope.
            const variable = util.findEql(
                Scope.Var, []const u8, selectVariableName, strCompare, scope.locals.items, name
            ) orelse util.findEql(
                Scope.Var, []const u8, selectVariableName, strCompare, scope.statics.items, name
            );
            return variable orelse {
                i -= 1;
                continue;
            };
        }
        return null;
    }

    pub fn enterScope(self: *Self) !void {
        try self.scopes.push(.{
            .locals = try std.ArrayList(Scope.Var).initCapacity(self.allocator, 0),
            .statics = try std.ArrayList(Scope.Var).initCapacity(self.allocator, 0),
        });
    }

    pub fn leaveScope(self: *Self) void {
        self.scopes.pop();
    }

    pub fn putVar(self: *Self, region: enum { local, static }, named: []const u8, value: *Ast) !void {
        const scope = self.scopes.peek() orelse return term.logErr(error.NoCurrentScope, "Not currently in any scope.", .{});
        switch (region) {
            .local => try scope.locals.append(self.allocator, .{ .name = named, .type = value}),
            .static => try scope.statics.append(self.allocator, .{ .name = named, .type = value}),
        }
    }

    pub fn init(gpa: std.mem.Allocator) Self {
        return .{ .allocator = gpa, };
    }

    pub fn generate(self: *Self, file_name: []const u8, asts: []Ast) !Ir.Declare {
        const fake_type_ast = Ast {
            .type_decl = .{ .fields = asts, .loc = .{
                .line = asts[0].lineinfo().line,
                .src_start_ndx = asts[0].lineinfo().src_start_ndx,
                .src_end_ndx = asts[asts.len - 1].lineinfo().src_end_ndx,
            } }
        };
        return self.declare(file_name, &fake_type_ast);
    }

    fn declare(self: *Self, name: []const u8, ast: *const Ast) !Ir.Declare {
        switch (ast.*) {
            .type_decl => |n| {
                const declares = try std.ArrayList(Ir.Declare).initCapacity(self.allocator, 8);
                return Ir.Declare {
                    .line = n.loc,
                    .name = name,
                    .thing = .{ .type = .{
                        .line = n.loc,
                        .decls = declares.toOwnedSlice(self.allocator),
                    } }
                };
            },
            .fn_decl => |n| {
                const body = try std.ArrayList(Ir).initCapacity(self.allocator, 8);
                for (n.body) |body_ast| {
                    try body.append(self.allocator, try self.statement(body_ast));
                }
                return Ir.Declare {
                    .line = n.loc,
                    .name = name,
                    .thing = .{
                        .fun = .{
                            .line = n.loc,
                            .body = try body.toOwnedSlice(self.allocator),
                        }
                    }
                };
            },
            .var_decl => |n| return self.declare(n.name, n.value),
            else => return term.logErr(error.UnexpectedNode, "Node '{s}' is not handled here.", .{ @tagName(ast) }),
        }
        return term.logErr(error.UnexpectedDeclaration, "Unexpected declaration, node '{s}'", .{ @tagName(ast.*) });
    }

    fn statement(self: *Self, ast: *const Ast) !Ir {

    }
};

const selectVariableName = struct {
    fn invoke(v: IRContext.Scope.Var) []const u8 {
        return v.name;
    }
}.invoke;

const strCompare = struct {
    fn invoke(s1: []const u8, s2: []const u8) bool {
        return std.mem.eql(u8, s1, s2);
    }
}.invoke;