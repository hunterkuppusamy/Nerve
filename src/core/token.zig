const root = @import("root");

pub const Token = struct {
    source_data: SourceData,
    data: TokenData,
    kind: TokenKind,
};

pub const SourceData = struct {
    line: usize,
    column: usize,
    index: usize,
};

pub const StringData = struct {
    /// A slice only containing the characters of the string
        slice: []const u8,
};

pub const TokenData = union(enum) {
    /// An allocated string slice, typically for literal_strings.
    /// This is because escape sequences lead to more than just
    /// source slices.
    string: StringData,
    integer: i32,
    u_integer: u32,
    float: f32,
    char: u8,
    bool: bool,
    none,
};

pub const TokenKind = enum(u8) {
    identifier,

    literal_string,
    literal_integer,
    literal_float,
    literal_bool,

    open_paren,
    close_paren,
    open_brace,
    close_brace,
    open_bracket,
    close_bracket,

    period,
    comma,
    colon,
    semicolon,
    equals, // assignment and equality, depending on number of occurrences

    right_arrow,

    keyword_pub, // declaration modifier
    keyword_const, // type or expression modifier
    keyword_static,

    keyword_struct,
    keyword_enum,

    keyword_fn, // declare function
    keyword_var, // declare variable
    keyword_type, // declare type

    keyword_if,
    keyword_elif,
    keyword_else,
    // keyword_switch

    keyword_while,
    keyword_for,
    keyword_break,
    keyword_continue,

    keyword_return,

    operator_add,
    operator_add_assign,
    operator_sub,
    operator_sub_assign,
    operator_mul,
    operator_mul_assign,
    operator_div,
    operator_div_assign,

    operator_less_than,
    operator_greater_than,
};