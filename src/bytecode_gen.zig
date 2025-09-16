const std = @import("std");

/// Magic
const class_format_header = 0xCAFEBABE;

pub const ClassFile = struct {
    magic: u32 = class_format_header,
    minor_version: u16,
    major_version: u16,
    constant_pool: []const Constant,
    access_flags: ClassAccessFlags,
    this_class: u16,
    super_class: u16,
    /// Array of indices of interfaces this class inherits
    interfaces: []u16,
    fields: []FieldInfo,
    methods: []const MethodInfo,
    attributes: []Attribute,

    pub const FieldAccessFlags = packed struct {
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
    };

    pub const ClassAccessFlags = packed struct {
        public: u1 = 0,
        __unused0: u3 = 0,

        final: u1 = 0,
        super: u1 = 0,
        __unused1: u2 = 0,

        __unused2: u1 = 0,
        interface: u1 = 0,
        abstract: u1 = 0,
        __unused3: u1 = 0,

        synthetic: u1 = 0,
        annotation: u1 = 0,
        @"enum": u1 = 0,
        module: u1 = 0,
    };

    pub const MethodAccessFlags = packed struct {
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
        attributes: []Attribute,
    };

    pub const Attribute = struct {
        attribute_name_index: u16,
        attribute_length: u32,
        info: union(enum) {
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
        class_info: struct {
            tag: u8 = 7,
            name_index: u16,
        },
        field_ref_info: struct {
            tag: u8 = 9,
            class_index: u16,
            name_and_type_index: u16,
        },
        method_ref_info: struct {
            tag: u8 = 10,
            class_index: u16,
            name_and_type_index: u16,
        },
        interface_ref_info: struct {
            tag: u8 = 11,
            class_index: u16,
            name_and_type_index: u16,
        },
        string_info: struct {
            tag: u8 = 8,
            string_index: u16,
        },
        integer_info: struct {
            tag: u8 = 3,
            /// big-endian
        bytes: u32,
        },
        float_info: struct {
            tag: u8 = 4,
            /// IEEE 754 big-endian
        bytes: u32,
        },
        long_info: struct {
            tag: u8 = 5,
            /// big-endian
        high_bytes: u32,
            /// big-endian
        low_bytes: u32,
        },
        double_info: struct {
            tag: u8 = 6,
            /// big-endian
        high_bytes: u32,
            /// big-endian
        low_bytes: u32,
        },
        name_and_type_info: struct {
            tag: u8 = 12,
            name_index: u16,
            descriptor_index: u16,
        },
        utf_8_info: struct {
            tag: u8 = 1,
            /// Some special rules:
            /// - No byte may have the value of 0
            /// - No byte may be in the range 0xf0..0xff
            ///
            /// See Section 3.9 Unicode Encoding Forms of The Unicode Standard, Version 6.0.0
            bytes: []const u8,
        },
        method_handle_info: struct {
            tag: u8 = 15,
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
            tag: u8 = 16,
            descriptor_index: u16,
        },
        invoke_dynamic: struct {
            tag: u8 = 18,
            // Usually includes:
            // - bootstrap_method_attr_index: u16,
            // - name_and_type_index: u16,
        },
    };
};

pub const DEBUG_SHORT: u16 = 0xdead;

test "Classfile emission" {
    var constants = [_]ClassFile.Constant{
        .{ .utf_8_info = .{ .bytes = "java/lang/Object" } },
        .{ .class_info = .{ .name_index = 1 } },
        .{ .utf_8_info = .{ .bytes = "Main" } },
        .{ .class_info = .{ .name_index = 3 } },
        .{ .utf_8_info = .{ .bytes = "Code" } },
        .{ .utf_8_info = .{ .bytes = "main" } },
        .{ .utf_8_info = .{ .bytes = "([Ljava/lang/String;)V" } },
    };
    const c = ClassFile {
        .minor_version = 0x00,
        .major_version = 65, // java 21?
        .access_flags = .{
            .public = 1,
        },
        .this_class = 4,
        .super_class = 2,
        .constant_pool = &constants,
        .fields = &[_]ClassFile.FieldInfo{},
        .methods = &[_]ClassFile.MethodInfo {
            ClassFile.MethodInfo {
                .access_flags = .{
                    .public = 1,
                    .static = 1,
                },
                .name_index = 6,
                .descriptor_index = 7,
                .attributes = &[_]ClassFile.Attribute{
                    ClassFile.Attribute {
                        .attribute_name_index = 5,
                        .attribute_length = 15,
                        .info = .{
                            .code = .{
                                .max_stack = 1,
                                .max_locals = 1,
                                .code = &[_]u8{
                                    0x12, 0x02, // Push "java/lang/Object"
                                    0xb1 // return
                                },
                                .exception_table = &[_]ClassFile.Attribute.Code.Exception{},
                                .attributes = &[_]ClassFile.Attribute{},
                            }
                        }
                    },
                },
            },
        },
        .interfaces = &[_]u16{},
        .attributes = &[_]ClassFile.Attribute{}
    };
    var buf: [64]u8 = undefined;
    var file = try std.fs.cwd().createFile("Main.class", .{.lock = .exclusive,});
    defer file.close();
    var fs = file.writer(&buf);
    try emitClassFile(&fs.interface, c);
    try fs.interface.flush();
}

test "basic file write" {
    var file = try std.fs.cwd().createFile("test_output.txt", .{});
    defer file.close();
    var buf: [64]u8 = undefined;

    var w = file.writer(&buf);
    try w.interface.writeAll("Test!");
    try w.interface.flush();
}

pub fn emitClassFile(w: *std.io.Writer, class: ClassFile) !void {
    try w.writeInt(u32, class.magic, .big);
    try w.writeInt(u16, class.minor_version, .big);
    try w.writeInt(u16, class.major_version, .big);
    var c_size: u16 = 1;
    // strange jvm quirk!
    for (class.constant_pool) |c| {
        switch (c) {
            .long_info, .double_info => c_size += 2,
            else => c_size += 1,
        }
    }
    try w.writeInt(u16, c_size, .big);
    for (class.constant_pool) |c| try emitConstant(w, c);
    const acc_flags: u16 = @bitCast(class.access_flags);
    std.debug.print("emitClassFile: Class Access Flags: {b:0>16}\n", .{acc_flags});
    try w.writeInt(u16, acc_flags, .big);
    std.debug.print("emitClassFile: This class = {s}\n", .{class.constant_pool[class.constant_pool[class.this_class - 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.this_class, .big);
    std.debug.print("emitClassFile: Super class = {s}\n", .{class.constant_pool[class.constant_pool[class.super_class -| 1].class_info.name_index - 1].utf_8_info.bytes});
    try w.writeInt(u16, class.super_class, .big);
    std.debug.print("emitClassFile: Number of interfaces {d}\n", .{class.interfaces.len});
    try w.writeInt(u16, @intCast(class.interfaces.len), .big);
    for (class.interfaces) |interface| try w.writeInt(u16, interface, .big);
    std.debug.print("emitClassFile: Number of fields {d}\n", .{class.fields.len});
    try w.writeInt(u16, @intCast(class.fields.len), .big);
    for (class.fields) |field| try emitMethodOrField(w, field);
    std.debug.print("emitClassFile: Number of methods {d}\n", .{class.methods.len});
    try w.writeInt(u16, @intCast(class.methods.len), .big);
    for (class.methods) |method| {
        std.debug.print("emitClassFile: Method Name = {s}\n", .{class.constant_pool[method.name_index - 1].utf_8_info.bytes});
        std.debug.print("emitClassFile: Method Descriptor = {s}\n", .{class.constant_pool[method.descriptor_index - 1].utf_8_info.bytes});
        try emitMethodOrField(w, method);
    }
    std.debug.print("emitClassFile: Number of attributes {d}\n", .{class.attributes.len});
    try w.writeInt(u16, @intCast(class.attributes.len), .big);
    for (class.attributes) |attr| try emitAttribute(w, attr);
}

fn emitMethodOrField(w: *std.io.Writer, m: anytype) !void {
    comptime {
        const typ = @TypeOf(m);
        if (typ != ClassFile.MethodInfo and typ != ClassFile.FieldInfo) {
            @compileError("Incorrect type." ++ @typeName(@TypeOf(m)));
        }
    }

    const acc_flags: u16 = @bitCast(m.access_flags);
    std.debug.print("emitMethodOrField: Access Flags: {b:0>16}\n", .{ acc_flags });
    try w.writeInt(u16, acc_flags, .big);
    try w.writeInt(u16, m.name_index, .big);
    try w.writeInt(u16, m.descriptor_index, .big);
    std.debug.print("emitMethodOrField: Number of attributes {any}\n", .{m.attributes.len});
    try w.writeInt(u16, @intCast(m.attributes.len), .big);
    for (m.attributes) |attribute| try emitAttribute(w, attribute);
}

fn emitAttribute(w: *std.io.Writer, a: ClassFile.Attribute) !void {
    std.debug.print("emitAttribute: Name = {d}\n", .{a.attribute_name_index});
    try w.writeInt(u16, a.attribute_name_index, .big);
    try w.writeInt(u32, a.attribute_length, .big);
    switch (a.info) {
        .constant_value_index => |c| try w.writeInt(u16, c, .big),
        .annotation_default => |an| {
            try emitAnnontationElementValue(w, an.default_value);
        },
        .bootstrap_methods => {},
        .code => |code| {
            try w.writeInt(u16, code.max_stack, .big);
            try w.writeInt(u16, code.max_locals, .big);
            try w.writeInt(u32, @intCast(code.code.len), .big);
            try w.writeAll(code.code);
            try w.writeInt(u16, @intCast(code.exception_table.len), .big);
            for (code.exception_table) |e| {
                try w.writeInt(u16, e.start_pc, .big);
                try w.writeInt(u16, e.end_pc, .big);
                try w.writeInt(u16, e.handler_pc, .big);
                try w.writeInt(u16, e.catch_type, .big);
            }
            try w.writeInt(u16, @intCast(code.attributes.len), .big);
            for (code.attributes) |attribute| try emitAttribute(w, attribute);
        },
        .deprecated => {},
        else => @panic("Unhandled Attr"),
    }
}


fn emitAnnontationElementValue(w: *std.io.Writer, e: ClassFile.Attribute.Annotation.ElementValue) !void {
    _ = e;
    _ = w;
    @panic("Annotations are unsupported");
}

fn emitConstant(w: *std.io.Writer, c: ClassFile.Constant) !void {
    switch (c) {
        .class_info => |class| {
            try w.writeByte(class.tag);
            try w.writeInt(u16, class.name_index, .big);
        },
        .double_info => |double| {
            try w.writeByte(double.tag);
            try w.writeInt(u32, double.high_bytes, .big);
            try w.writeInt(u32, double.low_bytes, .big);
        },
        .field_ref_info => |field| {
            try w.writeByte(field.tag);
            try w.writeInt(u16, field.class_index, .big);
            try w.writeInt(u16, field.name_and_type_index, .big);
        },
        .float_info => |float| {
            try w.writeByte(float.tag);
            try w.writeInt(u32, float.bytes, .big);
        },
        .integer_info => |int| {
            try w.writeByte(int.tag);
            try w.writeInt(u32, int.bytes, .big);
        },
        .interface_ref_info => |interface| {
            try w.writeByte(interface.tag);
            try w.writeInt(u16, interface.class_index, .big);
            try w.writeInt(u16, interface.name_and_type_index, .big);
        },
        .invoke_dynamic => {},
        .long_info => |long| {
            try w.writeByte(long.tag);
            try w.writeInt(u32, long.high_bytes, .big);
            try w.writeInt(u32, long.low_bytes, .big);
        },
        .method_handle_info => |handle| {
            try w.writeByte(handle.tag);
            try w.writeInt(u16, handle.reference_index, .big);
            try w.writeByte(@intFromEnum(handle.reference_kind));
        },
        .method_ref_info => |method| {
            try w.writeByte(method.tag);
            try w.writeInt(u16, method.class_index, .big);
            try w.writeInt(u16, method.name_and_type_index, .big);
        },
        .method_type_info => |typ| {
            try w.writeByte(typ.tag);
            try w.writeInt(u16, typ.descriptor_index, .big);
        },
        .name_and_type_info => |name| {
            try w.writeByte(name.tag);
            try w.writeInt(u16, name.name_index, .big);
            try w.writeInt(u16, name.descriptor_index, .big);
        },
        .string_info => |str| {
            try w.writeByte(str.tag);
            try w.writeInt(u16, str.string_index, .big);
        },
        .utf_8_info => |utf| {
            try w.writeByte(utf.tag);
            try w.writeInt(u16, @intCast(utf.bytes.len), .big);
            std.debug.print("emitConstant: utf8 = '{s}'\n", .{utf.bytes});
            try w.writeAll(utf.bytes);
        },
    }
}