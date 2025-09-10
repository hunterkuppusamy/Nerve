const std = @import("std");
const Writer = std.io.Writer;

pub const Color = union(enum) {
    rgb: struct {
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

pub fn setColor(s: ColorSpace, c: Color) void {
    var buf: [64]u8 = undefined;
    const w = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();
    setWriterColor(w, s, c) catch return;
}

pub fn setWriterColor(w: *Writer, s: ColorSpace, c: Color) !void {
    switch (c) {
        .color => {
            try w.print("\x1b[{};5;{}m", .{ @intFromEnum(s), @intFromEnum(c.color) });
        },
        .rgb => {
            try w.print("\x1b[{};2;{};{};{}m", .{ @intFromEnum(s), c.rgb.@"0", c.rgb.@"1", c.rgb.@"2" });
        },
        .attribute => {
            try w.print("\x1b[{}m", .{ @intFromEnum(c.attribute) });
        }
    }
}