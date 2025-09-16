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
        \\// Comment!
        \\pub fn start(y: int32)-> int32 {
        \\  var const a = 1 / y;
        \\  fn h(x: int32) -> int32 = x + 1;
        \\  var b = h(a);
        \\
        \\  if (b < 1) {
        \\      return y;
        \\  } elif(b < 3) {
        \\      return a;
        \\  } else {
        \\      return h(b) * 2;
        \\  }
        \\}
        \\
        \\fn new() -> none = 1;
    );
}