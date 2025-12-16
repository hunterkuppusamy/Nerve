const std = @import("std");
const op = @import("util").op;
const SourceSpan = @import("SourceSpan.zig");

pub const Node = union(enum) {
    type_def: TypeDef,

    field_def: FieldDef,
    function_def: FunctionDef,

    block: Code,

    pub const TypeDef = struct {
        name: []const u8,
        fields: []Node,
        source: SourceSpan,
    };

    pub const FunctionDef = struct {
        name: []const u8,
        params: []Param,
        ret: TypeRef,
        body: *Code,
        source: SourceSpan,

        pub const Param = struct {
            name: []const u8,
            type: TypeRef,
            source: SourceSpan,
        };
    };

    pub const FieldDef = struct {
        name: []const u8,
        type: TypeRef,
        flags: Flags,
        value: ?*Code,
        source: SourceSpan,

        pub const Flags = struct {
            public: bool,
            constant: bool,
            static: bool,
        };
    };

    pub const Code = struct {
        instructions: []Instruction,
        source: SourceSpan,
    };

    pub const TypeRef = struct {
        name: []const u8,
        kind: TypeKind,
        def: ?Node,
    };

    pub const TypeKind = union(enum) {
        type,
        function,
        array: TypeKind, // of what?
        string,
        i32,
        f32,
        i64,
        f64
    };

    pub const Instruction = union(enum) {
        pop: Pop,
        push_object: PushObject,
        push_string: PushString,
        push_bool: PushBool,
        push_int: PushInt,
        push_long: PushLong,
        push_float: PushFloat,
        push_double: PushDouble,

        binary_op: *BinaryOp,

        load_field: *LoadField,
        store_field: *StoreField,

        load_local: *LoadLocal,
        store_local: *StoreLocal,

        ret: *Return,

        invoke: *Invoke,

        pub const BinaryOp = struct {
            op: op.BinaryOperation,
            source: SourceSpan,
        };

        pub const UnaryOp = struct {
            op: op.UnaryOperation,
            source: SourceSpan,
        };

        ///
        /// Types are checked upon usage of popped elements, like when a function consumes stack elements.
        ///
        pub const Pop = struct {
            source: SourceSpan
        };

        pub const PushObject = struct {
            source: SourceSpan
        };

        pub const PushString = struct {
            value: []const u8,
            source: SourceSpan
        };

        pub const PushBool = struct {
            value: bool,
            source: SourceSpan
        };

        pub const PushInt = struct {
            value: i32,
            source: SourceSpan
        };

        pub const PushLong = struct {
            value: i64,
            source: SourceSpan
        };

        pub const PushFloat = struct {
            value: f32,
            source: SourceSpan
        };

        pub const PushDouble = struct {
            value: f64,
            source: SourceSpan
        };

        ///
        /// Store a local value, from the stack, into a local variable.
        ///
        pub const StoreLocal = struct {
            name: []const u8,
            source: SourceSpan
        };

        ///
        /// Load local onto stack
        ///
        pub const LoadLocal = struct {
            name: []const u8,
            source: SourceSpan
        };

        ///
        /// invoke a function and store its result on the stack.
        /// Destroys the arguments for the function that were passed in from the stack.
        ///
        /// stack order is as follows, from top of stack at the top and bottom at the bottom:
        ///     - argument arg_len - 1
        ///     - argument arg_len - 2
        ///     ...
        ///     - argument arg_len - arg_len
        ///
        /// the Instance of the type to invoke the function is just the first argument, or non-existent based on function def.
        ///
        pub const Invoke = struct {
            function: *FunctionDef,
            arg_len: u8,
            source: SourceSpan
        };

        ///
        /// Instance is top of stack.
        ///
        /// Field def has the type information.
        ///
        pub const LoadField = struct {
            field: *FieldDef,
            source: SourceSpan,
        };

        ///
        /// Instance is top of stack.
        ///
        /// Field def has the type information.
        ///
        pub const StoreField = struct {
            field: *FieldDef,
            source: SourceSpan,
        };

        ///
        /// Value is top of stack, if valued, otherwise returns void and stack frame is cleared upon function return as expected.
        ///
        pub const Return = struct {
            valued: bool,
            source: SourceSpan,
        };

        pub fn source(self: *Instruction) SourceSpan {
            switch(self.*) {
                inline else => |i| return i.source,
            }
        }
    };
};