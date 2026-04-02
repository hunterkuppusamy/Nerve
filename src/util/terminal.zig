const std = @import("std");
const io = std.Io;
const os = std.os;
const builtin = @import("builtin");
const Writer = io.Writer;

const Size = struct {
    x: u16, y: u16,
};

fn termSize(file: std.fs.File) !?Size {
    if (!file.supportsAnsiEscapeCodes()) {
        return null;
    }
    return switch (builtin.os.tag) {
        .windows => blk: {
            var buf: os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            break :blk switch (os.windows.kernel32.GetConsoleScreenBufferInfo(
                file.handle,
                &buf,
            )) {
                os.windows.TRUE => .{
                    .x = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1),
                    .y = @intCast(buf.srWindow.Bottom - buf.srWindow.Top + 1),
                },
                else => error.Unexpected,
            };
        },
        .linux, .macos => blk: {
            var buf: std.posix.winsize = undefined;
            break :blk switch (std.posix.errno(
                std.posix.system.ioctl(
                    file.handle,
                    std.posix.T.IOCGWINSZ,
                    @intFromPtr(&buf),
                ),
            )) {
                .SUCCESS => .{
                    .x = buf.col,
                    . y= buf.row,
                },
                else => error.IoctlError,
            };
        },
        else => error.Unsupported,
    };
}

const default_size = Size{ .x = 80, .y = 24 };

pub fn size() Size {
    const file = switch (builtin.os.tag) {
        .linux => std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write })
            catch return default_size,
        else => std.fs.File.stdout(),
    };
    if (!file.isTty()) return default_size;
    return (termSize(file) catch return default_size) orelse default_size;
}

pub fn columns() usize {
    return if (size().x == 0) 50 else size().x;
}

pub fn rows() usize {
    return if (size().y == 0) 50 else size().y;
}


pub const State = union(enum) {
    rgb_color: struct {
        u8, u8, u8
    },
    attribute: enum(u6) {
        reset = 0,

        bold = 1,
        dim = 2,
        /// Resets intensity, which includes 'dim'
        bold_off = 22,

        italic = 3,
        italic_off = 23,
        strike = 9,
        strike_off = 29,
        underline = 4,
        /// sometimes incorrectly 'disables bold'
        underline_double = 21,
        underline_off = 24,

        blink_slow = 5,
        blink_fast = 6,
        blink_off = 25,

        font_default = 10,
        font_alt_1 = 11,
        font_alt_9 = 19,

        conceal = 8,
        conceal_off = 28,

        foreground_default = 39,
        background_default = 49,

        _,
    },
    color: enum(u8) {
        black = 0,
        red = 1,
        green = 2,
        yellow = 3,
        blue = 4,
        cyan = 6,
        white = 7,
        _
    }
};

pub const ColorSpace = enum(u6) {
    foreground = 38,
    background = 48,
    /// Not in standard, but supported by some popular terminals.
    underline = 58,
};

pub fn setState(s: ColorSpace, c: State) void {
    var buf: [64]u8 = undefined;
    const w = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    setTerminalState(w, s, c) catch return;
}

pub fn setTerminalState(w: *Writer, s: ColorSpace, c: State) !void {
    switch (c) {
        .color => {
            try w.print("\x1b[{};5;{}m", .{ @intFromEnum(s), @intFromEnum(c.color) });
        },
        .rgb_color => {
            try w.print("\x1b[{};2;{};{};{}m", .{ @intFromEnum(s), c.rgb_color.@"0", c.rgb_color.@"1", c.rgb_color.@"2" });
        },
        .attribute => {
            try w.print("\x1b[{}m", .{ @intFromEnum(c.attribute) });
        }
    }
}