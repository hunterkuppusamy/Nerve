package dev.hunter.nerve.core.components.function

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.InterpretationException
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.resolved.FunctionReturnException
import dev.hunter.nerve.core.components.type.Type
import org.jetbrains.annotations.ApiStatus

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
    /**
     * Functions do not return normally, they throw exceptions to stop all further code execution
     * This is not the best approach, but it also is not that bad.
     */
    fun invoke(scope: ExecutionScope, args: List<Value>): Nothing? {
        try {
            invoke0(scope, args)
            return null
        }catch(r: FunctionReturnException) {
            throw r
        }catch (t: Throwable) {
            throw InterpretationException("Within $this", t)
        }
    }

    abstract val returnType: Type

    override fun toString(): String = "Function[${this::class.simpleName}(...)]"
    protected abstract fun invoke0(localScope: ExecutionScope, args: List<Value>): Nothing?
}