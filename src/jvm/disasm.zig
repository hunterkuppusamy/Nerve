const std = @import("std");
const ConstantPool = @import("../ConstantPool.zig");
const format = @import("format.zig");
const Op = format.Op;

pub fn print(bytecode: []const u8, cpool: ?*ConstantPool) !void {
    var fixedReader = std.Io.Reader.fixed(bytecode);
    const r = &fixedReader;
    while (r.seek < r.end) {
        const op_byte = try r.takeByte();
        var code: ?Op.Code = null;
        inline for (@typeInfo(Op.Code).@"enum".fields) |op| {
            if (op.value == op_byte) code = @enumFromInt(op.value);
        }
        if (code == null) {
            std.debug.print("Unknown op code {}.\n", .{op_byte});
            return error.UnknownOpCode;
        }
        printOp(r, cpool, code.?) catch |e| {
            std.debug.print("\nError while printing op {?}.\n", .{code});
            return e;
        };
    }
}

fn printOp(r: *std.Io.Reader, cpool: ?*ConstantPool, op: Op.Code) !void {
    const meta = Op.meta(op) orelse return error.UndefinedMeta;
    std.debug.print(" | {s}", .{meta.mnemonic});
    switch (meta.operand_form) {
        .none => std.debug.print("\n", .{}),
        .I8 => std.debug.print(", {any}\n", .{try r.takeInt(i8, .big)}),
        .U8, .local => std.debug.print(", {any}\n", .{try r.takeInt(u8, .big)}),
        .U16 => std.debug.print(", {any}\n", .{try r.takeInt(u16, .big)}),
        .I16 => std.debug.print(", {any}\n", .{try r.takeInt(i16, .big)}),
        .U8_constant => try printConstant(u8, r, cpool),
        .U16_constant => try printConstant(u16, r, cpool),
        .branch_offset => std.debug.print(", {any}\n", .{try r.takeInt(i16, .big)}),
        else => {
            std.debug.print("\nUnhandled operand form '{s}'.\n", .{@tagName(meta.operand_form)});
            return error.Unhandled;
        },
    }
}

fn printConstant(comptime width: type, r: *std.Io.Reader, maybe_pool: ?*ConstantPool) !void {
    const indx = try r.takeInt(width, .big);
    std.debug.print(", {any}", .{indx});
    if (maybe_pool) |pool| {
        const cp = pool.constant_list.items;
        std.debug.print(" ({s} ", .{@tagName(cp[indx - 1])});
        switch (cp[indx - 1]) {
            .utf_8_info => |c| std.debug.print("'{s}'", .{c.bytes}),
            .class_info => |c| std.debug.print("{s}", .{cp[c.name_index - 1].utf_8_info.bytes}),
            .integer_info => |c| std.debug.print("{d}", .{std.math.cast(i32, c.bytes).?}),
            .name_and_type_info => |c| std.debug.print("{s} {s}", .{
                cp[c.name_index - 1].utf_8_info.bytes,
                cp[c.descriptor_index - 1].utf_8_info.bytes,
            }),
            else => |c| std.debug.print("{any}", .{c}),
        }
        std.debug.print(")\n", .{});
    } else std.debug.print("\n", .{});
}
