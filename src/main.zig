const std = @import("std");
const Nerve = @import("Nerve");

///
/// CLI entry point.
///
pub fn main() !void {
    const string = "Hello, World!";
    std.debug.print("The type of string '{s}' is '{s}'", .{ string, @typeName(@TypeOf(string)) });
    std.debug.print("Starting program.\n", .{});
    const source =
        \\const var System = [import]("test/java/lang/System.class")
        \\const var String = [import]("test/java/lang/String.class")
        \\pub static const var main = fn(args: []String)->void {
        \\  System.out.println("hellomayasworld");
        \\  return;
        \\}
        ;
    try Nerve.compile(source);
}