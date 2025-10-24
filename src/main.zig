const std = @import("std");
const Nerve = @import("Nerve");
const util = @import("util");
const terminal = util.terminal;
const logErr = terminal.logErr;

const log = std.log.scoped(.main);

const Option = union(enum) {
    value: []const u8,
    present,
};

pub const panic: type = std.debug.FullPanic(
    struct { pub fn panic(
        msg: []const u8,
        first_trace_addr: ?usize,
    ) noreturn {
        log.err("Compiler panic. This is exceptional behavior.", .{});
        log.err("Panic: {s}", .{ msg });
        std.debug.dumpCurrentStackTrace(first_trace_addr orelse @returnAddress());
        std.process.exit(1);
    }}.panic,
);

pub const std_options = std.Options {
    .logFn = terminal.std_log_fn
};

///
/// General rule of thumb for errors users may see:
/// - `OOM` / `AllocError` doesn't need special handling; just `try`.
/// - `FileNotFound` should be detail of what data could not be found.
/// - Anything else; be descriptive.
///
///
/// CLI entry point.
///
pub fn main() !void {
    // EST: during fall, -4, else -5
    terminal.utc_offset = -4;
    log.info("Starting core.", .{});
    log.warn("v0 - expect bugs.", .{});

    const gpa = std.heap.page_allocator;
    // cross platform args
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    var arg_map = std.StringHashMap(Option).init(gpa);
    defer arg_map.deinit();

    while (args.next()) |arg| {
        log.debug("ARGUMENT {s}", .{ arg });
        if (std.mem.startsWith(u8, arg, "--")) {
            if (!std.mem.containsAtLeastScalar(u8, arg, 1, '='))
                return logErr(error.InvalidOption, "Option passed but there is no value ('{s}').", .{ arg });
            var pair = std.mem.splitScalar(u8, arg, '=');
            const key = pair.first()[2..];
            const value = pair.rest();
            // if (pair.next() != null)
            //     return errorMessage(error.InvalidOption, "Option passed with more than one equal sign ({s}).\n", .{ arg });
            log.debug("Option {s}={s}", .{ key, value });
            try arg_map.put(key, .{ .value = value });
        } else if (std.mem.startsWith(u8, arg, "-")) {
            log.debug("Option {s} present", .{ arg[1..] });
            try arg_map.put(arg[1..], .present);
        } else if (arg_map.count() == 0)
            continue
        else
            return logErr(error.InvalidOption, "Option is invalid [doesn't start with '-' or '--'] ('{s}').", .{ arg });
    }

    const jdk_path = try requireValueOption(arg_map, "jdk_path")
        orelse return logErr(error.MissingJdk, "Specifying the JDK path is required.", .{});
    const source_path = try requireValueOption(arg_map, "src")
        orelse "test/src/main.nerve";
    const output_path = try requireValueOption(arg_map, "out")
        orelse "test/out/Main.class";

    const cwd = std.fs.cwd();
    const source_file = cwd.openFile(source_path, .{ .mode = .read_only })
        catch |e| return logErr(e, "Could not open source file '{s}'.", .{ source_path });
    var buf: [2048]u8 = undefined;
    var source_reader = source_file.reader(&buf);
    const r = &source_reader.interface;
    const source = try r.allocRemaining(gpa, .unlimited);
    defer gpa.free(source);

    try Nerve.compile(gpa, source, source_path, jdk_path, output_path);
}

fn requireValueOption(arg_map: std.StringHashMap(Option), key: []const u8) !?[]const u8 {
    const option = arg_map.get(key) orelse return null;
    return switch (option) {
        .value => |v| v,
        else => logErr(error.InvalidOption, "'{s}' must have a value.", .{ key }),
    };
}