const std = @import("std");

/// Magic
const class_format_header = 0xCAFEBABE;

pub const ClassFile = struct {
    magic: u32 = class_format_header,
    minor_version: u16,
    major_version: u16,
    constant_pool_count: u16,
    constant_pool: []Constant,
    access_flags: ClassAccessFlags,
    this_class: u16,
    super_class: u16,
    interfaces_count: u16,
    /// Array of indices of interfaces this class inherits
    interfaces: []u16,
    fields_count: u16,
    fields: []FieldInfo,
    methods_count: u16,
    methods: []MethodInfo,
    attributes_count: u16,
    attributes: []Attribute,

    pub const FieldAccessFlags = union(enum) {
        value: u16,
        typed: packed struct {
            public: u1 = 0,
            private: u1 = 0,
            protected: u1 = 0,
            static: u1 = 0,

            final: u1 = 0,
            __unused0: u1 = 0,
            @"volatile": u1 = 0,
            transient: u1 = 0,

            synthetic: u1 = 0,
            __unused1: u1 = 0,
            @"enum": u1 = 0,
            __unused2: u1 = 0,

            __unused3: u1 = 0,
            __unused4: u1 = 0,
            __unused5: u1 = 0,
            __unused6: u1 = 0,
        },
    };

    pub const ClassAccessFlags = union(enum) {
        value: u16,
        typed: packed struct {
            stuff: u16,
        }
    };

    pub const MethodAccessFlags = union(enum) {
        value: u16,
        typed: packed struct {
            public: u1 = 0,
            private: u1 = 0,
            protected: u1 = 0,
            static: u1 = 0,

            final: u1 = 0,
            synchronized: u1 = 0,
            bridge: u1 = 0,
            varargs: u1 = 0,

            native: u1 = 0,
            __unused0: u1 = 0,
            abstract: u1 = 0,
            strict: u1 = 0,

            synthetic: u1 = 0,
            __unused1: u1 = 0,
            __unused2: u1 = 0,
            __unused3: u1 = 0,
        },
    };

    pub const MethodInfo = struct {
        access_flags: MethodAccessFlags,
        name_index: u16,
        descriptor_index: u16,
        attributes_count: u16,
        attributes: []Attribute,
    };

    pub const FieldInfo = struct {
        access_flags: FieldAccessFlags,
        name_index: u16,
        descriptor_index: u16,
        attributes_count: u16,
        attributes: []Attribute,
    };

    pub const Attribute = struct {
        attribute_name_index: u16,
        attribute_length: u32,
        info: union(enum) {
            constant_value_index: u16,
            code: struct {
                max_stack: u16,
                max_locals: u16,
                code_length: u32,
                code: []u8,
                exception_table_length: u16,
                exception_table: []struct {
                    start_pc: u16,
                    end_pc: u16,
                    handler_pc: u16,
                    catch_type: u16,
                },
                attributes_count: u16,
                attributes: []Attribute
            },
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
        class_info: struct {
            name_index: u16,
        },
        field_ref_info: struct {
            class_index: u16,
            name_and_type_index: u16,
        },
        method_ref_info: struct {
            class_index: u16,
            name_and_type_index: u16,
        },
        interface_ref_info: struct {
            class_index: u16,
            name_and_type_index: u16,
        },
        string_info: struct {
            string_index: u16,
        },
        integer_info: struct {
            /// big-endian
            bytes: u32,
        },
        float_info: struct {
            /// IEEE 754 big-endian
            bytes: u32,
        },
        long_info: struct {
            /// big-endian
            high_bytes: u32,
            /// big-endian
            low_bytes: u32,
        },
        double_info: struct {
            /// big-endian
            high_bytes: u32,
            /// big-endian
            low_bytes: u32,
        },
        name_and_type_info: struct {
            name_index: u16,
            descriptor_index: u16,
        },
        utf_8_info: struct {
            length: u16,
            /// Some special rules:
            /// - No byte may have the value of 0
            /// - No byte may be in the range 0xf0..0xff
            ///
            /// See Section 3.9 Unicode Encoding Forms of The Unicode Standard, Version 6.0.0
            bytes: []u8,
        },
        method_handle_info: struct {
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
            descriptor_index: u16,
        },
        invoke_dynamic: u0,

        /// Encoding alongside the corresponding 'info' struct
        /// in the form of a leading byte `tag`.
        pub const Tag = enum(u8) {
            class = 7,
            field_ref = 9,
            method_ref = 10,
            interface_ref = 11,
            string = 8,
            integer = 3,
            float = 4,
            long = 5,
            double = 6,
            name_and_type = 12,
            utf_8 = 11,
            method_handle = 15,
            method_type = 16,
            invoke_dynamic = 18,
        };
    };
};
