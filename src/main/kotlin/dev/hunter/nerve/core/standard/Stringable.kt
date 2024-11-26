package dev.hunter.nerve.core.standard

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.function.DelegateFunction
import dev.hunter.nerve.core.components.function.Function
import dev.hunter.nerve.core.components.type.Type

object Stringable: Type("Stringable", arrayOf()) {
    override val functions: MutableMap<String, Function> = mutableMapOf(
        "toString" to StringableFunction
    )

    object StringableFunction: DelegateFunction("toString", STRING_TYPE, (Stringable)){
        override fun handle(scope: ExecutionScope, args: List<Value>): Value {
            return Value(STRING_TYPE, args[0].value.toString())
        }
    }
}