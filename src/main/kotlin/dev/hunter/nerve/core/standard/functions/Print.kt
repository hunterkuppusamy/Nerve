package dev.hunter.nerve.core.standard.functions

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.function.DelegateFunction
import dev.hunter.nerve.core.components.type.NoneType
import dev.hunter.nerve.core.standard.STRING_TYPE

data object Print: DelegateFunction("print", arrayOf(STRING_TYPE), NoneType){
    override fun handle(scope: ExecutionScope, args: List<Value>): Value {
        TODO("Not yet implemented")
    }
}