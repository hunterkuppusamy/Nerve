package dev.hunter.nerve.core.components

import dev.hunter.nerve.Nerve
import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.InterpretationException
import dev.hunter.nerve.core.LocalExecutionScope
import org.jetbrains.annotations.ApiStatus
import kotlin.reflect.KClass
import kotlin.time.measureTime

/**
 * Do not extend or use this class for Function Registration
 *
 * Extend [DelegateFunction] and override [DelegateFunction.handle]
 *
 * Then, register your function in the [FunctionRegistry] with [FunctionRegistry.register]
 *
 * @see DelegateFunction
 */
@ApiStatus.Internal
@ApiStatus.NonExtendable
abstract class Function{
    suspend fun invoke(scope: ExecutionScope, args: List<Any?>): Any? {
        try{
            return LocalExecutionScope(scope).use {
                val ret: Any? = invoke0(it, args)
                ret
            }
        }catch (t: Throwable) {
            throw InterpretationException("Within $this", t)
        }
    }
    override fun toString(): String = "Function[${this::class.simpleName}(...)]"
    protected abstract suspend fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any?
}

abstract class DelegateFunction(
    val name: String,
    val params: Array<out KClass<out Any>>
): Function() {
    final override suspend fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? {
        for ((i, a) in args.withIndex()) {
            val p = params.getOrNull(i) ?: throw InterpretationException("Too many arguments, expected only ${params.size}")
            if (!p.isInstance(a)) throw InterpretationException("Expected argument #$i to be ${params[i].simpleName}, got ${if (a == null) "null" else a::class.simpleName}")
        }
        return handle(localScope, args)
    }
    abstract suspend fun handle(scope: ExecutionScope, args: List<Any?>): Any?
    private val cachedName = "DelegatedFunction[$name(${params.joinToString { it.simpleName ?: "Anonymous Object" }})]"
    final override fun toString(): String = cachedName
}

sealed class StandardFunction(
    name: String,
    vararg params: KClass<out Any>,
    val exec: suspend (ExecutionScope, List<Any?>) -> Any?
): DelegateFunction(name, params) {
    override suspend fun handle(scope: ExecutionScope, args: List<Any?>): Any? = exec(scope, args)
    data object Print: StandardFunction("print", Any::class, exec =
    { scope, args ->
        val str = args.getOrNull(0)
        val ret = if (str is OfValue) str.interpret(scope).toString() else str?.toString() ?: ""
        scope.interpreter.logMethod(ret)
    })
    data object SystemCurrentMillis: StandardFunction("system_currentMillis", exec =
    { _, _ ->
        System.currentTimeMillis()
    })
    data object SystemNanoTime: StandardFunction("system_nanoTime", exec =
    {_ , _ ->
        System.nanoTime()
    })
    data object RunNerve: StandardFunction("nerve_run", String::class, exec =
    {scope, args ->
        val string = args.getOrNull(0) ?: throw InterpretationException("Missing parameter 1")
        Nerve.run((string as String).toCharArray())
    })
}