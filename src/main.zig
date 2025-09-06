const std = @import("std");
const Nerve = @import("Nerve");

///
/// CLI entry point.
///
pub fn main() !void {
    const string = "Hello, World!";
    std.debug.print("The type of string '{s}' is '{s}'", .{ string, @typeName(@TypeOf(string)) });
    std.debug.print("Starting program.\n", .{});
    try Nerve.compile(
        \\pub fn hello() {
        \\  var death = 0;
        \\  return "done";
        \\}
    );
}