package dev.hunter.nerve.core

import org.jetbrains.annotations.ApiStatus
import kotlin.reflect.KClass
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.TimeSource
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
    fun invoke(scope: ExecutionScope, args: List<Any?>): Any? {
        try{
            val local = LocalExecutionScope(scope)
            val ret: Any? = invoke0(local, args)
            return ret
        }catch (t: Throwable) {
            throw RuntimeException(this.toString(), t)
        }
    }
    override fun toString(): String = "Function_${this::class.simpleName}(...)"
    protected abstract fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any?
}

abstract class DelegateFunction(
    val name: String,
    private val params: Array<out KClass<out Any>>
): Function() {
    final override fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? {
        val ret: Any?
        val elapsed = measureTime {
            for ((i, a) in args.withIndex()) {
                val p = params.getOrNull(i) ?: throw RuntimeException("Too many arguments, expected only ${params.size}")
                if (!p.isInstance(a)) throw RuntimeException("Expected argument #$i to be ${params[i].simpleName}, got ${if (a == null) "null" else a::class.simpleName}")
            }
            ret = handle(localScope, args)
        }
        localScope.time += elapsed
        return ret
    }
    abstract fun handle(scope: ExecutionScope, args: List<Any?>): Any?
    private val cachedName = "DelegatedFunction_${name}(${params.joinToString { it.simpleName ?: "null" }})"
    final override fun toString(): String = cachedName
}

object FunctionRegistry {
    private val _entries = HashMap<String, DelegateFunction>()
    val entries: Map<String, Function> get() = _entries

    fun register(function: DelegateFunction) {
        _entries[function.name] = function
    }

    fun register(name: String, params: Array<KClass<Any>>, f: (ExecutionScope, List<Any?>) -> Any?) {
        val function = object: DelegateFunction(name, params) {
            override fun handle(scope: ExecutionScope, args: List<Any?>): Any? = f(scope, args)
        }
        register(function)
    }

    init {
        register(StandardFunction.Print)
        register(StandardFunction.SystemNanoTime)
    }
}

sealed class StandardFunction(
    name: String,
    vararg params: KClass<out Any>,
    val exec: (ExecutionScope, List<Any?>) -> Any?
): DelegateFunction(name, params) {
    override fun handle(scope: ExecutionScope, args: List<Any?>): Any? = exec(scope, args)
    data object Print: StandardFunction("print", String::class, exec =
    { scope, args ->
        val str = args[0]
        val ret = if (str is OfValue) scope.computeValuable(str).toString() else str.toString()
        scope.interpreter.logMethod(ret)
    })
    data object SystemNanoTime: StandardFunction("system_currentMillis", exec =
    { _, _ ->
        System.currentTimeMillis()
    })
}