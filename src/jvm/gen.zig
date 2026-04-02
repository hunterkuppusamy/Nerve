// Backend lowering — re-exports for external consumers.
//
// The implementation is split across:
//   context.zig  — GlobalContext, FileContext, ClassContext, FunctionContext
//   import.zig   — JVM class file importing and type descriptor parsing
//   infer.zig    — Type inference from AST nodes
//   emit.zig     — Bytecode emission from AST
//   generate.zig — Top-level class generation from Type.Struct
//   disasm.zig   — Bytecode disassembler / printer

pub const GlobalContext = @import("context.zig").GlobalContext;
pub const FileContext = @import("context.zig").FileContext;
pub const ClassContext = @import("context.zig").ClassContext;
pub const FunctionContext = @import("context.zig").FunctionContext;
pub const StaticScope = @import("context.zig").StaticScope;
pub const Variable = @import("context.zig").Variable;
pub const Primitive = @import("context.zig").Primitive;

pub const generate = @import("generate.zig").generate;
pub const assembleMethodDesc = @import("generate.zig").assembleMethodDesc;

pub const bytecodeOf = @import("emit.zig").bytecodeOf;

pub const importClass = @import("import.zig").importClass;
pub const importPath = @import("import.zig").importPath;
pub const importClassName = @import("import.zig").importClassName;
pub const ImportError = @import("import.zig").ImportError;

pub const inferType = @import("infer.zig").inferType;
pub const InferError = @import("infer.zig").InferError;

pub const disasm = @import("disasm.zig");
