const std = @import("std");

pub fn findEql(
    comptime E: type,
    comptime T: type,
    comptime select: fn (E) T,
    comptime eql: fn (T, T) bool,
    haystack: []E,
    value: T,
) ?E {
    for (haystack) |e| {
        if (eql(select(e), value)) return e;
    }
    return null;
}