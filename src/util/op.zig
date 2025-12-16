pub const BinaryOperation = enum {
    // zig fmt: align
    // Op | Op then assign
    add,
    adda,

    sub,
    suba,

    mul,
    mula,

    div,
    diva,

    lt,
    lte,
    gt,
    gte,
};

pub const UnaryOperation = enum {
    negate,
};