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

pub fn size() Size {
    const file = switch (builtin.os.tag) {
        .linux => std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write })
            catch @panic("Cannot open '/dev/tty'."),
        else => std.fs.File.stdout(),
    };
    if (!file.isTty()) return .{ .x = 50, .y = 50 };
    return termSize(file) catch @panic("Could not get terminal size.") orelse .{ .x = 50, .y = 50};
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
    none = std.math.maxInt(u6),
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

pub var utc_offset: i4 = 0;

pub const std_log_fn = struct { fn invoke(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype
) void {
    const milliEpoch = std.time.milliTimestamp();
    const hourEpoch = std.math.divTrunc(i64, milliEpoch, std.time.ms_per_hour) catch -1;
    const minuteEpoch = std.math.divTrunc(i64, milliEpoch, std.time.ms_per_min) catch -1;
    const secondEpoch = std.math.divTrunc(i64, milliEpoch, std.time.ms_per_s) catch -1;

    const hour = std.math.rem(i64, hourEpoch, 24) catch -2;
    const minute = std.math.rem(i64, minuteEpoch, 60) catch -2;
    const second = std.math.rem(i64, secondEpoch, 60) catch -2;
    const milli = std.math.rem(i64, milliEpoch, 1000) catch -2;

    const level_text = comptime switch (message_level) {
        .err => " E ",
        .warn => " W ",
        .info => " I ",
        .debug => " D "
    };
    var millis_buf: [3]u8 = undefined;
    const milli_sting = std.fmt.bufPrint(&millis_buf, "{}", .{ milli }) catch "err";
    var seconds_buf: [2]u8 = undefined;
    const second_string = std.fmt.bufPrint(&seconds_buf, "{}", .{ second }) catch "err";
    var minutes_buf: [2]u8 = undefined;
    const minute_sting = std.fmt.bufPrint(&minutes_buf, "{}", .{ minute }) catch "err";
    var hours_buf: [2]u8 = undefined;
    const hour_sting = std.fmt.bufPrint(&hours_buf, "{}", .{ hour + utc_offset }) catch "err";
    var time_buf: [12]u8 = undefined;
    const time_string = std.fmt.bufPrint(&time_buf, "{s:0>2}:{s:0>2}:{s:0>2}.{s:0>3}", .{
        hour_sting,
        minute_sting,
        second_string,
        milli_sting
    }) catch "error";
    std.debug.print("{s:>13} | ", .{ time_string });
    std.debug.print("{s:>15} | ", .{ @tagName(scope) });
    setState(.foreground, .{ .color = .black }); // Black just works better
    switch (message_level) {
        .err => {
            setState(.foreground, .{ .rgb_color = .{ 210, 210, 210 } }); // except here
            setState(.background, .{ .rgb_color = .{ 180, 20, 20 } });
        },
        .warn =>  setState(.background, .{ .rgb_color = .{ 220, 200, 20 } }),
        .info => setState(.background, .{ .rgb_color = .{ 0, 100, 180 } }),
        .debug => setState(.background, .{ .rgb_color = .{ 0, 180, 100} })
    }
    std.debug.print(level_text, .{});
    setState(.foreground, .{ .attribute = .reset });
    std.debug.print(" | " ++ format ++ "\n", args);
}}.invoke;

pub fn logErr(err: anyerror, comptime fmt: []const u8, args: anytype) anyerror {
    std.log.err(fmt, args);
    return err;
}