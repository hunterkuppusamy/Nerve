const std = @import("std");
const Class = @import("jvm/class.zig").Class;

const ConstantPool = @This();

allocator: std.mem.Allocator,

/// To populate before populating the Class instance.
constant_list: std.ArrayList(Class.Constant),

// HashMaps to dedupe; keys refer to *handles* (usize).
utf8_map: std.StringHashMap(usize),
/// UTF index to Class index
class_map: std.AutoHashMap(usize, usize),
///
name_and_type_map: std.AutoHashMap(u128, usize),
method_ref_map: std.AutoHashMap(u64, usize),
field_ref_map: std.AutoHashMap(u64, usize),
string_map: std.AutoHashMap(usize, usize),
integer_map: std.AutoHashMap(i32, usize),
long_map: std.AutoHashMap(i64, usize),
float_map: std.AutoHashMap(u32, usize),
double_map: std.AutoHashMap(u64, usize),

pub fn init(gpa: std.mem.Allocator) !ConstantPool {
    const cp = ConstantPool {
        .allocator = gpa,
        .constant_list = try std.ArrayList(Class.Constant).initCapacity(gpa, 32),
        .utf8_map = std.StringHashMap(usize).init(gpa),
        .class_map = std.AutoHashMap(usize, usize).init(gpa),
        .name_and_type_map = std.AutoHashMap(u128, usize).init(gpa),
        .method_ref_map = std.AutoHashMap(u64, usize).init(gpa),
        .field_ref_map = std.AutoHashMap(u64, usize).init(gpa),
        .string_map = std.AutoHashMap(usize, usize).init(gpa),
        .integer_map = std.AutoHashMap(i32, usize).init(gpa),
        .long_map = std.AutoHashMap(i64, usize).init(gpa),
        .float_map = std.AutoHashMap(u32, usize).init(gpa),
        .double_map = std.AutoHashMap(u64, usize).init(gpa),
    };
    return cp;
}

pub fn deinit(self: *ConstantPool) void {
    _ = self.utf8_map.deinit();
    _ = self.class_map.deinit();
    _ = self.name_and_type_map.deinit();
    _ = self.method_ref_map.deinit();
    _ = self.field_ref_map.deinit();
    _ = self.string_map.deinit();
    _ = self.integer_map.deinit();
    _ = self.float_map.deinit();
    _ = self.long_map.deinit();
    _ = self.double_map.deinit();
    _ = self.constant_list.constant_pool.deinit();
}

/// internal helper: append a constant and mark wide-ness.
fn appendConst(self: *ConstantPool, c: Class.Constant) !usize {
    const idx = self.constant_list.items.len;
    if (c == Class.Constant.utf_8_info) {
        std.log.debug("Adding const #{} '{s}'", .{idx, c.utf_8_info.bytes});
    } else std.log.debug("Adding const #{} {any}", .{idx, c});
    try self.constant_list.append(self.allocator, c);
    switch (c) {
        .long_info, .double_info => try self.constant_list.append(self.allocator, .placeholder),
        else => {}
    }
    return idx + 1;
}

pub fn add_utf8(self: *ConstantPool, bytes: []const u8) !usize {
    if (self.utf8_map.get(bytes)) |h| return h;
    const c = Class.Constant{ .utf_8_info = .{
        .bytes = bytes,
    }};
    const idx = try self.appendConst(c);
    try self.utf8_map.put(bytes, idx);
    return idx;
}

pub fn add_class(self: *ConstantPool, internal_name: []const u8) !usize {
    const name_h = try self.add_utf8(internal_name);
    if (self.class_map.get(name_h)) |h| return h;
    const c = Class.Constant{ .class_info = .{
        .name_index = @intCast(name_h)
    } };
    const idx = try self.appendConst(c);
    try self.class_map.put(name_h, idx);
    return idx;
}

pub fn add_name_and_type(self: *ConstantPool, name: []const u8, descriptor: []const u8) !usize {
    const name_h = try self.add_utf8(name);
    const desc_h = try self.add_utf8(descriptor);
    const key: u128 = (@as(u128, @intCast(name_h)) << 64) | @as(u128, @intCast(desc_h));
    if (self.name_and_type_map.get(key)) |h| return h;
    const c = Class.Constant{ .name_and_type_info = .{
        .name_index = @intCast(name_h),
        .descriptor_index = @intCast(desc_h),
    }};
    const idx = try self.appendConst(c);
    try self.name_and_type_map.put(key, idx);
    return idx;
}

