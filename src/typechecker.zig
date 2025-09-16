const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const Token = lexer.Token;

const Code = struct {
    _constant_pool: ConstantPool = .{},
    _type_pool: Pool(Type)
};

pub const TypeChecker = struct {
    _context: Code = .{},
};

pub fn Pool(comptime T: type) type {
    return struct {
        _list: std.ArrayList(T),
        _allocator: std.heap.ArenaAllocator,

        pub fn init(alloc: std.mem.Allocator) !Pool(T) {
            var arena = std.heap.ArenaAllocator.init(alloc);
            return .{
                ._list = try std.ArrayList(T).initCapacity(arena.allocator(), 16),
                ._allocator = arena,
            };
        }

        pub fn deinit(self: *@This()) void {
            self._list.deinit(self._allocator.allocator());
            self._allocator.deinit();
        }

        pub fn append(self: *@This(), value: T) !void {
            try self._list.append(self._allocator.allocator(), value);
        }
    };
}

pub const ConstantPool = struct {
    _allocator: std.mem.Allocator = undefined,
    _list: std.ArrayList(Constant) = undefined,

    pub fn appendString(self: *@This(), string: []const u8) !void {
        const owned_here = try self._allocator.alloc(u8, string.len);
        @memcpy(owned_here, string);
        try self._list.append(self._allocator, .{
            .string = owned_here,
        });
    }

    pub fn append(self: *@This(), comptime T: type, value: T) !void {
        comptime switch (@typeInfo(T)) {
            .int, .float => {},
            else => @compileError("Unhandled type.")
        };

        const owned_here = try self._allocator.create(T);
        owned_here.* = value;
        const c: Constant = c: switch (@typeInfo(T)) {
            .int => |i| {
                break :c if (i.bits <= 32) .{
                    .integer = std.math.cast(i32, value)
                } else .{
                    .long = std.math.cast(i64, value)
                };
            },
            .float => |f| {
                break :c if (f.bits <= 32) .{
                    .float = std.math.cast(f32, value)
                } else .{
                    .double = std.math.cast(f64, value)
                };
            }
        };
        self._list.append(self._allocator, c);
    }

    pub fn init(self: *@This(), alloc: std.mem.Allocator) !void {
        self._list = try std.ArrayList(Constant).initCapacity(alloc, 16);
        self._allocator = alloc;
    }

    pub fn deinit(self: *@This()) void {
        self._list.deinit(self._allocator);
    }

    const Constant = union(enum) {
        string: []const u8,
        integer: i32,
        float: f32,
        long: i64,
        double: f64,
    };
};

const TypePoolIndex = u32;
const FunctionPoolIndex = u32;
const ConstantPoolIndex = u32;

test "Type checking" {
    _ = Body{ .statements = &[0]Statement{} };
    var t = Type {
        .name = 0,
        .functions = try Pool(FunctionDeclaration).init(std.testing.allocator),
    };
    try t.functions.append(.{
        .name = 1,
        .parameters = &[0]Parameter{},
        .body = &[0]Statement{},
    });
    defer t.functions.deinit();
}

pub const Type = struct {
    name: ConstantPoolIndex,
    functions: Pool(FunctionDeclaration),
};

pub const Statement = union(enum) {
    @"if": IfStatement
};

pub const IfStatement = struct {
    condition: Expression,
    @"true": Body,
    @"false": union(enum) {
        @"else": Body,
        elseif: *IfStatement
    },
};

pub const Body = struct {
    statements: []const Statement,
};

pub const FunctionDeclaration = struct {
    name: ConstantPoolIndex,
    parameters: []const Parameter,
    body: []const Statement,
};

pub const FunctionInvocation = struct {
    owning_type: TypePoolIndex,
    function: FunctionPoolIndex,
    arguments: []const Expression
};

pub const Parameter = struct {
    name: ConstantPoolIndex,
    @"type": TypePoolIndex,
};

pub const Expression = union(enum) {
    value: Value,
    binary_op: BinaryOp,
};

pub const Value = union {
    constant: ConstantPoolIndex,
    variable: struct {
        name: ConstantPoolIndex,
        @"type": TypePoolIndex,
    }
};

pub const BinaryOp = struct {
    lhs: *Expression,
    op: parser.BinaryOperation,
    rhs: *Expression,
};

pub const Flags = packed struct {
    public: bool,
    constant: bool
};