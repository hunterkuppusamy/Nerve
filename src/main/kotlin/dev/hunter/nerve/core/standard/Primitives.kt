package dev.hunter.nerve.core.standard

import dev.hunter.nerve.core.components.function.Function
import dev.hunter.nerve.core.components.type.Type

class Primitive(name: String) : Type(name, arrayOf(STRING_TYPE)){
    override val functions = HashMap<String, Function>()
}

val ANY_TYPE = Primitive("Any")
val BOOLEAN_TYPE = Primitive("Boolean")
val BYTE_TYPE = Primitive("Byte")
val INTEGER_TYPE = Primitive("Integer")
val LONG_TYPE = Primitive("Long")
val FLOAT_TYPE = Primitive("Float")
val DOUBLE_TYPE = Primitive("Double")
val STRING_TYPE = Primitive("String")

val PrimitiveTypes = listOf(
    BOOLEAN_TYPE,
    BYTE_TYPE,
    INTEGER_TYPE,
    LONG_TYPE,
    FLOAT_TYPE,
    DOUBLE_TYPE,
    STRING_TYPE
)