pub fn add_method_ref(self: *ConstantPool, class: []const u8, name: []const u8, descriptor: []const u8) !usize {
    const class_h = try self.add_class(class);
    const nat_h = try self.add_name_and_type(name, descriptor);
    const key: u64 = @intCast(class_h << 32 | nat_h);
    if (self.method_ref_map.get(key)) |h| return h;
    const c = Class.Constant{ .method_ref_info = .{
        .class_index = @intCast(class_h),
        .name_and_type_index = @intCast(nat_h),
    }};
    const idx = try self.appendConst(c);
    try self.method_ref_map.put(key, idx);
    return idx;
}

pub fn add_field_ref(self: *ConstantPool, class: []const u8, name: []const u8, descriptor: []const u8) !usize {
    const class_h = try self.add_class(class);
    const nat_h = try self.add_name_and_type(name, descriptor);
    const key: u64 = @intCast(class_h << 32 | nat_h);
    if (self.field_ref_map.get(key)) |h| return h;
    const c = Class.Constant{ .field_ref_info = .{
        .class_index = @intCast(class_h),
        .name_and_type_index = @intCast(nat_h),
    }};
    const idx = try self.appendConst(c);
    try self.field_ref_map.put(key, idx);
    return idx;
}

pub fn add_string(self: *ConstantPool, s: []const u8) !usize {
    const utf_h = try self.add_utf8(s);
    if (self.string_map.get(utf_h)) |h| return h;
    const c = Class.Constant{ .string_info = .{
        .string_index = @intCast(utf_h),
    }};
    const idx = try self.appendConst(c);
    try self.string_map.put(utf_h, idx);
    return idx;
}

pub fn add_integer(self: *ConstantPool, bytes: i32) !usize {
    if (self.integer_map.get(bytes)) |h| return h;
    const c = Class.Constant{ .integer_info = .{
        .bytes = @bitCast(bytes),
    }};
    const idx = try self.appendConst(c);
    try self.integer_map.put(bytes, idx);
    return idx;
}

pub fn add_float(self: *ConstantPool, float: f32) !usize {
    const bytes: u32 = @bitCast(float);
    if (self.float_map.get(bytes)) |h| return h;
    const c = Class.Constant{ .float_info = .{
        .bytes = bytes,
    }};
    const idx = try self.appendConst(c);
    try self.float_map.put(bytes, idx);
    return idx;
}

pub fn add_long(self: *ConstantPool, long: u64) !usize {
    if (self.long_map.get(long)) |h| return h;
    const c = Class.Constant{ .long_info = .{
        .high_bytes = @intCast(long << 32),
        .low_bytes = @intCast(long),
    }};
    const idx = try self.appendConst(c);
    try self.long_map.put(long, idx);
    return idx;
}

pub fn add_double(self: *ConstantPool, double: f64) !usize {
    const bytes: u64 = @bitCast(double);
    if (self.double_map.get(bytes)) |h| return h;
    const c = Class.Constant{ .double_info = .{
        .high_bytes = @intCast(bytes << 32),
        .low_bytes = @truncate(bytes),
    }};
    const idx = try self.appendConst(c);
    try self.double_map.put(bytes, idx);
    return idx;
}

pub fn populate(self: *ConstantPool, class: *Class) !void {
    const cp_count = self.constant_list.items.len + 1;
    if (cp_count > 0xFFFF) @panic("constant_pool_count > 65535");
    const owned = try self.constant_list.toOwnedSlice(self.allocator);
    defer self.constant_list.deinit(self.allocator);
    class.constant_pool = owned;
}

const expect = std.testing.expect;

test "Constant Pool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    var classfile = Class{};
    var pool = try ConstantPool.init(alloc);
    _ = try pool.add_double(1.0);
    _ = try pool.add_float(2.0);
    _ = try pool.add_string("Hello");
    const this = try pool.add_class("zig/Fun");
    const super = try pool.add_class("java/lang/Object");
    classfile.super_class = @truncate(super);
    classfile.this_class = @truncate(this);
    const to_string_method = try pool.add_method_ref("java/lang/Object", "toString", "();Ljava/lang/String");
    std.debug.print("Object#ToString() index = {any}\n", .{ to_string_method });
    try expect(to_string_method == 13);
}