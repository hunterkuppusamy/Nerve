const std = @import("std");
const CodeContext = @import("gen.zig").CodeContext;

/// Magic
pub const class_format_header = 0xCAFEBABE;

pub const Class = struct {
    magic: u32 = class_format_header,
    minor_version: u16 = 0,
    major_version: u16 = 52,
    constant_pool: std.ArrayList(Constant) = undefined,
    access_flags: ClassAccessFlags = .{
        .public = true,
    },
    this_class: u16 = 0,
    super_class: u16 = 0,
    /// Array of indices of interfaces this class inherits
    interfaces: []const u16 = &[0]u16{},
    fields: std.ArrayList(FieldInfo) = undefined,
    methods: std.ArrayList(MethodInfo) = undefined,
    attributes: std.ArrayList(Attribute) = undefined,

    pub const FieldAccessFlags = packed struct {
        public: bool = false,
        private: bool = false,
        protected: bool = false,
        static: bool = false,

        final: bool = false,
        __unused0: u1 = 0,
        @"volatile": bool = false,
        transient: bool = false,

        synthetic: bool = false,
        __unused1: u1 = 0,
        @"enum": bool = false,
        __unused2: u1 = 0,

        __unused3: u1 = 0,
        __unused4: u1 = 0,
        __unused5: u1 = 0,
        __unused6: u1 = 0,
    };

    pub const ClassAccessFlags = packed struct {
        public: bool = false,
        __unused0: u3 = 0,

        final: bool = false,
        super: bool = false,
        __unused1: u2 = 0,

        __unused2: u1 = 0,
        interface: bool = false,
        abstract: bool = false,
        __unused3: u1 = 0,

        synthetic: bool = false,
        annotation: bool = false,
        @"enum": bool = false,
        module: bool = false,
    };

    pub const MethodAccessFlags = packed struct {
        public: bool = false,
        private: bool = false,
        protected: bool = false,
        static: bool = false,

        final: bool = false,
        synchronized: bool = false,
        bridge: bool = false,
        varargs: bool = false,

        native: bool = false,
        __unused0: u1 = 0,
        abstract: bool = false,
        strict: bool = false,

        synthetic: bool = false,
        __unused1: u3 = 0,
    };

    pub const MethodInfo = struct {
        access_flags: MethodAccessFlags,
        name_index: u16,
        descriptor_index: u16,
        attributes: []const Attribute,
    };

    pub const FieldInfo = struct {
        access_flags: FieldAccessFlags,
        name_index: u16,
        descriptor_index: u16,
        attributes: []const Attribute,
    };

    pub const Attribute = struct {
        attribute_name_index: u16,
        attribute_length: u32,
        info: union(enum) {
            undefined,
            constant_value_index: u16,
            code: Code,
            stack_map_table: StackMapTable,
            exceptions: struct {
                number_of_exceptions: u16,
                exception_index_table: []u16
            },
            inner_classes: struct {
                number_of_classes: u16,
                classes: []struct {
                    inner_class_info_index: u16,
                    outer_class_info_index: u16,
                    inner_name_index: u16,
                    inner_class_access_flags: union(enum){
                        value: u16,
                        typed: packed struct {
                            public: u1 = 0,
                            private: u1 = 0,
                            protected: u1 = 0,
                            static: u1 = 0,

                            final: u1 = 0,
                            __unused0: u1 = 0,
                            __unused1: u1 = 0,
                            __unused2: u1 = 0,

                            __unused3: u1 = 0,
                            interface: u1 = 0,
                            abstract: u1 = 0,
                            __unused4: u1 = 0,

                            synthetic: u1 = 0,
                            annotation: u1 = 0,
                            @"enum": u1 = 0,
                            __unused5: u1 = 0,
                        }
                    },
                }
            },
            enclosing_method: struct {
                class_index: u16,
                method_index: u16,
            },
            synthetic: struct {},
            signature: struct {
                signature_index: u16,
            },
            source_file: struct {
                /// Refers to a utf8_info which is the name of the source file.
                sourcefile_index: u16,
            },
            line_number_table: struct {
                line_number_table_length: u16,
                line_number_table: []struct {
                    start_pc: u16,
                    line_number: u16,
                },
            },
            local_variable_table: struct {
                local_variable_table_length: u16,
                local_variable_table: []struct {
                    start_pc: u16,
                    length: u16,
                    name_index: u16,
                    descriptor_index: u16,
                    index: u16,
                },
            },
            deprecated: struct{},
            runtime_visible_annotations: struct {
                num_annotations: u16,
                annotations: []Annotation,
            },
            runtime_invisible_annotations: struct {
                num_annotations: u16,
                annotations: []Annotation,
            },
            runtime_visible_parameter_annotations: struct {
                num_parameters: u16,
                parameter_annotations: []struct {
                    num_annotations: u16,
                    annotations: []Annotation,
                },
            },
            runtime_invisible_parameter_annotations: struct {
                num_parameters: u16,
                parameter_annotations: []struct {
                    num_annotations: u16,
                    annotations: []Annotation,
                },
            },
            runtime_visible_type_annotations: struct {
                num_annotations: u16,
                annotations: []TypeAnnotation,
            },
            runtime_invisible_type_annotations: struct {
                num_annotations: u16,
                annotations: []TypeAnnotation,
            },
            annotation_default: struct {
                default_value: Annotation.ElementValue
            },
            bootstrap_methods: struct {
                // TODO??
            },
            method_parameters: struct {
                parameters_count: u8,
                parameters: []struct {
                    name_index: u16,
                    access_flags: union(enum){
                        value: u16,
                        typed: packed struct {
                            __unused0: u4 = 0,

                            final: u1 = 0,
                            __unused1: u3 = 0,

                            __unused2: u4 = 0,

                            synthetic: u1 = 0,
                            __unused3: u2 = 0,
                            mandated: u1 = 0,
                        },
                    }
                }
            }
        },

        pub const TypeAnnotation = struct {
            target_type: u8,
            target_info: union(enum) {
                type_parameters_target: struct {
                    type_parameter_index: u8,
                },
                supertype_target: struct {
                    supertype_index: u16,
                },
                type_parameter_bound_target: struct {
                    type_parameter_index: u8,
                    bound_index: u8,
                },
                empty_target: struct {},
                formal_parameter_target: struct {
                    formal_parameter_index: u8,
                },
                throws_target: struct {
                    throws_type_index: u16,
                },
                localvar_target: struct {
                    table_length: u16,
                    table: []struct {
                        start_pc: u16,
                        length: u16,
                        index: u16,
                    },
                },
                catch_target: struct {
                    exception_table_index: u16,
                },
                offset_target: struct {
                    offset: u16,
                    type_argument_index: u8,
                },
                type_argument_target: struct {
                    offset: u16,
                    type_argument_index: u8,
                },
            },
            target_path: TypePath,
            type_index: u16,
            num_element_value_pairs: u16,
            element_value_pairs: []struct {
                element_name_index: u16,
                element_value: Annotation.ElementValue,
            },

            pub const TypePath = struct {
                path_length: u8,
                path: []struct {
                    type_path_kind: u8,
                    type_argument_index: u8
                },
            };
        };

        pub const Annotation = struct {
            type_index: u16,
            num_element_value_pairs: u16,
            element_value_pairs: []struct {
                element_name_index: u16,
                element_value: ElementValue,
            },

            pub const ElementValue = struct {
                tag: u8,
                value: union(enum) {
                    const_value_index: u16,
                    enum_const_value: struct {
                        type_name_index: u16,
                        const_name_index: u16,
                    },
                    class_info_index: u16,
                    annotation_value: Annotation,
                    array_value: struct {
                        num_values: u16,
                        values: []ElementValue,
                    },
                }
            };
        };

        pub const Code = struct {
            max_stack: u16,
            max_locals: u16,
            code: []const u8,
            exception_table: []Exception,
            attributes: []Attribute,

            pub const Exception = struct {
                start_pc: u16,
                end_pc: u16,
                handler_pc: u16,
                catch_type: u16,
            };
        };

        pub const StackMapTable = struct {
            number_of_entries: u16,
            entries: []struct {
                // TODO fix
            },

            pub const VerificationTypeInfo = union(enum) {
                top_variable_info: struct {
                    tag: VerificationType.top,
                },
                integer_variable_info: struct {
                    tag: VerificationType.integer,
                },
                float_variable_info: struct {
                    tag: VerificationType.float,
                },
                null_variable_info: struct {
                    tag: VerificationType.null,
                },
                uninitialized_this_variable_info: struct {
                    tag: VerificationType.uninitialized_this,
                },
                object_variable_info: struct {
                    tag: VerificationType.object,
                    cpool_index: u16,
                },
                uninitialized_variable_info: struct {
                    tag: VerificationType.uninitialized,
                    offset: u16,
                },
                /// double size
                long_variable_info: struct {
                    tag: VerificationType.long,
                },
                /// double size
                double_varaible_info: struct {
                    tag: VerificationType.double,
                }
            };

            pub const VerificationType = enum(u8) {
                top = 0, integer = 1, float = 2, null = 5,
                uninitialized_this = 6, object = 7, uninitialized = 8,
                long = 4, double = 3,
            };

            pub const StackMapFrame = union(enum) {
                same_frame: struct {
                    frame_type: u8, // 0-63
                },
                same_locals_1_stack_item_frame: struct {
                    frame_type: u8, // 64-127
                    stack: []VerificationTypeInfo,
                },
                same_locals_1_stack_item_frame_extended: struct {
                    frame_type: u8, // 247
                    offset_delta: u16,
                    stack: []VerificationTypeInfo,
                },
                chop_frame: struct {
                    frame_type: u8, // 248-250
                    offset_delta: u16,
                },
                same_frame_extended: struct {
                    frame_type: u8, // 251
                    offset_delta: u16,
                },
                append_frame: struct {
                    frame_type: u8, // 252-254
                    offset_delta: u16,
                    locals: []VerificationTypeInfo
                },
                full_frame: struct {
                    frame_type: u8, // 255
                    offset_delta: u16,
                    number_of_locals: u16,
                    locals: []VerificationTypeInfo,
                    number_of_stack_items: u16,
                    stack: []VerificationTypeInfo
                }
            };
        };
    };

    pub const Constant = union(enum) {
        utf_8_info: struct {
            tag: u8 = @intFromEnum(Tag.utf8),
            /// Some special rules:
            /// - No byte may have the value of 0
            /// - No byte may be in the range 0xf0..0xff
            ///
            /// See Section 3.9 Unicode Encoding Forms of The Unicode Standard, Version 6.0.0
            bytes: []const u8,
        },
        integer_info: struct {
            tag: u8 = @intFromEnum(Tag.integer),
            /// big-endian
            bytes: u32,
        },
        float_info: struct {
            tag: u8 = @intFromEnum(Tag.float),
            /// IEEE 754 big-endian
            bytes: u32,
        },
        long_info: struct {
            tag: u8 = @intFromEnum(Tag.long),
            /// big-endian
            high_bytes: u32,
            /// big-endian
            low_bytes: u32,
        },
        double_info: struct {
            tag: u8 = @intFromEnum(Tag.double),
            /// big-endian
            high_bytes: u32,
            /// big-endian
            low_bytes: u32,
        },
        class_info: struct {
            tag: u8 = @intFromEnum(Tag.class),
            name_index: u16,
        },
        string_info: struct {
            tag: u8 = @intFromEnum(Tag.string),
            string_index: u16,
        },
        field_ref_info: struct {
            tag: u8 = @intFromEnum(Tag.fieldref),
            class_index: u16,
            name_and_type_index: u16,
        },
        method_ref_info: struct {
            tag: u8 = @intFromEnum(Tag.methodref),
            class_index: u16,
            name_and_type_index: u16,
        },
        interface_ref_info: struct {
            tag: u8 = @intFromEnum(Tag.interface_methodref),
            class_index: u16,
            name_and_type_index: u16,
        },
        name_and_type_info: struct {
            tag: u8 = @intFromEnum(Tag.name_and_type),
            name_index: u16,
            descriptor_index: u16,
        },
        method_handle_info: struct {
            tag: u8 = @intFromEnum(Tag.method_handle),
            reference_kind: enum(u8) {
                get_field = 1,
                get_static = 2,
                put_field = 3,
                put_static = 4,
                invoke_virtual = 5,
                invoke_static = 6,
                invoke_special = 7,
                new_invoke_special = 8,
                invoke_interface = 9,
            },
            /// - If `reference_kind` is `reference_kind`, `get_static`, `put_field`, or `put_static`,
            /// then the constant pool entry must be a `field_ref_info`.
            ///
            /// - If `reference_kind` is `invoke_virtual` or `new_invoke_special`, then the constant
            /// pool entry must be a `method_ref_info` (method or constructor).
            ///
            /// - If `reference_kind` is `invoke_static` or `invoke_special`, then if the class file version is less
            /// than `52.0`, the constant pool entry must be a `method_ref_info`. If the class file version is `52.0` or above,
            /// it can be either `method_ref_info` or `interface_method_ref_info`.
            ///
            /// - If `reference_kind` is `invoke_interface`, then the constant pool entry must be a
            /// `interface_method_ref_info`.
            ///
            /// `invoke_virtual`, `invoke_static`, `invoke_special`, or `invoke_interface` must not point to a
            /// static or instance constructor (<init> or <clinit>).
            ///
            /// `new_invoke_special` must point to an instance constructor (<init>).
            reference_index: u16,
        },
        method_type_info: struct {
            tag: u8 = @intFromEnum(Tag.method_type),
            descriptor_index: u16,
        },
        invoke_dynamic: struct {
            tag: u8 = @intFromEnum(Tag.invoke_dynamic),
            // Usually includes:
            // - bootstrap_method_attr_index: u16,
            // - name_and_type_index: u16,
        },
        /// Only exists to buffer after longs and doubles (which occupy two indices in the class file).
        placeholder : void,

        pub const Tag = enum(u8) {
            utf8 = 1,
            integer = 3,
            float = 4,
            long = 5,
            double = 6,
            class = 7,
            string = 8,
            fieldref = 9,
            methodref = 10,
            interface_methodref = 11,
            name_and_type = 12,
            method_handle = 15,
            method_type = 16,
            dynamic = 17,
            invoke_dynamic = 18,
            module = 19,
            package = 20,
        };
    };
};

