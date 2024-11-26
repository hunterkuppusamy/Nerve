package dev.hunter.nerve.core.components.function

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.InterpretationException
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.resolved.FunctionReturnException
import dev.hunter.nerve.core.components.type.Type

abstract class DelegateFunction(
    val name: String,
    val params: Array<out Type>,
    override val returnType: Type
): Function() {
    constructor(name: String, returnType: Type, vararg params: Type) : this(name, params, returnType)

    final override fun invoke0(localScope: ExecutionScope, args: List<Value>): Nothing? {
        for ((i, a) in args.withIndex()) {
            val p = params.getOrNull(i) ?: throw InterpretationException("Too many arguments, expected only ${params.size}")
            if (!p.isInstance(a)) throw InterpretationException("Expected argument #$i to be '${params[i].name}', got '${a.type.name}'")
        }
        val ret = handle(localScope, args)
        return if (ret.value == null) null else throw FunctionReturnException(ret)
    }

    abstract fun handle(scope: ExecutionScope, args: List<Value>): Value
    private val cachedName = "DelegatedFunction[$name(${params.joinToString { it.name }})]"
    final override fun toString(): String = cachedName
}