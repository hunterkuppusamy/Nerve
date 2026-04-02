const std = @import("std");
const Nerve = @import("Nerve");

const usage =
    \\Usage: nerve [options] <file>
    \\       nerve [options] -e <source>
    \\
    \\Compile Nerve source to JVM class files.
    \\
    \\Options:
    \\  -o <path>       Output class file path (default: out/<ClassName>.class)
    \\  -e <source>     Compile inline source instead of a file
    \\  --name <name>   Class name (default: derived from filename or "Main")
    \\  --jdk <path>    Path to JDK class files (default: test/jdk)
    \\  -h, --help      Show this help message
    \\
;

pub fn main() !void {
    var gpa_backing = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_backing.deinit();
    const gpa = gpa_backing.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var output: ?[]const u8 = null;
    var class_name: ?[]const u8 = null;
    var jdk_path: []const u8 = "test/jdk";
    var source_file: ?[]const u8 = null;
    var inline_source: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            return;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return fatal("missing argument for -o");
            output = args[i];
        } else if (std.mem.eql(u8, arg, "-e")) {
            i += 1;
            if (i >= args.len) return fatal("missing argument for -e");
            inline_source = args[i];
        } else if (std.mem.eql(u8, arg, "--name")) {
            i += 1;
            if (i >= args.len) return fatal("missing argument for --name");
            class_name = args[i];
        } else if (std.mem.eql(u8, arg, "--jdk")) {
            i += 1;
            if (i >= args.len) return fatal("missing argument for --jdk");
            jdk_path = args[i];
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            source_file = arg;
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.debug.print("{s}", .{usage});
            std.process.exit(1);
        }
    }

    if (inline_source == null and source_file == null) {
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    const source = if (inline_source) |src|
        src
    else
        std.fs.cwd().readFileAlloc(gpa, source_file.?, 10 * 1024 * 1024) catch |e| {
            std.debug.print("error: could not read '{s}': {}\n", .{ source_file.?, e });
            std.process.exit(1);
        };
    defer if (inline_source == null) gpa.free(source);

    const derived_name = class_name orelse if (source_file) |path| deriveName(path) else "Main";
    const out = output orelse try std.fmt.allocPrint(gpa, "out/{s}.class", .{derived_name});
    defer if (output == null) gpa.free(out);

    if (output == null) {
        std.fs.cwd().makePath("out") catch {};
    }

    Nerve.compile(source, .{
        .output = out,
        .class_name = derived_name,
        .jdk_path = jdk_path,
        .file_name = source_file orelse "<inline>",
    }) catch |e| {
        std.debug.print("error: compilation failed: {}\n", .{e});
        std.process.exit(1);
    };

    std.debug.print("compiled {s}\n", .{out});
}

fn deriveName(path: []const u8) []const u8 {
    var name = std.fs.path.basename(path);
    if (std.mem.indexOfScalar(u8, name, '.')) |dot| {
        name = name[0..dot];
    }
    return name;
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}