pub const OperandForm = enum {
    none,
    U8,            // one unsigned byte
    I8,            // one signed byte
    U16,           // two unsigned bytes (big-endian)
    I16,           // two signed bytes
    branch_offset,  // signed offset (usually 16 bits; some instructions use 32-bit)
    U8_constant,        // constant-pool index (u16 for most, but some use u8)
    U16_constant,
    local,      // local variable index (u8 or u16 if “wide” prefix)
    local_index_const, // e.g. iinc: (index, const)
    offset_w,   // e.g. goto_w / jsr_w (32-bit offset)
    contextual,        // variable-length (tableswitch, lookupswitch)
};

pub const Op = struct {
    pub const Meta = struct {
        mnemonic: []const u8,
        operand_form: OperandForm,
        stack_pop: i8,
        stack_push: i8,
    };

    pub const Code = enum(u8) {
        // Constants / literals
        NOP = 0x00,
        ACONST_NULL = 0x01,
        ICONST_M1 = 0x02,
        ICONST_0 = 0x03,
        ICONST_1 = 0x04,
        ICONST_2 = 0x05,
        ICONST_3 = 0x06,
        ICONST_4 = 0x07,
        ICONST_5 = 0x08,
        LCONST_0 = 0x09,
        LCONST_1 = 0x0a,
        FCONST_0 = 0x0b,
        FCONST_1 = 0x0c,
        FCONST_2 = 0x0d,
        DCONST_0 = 0x0e,
        DCONST_1 = 0x0f,
        BIPUSH = 0x10,
        SIPUSH = 0x11,
        LDC = 0x12,
        LDC_W = 0x13,
        LDC2_W = 0x14,

        // Loads
        ILOAD = 0x15,
        LLOAD = 0x16,
        FLOAD = 0x17,
        DLOAD = 0x18,
        ALOAD = 0x19,
        ILOAD_0 = 0x1a,
        ILOAD_1 = 0x1b,
        ILOAD_2 = 0x1c,
        ILOAD_3 = 0x1d,
        // ... (other load_n, wide, etc.)

        // Stores
        ISTORE = 0x36,
        LSTORE = 0x37,
        FSTORE = 0x38,
        DSTORE = 0x39,
        ASTORE = 0x3a,
        ISTORE_0 = 0x3b,
        ISTORE_1 = 0x3c,
        ISTORE_2 = 0x3d,
        ISTORE_3 = 0x3e,
        // ... (other store_n, wide, etc.)

        // Stack
        POP = 0x57,
        POP2 = 0x58,
        DUP = 0x59,
        DUP_X1 = 0x5a,
        DUP_X2 = 0x5b,
        DUP2 = 0x5c,
        DUP2_X1 = 0x5d,
        DUP2_X2 = 0x5e,
        SWAP = 0x5f,

        // Math
        IADD = 0x60,
        LADD = 0x61,
        FADD = 0x62,
        DADD = 0x63,
        ISUB = 0x64,
        // ... (many more arithmetic, shifts, etc.)

        // Conversions
        I2L = 0x85,
        I2F = 0x86,
        I2D = 0x87,
        // ... (other conversion opcodes)

        // Control / branching
        GOTO = 0xa7,
        IFEQ = 0x99,
        IFNE = 0x9a,
        IF_ICMPEQ = 0x9f,
        IF_ICMPNE = 0xa0,
        IF_ICMPLT = 0xa1,
        IF_ICMPGE = 0xa2,
        IF_ICMPGT = 0xa3,
        IF_ICMPLE = 0xa4,
        GOTO_W = 0xc8,
        // ... (other branch instructions)

        // Method invocation & return
        RETURN = 0xb1,
        IRETURN = 0xac,
        FRETURN = 0xae,
        ARETURN = 0xb0,
        INVOKEVIRTUAL = 0xb6,
        INVOKESPECIAL = 0xb7,
        INVOKESTATIC = 0xb8,
        INVOKEINTERFACE = 0xb9,
        INVOKEDYNAMIC = 0xba,

        // Field / method / class ops
        GETSTATIC = 0xb2,
        PUTSTATIC = 0xb3,
        GETFIELD = 0xb4,
        PUTFIELD = 0xb5,
        NEW = 0xbb,
        NEWARRAY = 0xbc,
        ANEWARRAY = 0xbd,
        ARRAYLENGTH = 0xbe,
        CHECKCAST = 0xc0,
        INSTANCEOF = 0xc1,
        // ... (others, e.g. monitorenter, monitorexit)

        // Exception / others
        ATHROW = 0xbf,
        // Reserved / special
        IMPDEP1 = 0xfe,
        IMPDEP2 = 0xff,
        _
    };

    pub fn meta(op: Code) ?Meta {
        return switch (op) {
        // Constants / literals
            .NOP => .{ .mnemonic = "nop", .operand_form = .none, .stack_pop = 0, .stack_push = 0 },
            .ACONST_NULL => .{ .mnemonic = "aconst_null", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_M1 => .{ .mnemonic = "iconst_m1", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_0 => .{ .mnemonic = "iconst_0", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_1 => .{ .mnemonic = "iconst_1", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_2 => .{ .mnemonic = "iconst_2", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_3 => .{ .mnemonic = "iconst_3", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_4 => .{ .mnemonic = "iconst_4", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .ICONST_5 => .{ .mnemonic = "iconst_5", .operand_form = .none, .stack_pop = 0, .stack_push = 1 },
            .BIPUSH => .{ .mnemonic = "bipush", .operand_form = .I8, .stack_pop = 0, .stack_push = 1 },
            .SIPUSH => .{ .mnemonic = "sipush", .operand_form = .I16, .stack_pop = 0, .stack_push = 1 },
            .LDC => .{ .mnemonic = "ldc", .operand_form = .U8_constant, .stack_pop = 0, .stack_push = 1 },
            .LDC_W => .{ .mnemonic = "ldc_w", .operand_form = .U16_constant, .stack_pop = 0, .stack_push = 1 },
            .LDC2_W => .{ .mnemonic = "ldc2_w", .operand_form = .U16_constant, .stack_pop = 0, .stack_push = 1 },

            // Loads
            .ILOAD => .{ .mnemonic = "iload", .operand_form = .local, .stack_pop = 0, .stack_push = 1 },
            .LLOAD => .{ .mnemonic = "lload", .operand_form = .local, .stack_pop = 0, .stack_push = 1 },
            .FLOAD => .{ .mnemonic = "fload", .operand_form = .local, .stack_pop = 0, .stack_push = 1 },
            .DLOAD => .{ .mnemonic = "dload", .operand_form = .local, .stack_pop = 0, .stack_push = 1 },
            .ALOAD => .{ .mnemonic = "aload", .operand_form = .local, .stack_pop = 0, .stack_push = 1 },

            // Stores
            .ISTORE => .{ .mnemonic = "istore", .operand_form = .local, .stack_pop = 1, .stack_push = 0 },
            .LSTORE => .{ .mnemonic = "lstore", .operand_form = .local, .stack_pop = 1, .stack_push = 0 },
            .FSTORE => .{ .mnemonic = "fstore", .operand_form = .local, .stack_pop = 1, .stack_push = 0 },
            .DSTORE => .{ .mnemonic = "dstore", .operand_form = .local, .stack_pop = 1, .stack_push = 0 },
            .ASTORE => .{ .mnemonic = "astore", .operand_form = .local, .stack_pop = 1, .stack_push = 0 },

            // Stack operations
            .POP => .{ .mnemonic = "pop", .operand_form = .none, .stack_pop = 1, .stack_push = 0 },
            .POP2 => .{ .mnemonic = "pop2", .operand_form = .none, .stack_pop = 2, .stack_push = 0 },
            .DUP => .{ .mnemonic = "dup", .operand_form = .none, .stack_pop = 1, .stack_push = 2 },
            .SWAP => .{ .mnemonic = "swap", .operand_form = .none, .stack_pop = 2, .stack_push = 2 },

            // Arithmetic
            .IADD => .{ .mnemonic = "iadd", .operand_form = .none, .stack_pop = 2, .stack_push = 1 },
            .LADD => .{ .mnemonic = "ladd", .operand_form = .none, .stack_pop = 2, .stack_push = 1 },
            .FADD => .{ .mnemonic = "fadd", .operand_form = .none, .stack_pop = 2, .stack_push = 1 },
            .DADD => .{ .mnemonic = "dadd", .operand_form = .none, .stack_pop = 2, .stack_push = 1 },

            // Conversions
            .I2L => .{ .mnemonic = "i2l", .operand_form = .none, .stack_pop = 1, .stack_push = 1 },
            .I2F => .{ .mnemonic = "i2f", .operand_form = .none, .stack_pop = 1, .stack_push = 1 },
            .I2D => .{ .mnemonic = "i2d", .operand_form = .none, .stack_pop = 1, .stack_push = 1 },

            // Branch / control
            .GOTO => .{ .mnemonic = "goto", .operand_form = .branch_offset, .stack_pop = 0, .stack_push = 0 },
            .IFEQ => .{ .mnemonic = "ifeq", .operand_form = .branch_offset, .stack_pop = 1, .stack_push = 0 },
            .IFNE => .{ .mnemonic = "ifne", .operand_form = .branch_offset, .stack_pop = 1, .stack_push = 0 },
            .IF_ICMPEQ => .{ .mnemonic = "if_icmpeq", .operand_form = .branch_offset, .stack_pop = 2, .stack_push = 0 },
            .GOTO_W => .{ .mnemonic = "goto_w", .operand_form = .offset_w, .stack_pop = 0, .stack_push = 0 },

            // Method invocation & return
            .RETURN => .{ .mnemonic = "return", .operand_form = .none, .stack_pop = 0, .stack_push = 0 },
            .IRETURN => .{ .mnemonic = "ireturn", .operand_form = .none, .stack_pop = 1, .stack_push = 0 },
            .FRETURN => .{ .mnemonic = "freturn", .operand_form = .none, .stack_pop = 1, .stack_push = 0 },
            .ARETURN => .{ .mnemonic = "areturn", .operand_form = .none, .stack_pop = 1, .stack_push = 0 },
            .INVOKEVIRTUAL => .{ .mnemonic = "invokevirtual", .operand_form = .U16, .stack_pop = -1, .stack_push = -1 }, // pop: objectref + args, push: return value
            .INVOKESPECIAL => .{ .mnemonic = "invokespecial", .operand_form = .U16, .stack_pop = -1, .stack_push = -1 },
            .INVOKESTATIC => .{ .mnemonic = "invokestatic", .operand_form = .U16, .stack_pop = -1, .stack_push = -1 },
            .INVOKEINTERFACE => .{ .mnemonic = "invokeinterface", .operand_form = .U16, .stack_pop = -1, .stack_push = -1 },
            .INVOKEDYNAMIC => .{ .mnemonic = "invokedynamic", .operand_form = .U16, .stack_pop = -1, .stack_push = -1 },

            // Field / object
            .GETSTATIC => .{ .mnemonic = "getstatic", .operand_form = .U16, .stack_pop = 0, .stack_push = 1 },
            .PUTSTATIC => .{ .mnemonic = "putstatic", .operand_form = .U16, .stack_pop = 1, .stack_push = 0 },
            .GETFIELD => .{ .mnemonic = "getfield", .operand_form = .U16, .stack_pop = 1, .stack_push = 1 },
            .PUTFIELD => .{ .mnemonic = "putfield", .operand_form = .U16, .stack_pop = 2, .stack_push = 0 },
            .NEW => .{ .mnemonic = "new", .operand_form = .U16, .stack_pop = 0, .stack_push = 1 },
            .NEWARRAY => .{ .mnemonic = "newarray", .operand_form = .U8, .stack_pop = 1, .stack_push = 1 },
            .ANEWARRAY => .{ .mnemonic = "anewarray", .operand_form = .U16, .stack_pop = 1, .stack_push = 1 },
            .ARRAYLENGTH => .{ .mnemonic = "arraylength", .operand_form = .none, .stack_pop = 1, .stack_push = 1 },
            .CHECKCAST => .{ .mnemonic = "checkcast", .operand_form = .U16, .stack_pop = 1, .stack_push = 1 },
            .INSTANCEOF => .{ .mnemonic = "instanceof", .operand_form = .U16, .stack_pop = 1, .stack_push = 1 },

            // Exception / other
            .ATHROW => .{ .mnemonic = "athrow", .operand_form = .none, .stack_pop = 1, .stack_push = 0 },
            .IMPDEP1 => .{ .mnemonic = "impdep1", .operand_form = .none, .stack_pop = 0, .stack_push = 0 },
            .IMPDEP2 => .{ .mnemonic = "impdep2", .operand_form = .none, .stack_pop = 0, .stack_push = 0 },

            else => null,
        };
    }
};

pub const DEBUG_SHORT: u16 = 0xdead;