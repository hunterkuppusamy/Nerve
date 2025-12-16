const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Stack(comptime T: type) type {
    return StackManaged(T);
}

pub fn StackManaged(comptime T: type) type {
    return struct {
        list: std.ArrayList(T),
        allocator: Allocator,

        const Self = @This();

        pub fn init(gpa: Allocator) Allocator.Error!Self {
            return .{ .list = try std.ArrayList(T).initCapacity(gpa, 16), .allocator = gpa, };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit(self.allocator);
        }

        pub fn push(self: *Self, element: T) Allocator.Error!void {
            try self.list.append(self.allocator, element);
        }

        pub fn pop(self: *Self) ?T {
            return self.list.pop();
        }

        pub fn peek(self: *Self) ?T {
            if (self.list.items.len <= 0) return null;
            return self.list.items[self.list.items.len - 1];
        }
    };
}