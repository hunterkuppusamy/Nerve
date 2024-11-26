package dev.hunter.nerve.core

import dev.hunter.nerve.Contextual
import dev.hunter.nerve.Nerve
import dev.hunter.nerve.NerveContext
import dev.hunter.nerve.core.components.resolved.Definition
import dev.hunter.nerve.core.components.resolved.FunctionReturnException

enum class Flag {

    DEBUG_TIMING,
    DEBUG_STATE_CHANGE,
    DEBUG_ERRORS
}

class Interpreter(
    context: NerveContext = Nerve.globalContext,
    val script: NodeScript,
    initialVars: Map<String, Variable> = emptyMap(),
): Contextual(context) {

    constructor(
        context: NerveContext = Nerve.globalContext,
        script: NodeScript,
        vararg initialVars: Pair<String, Variable>
    ) : this(context, script, initialVars.toMap())

    private val scope = ExecutionScope(context, initialVars)

    val time get() = scope.time

    fun interpret(): Throwable? {
        var ret: Throwable? = null
        for (node in script.nodes) {
            if (node !is Definition) continue
            println("Interpreted definition $node")
            node.interpret(scope)
        }
        try {
            for (node in script.nodes) {
                if (node is Definition) continue
                node.interpret(scope)
            }
        } catch (r: FunctionReturnException){
            throw InterpretationException("Unexpected function return", r)
        } catch (t: Throwable) {
            context.logger.debug(Flag.DEBUG_ERRORS) { "Interpretation threw an exception: ${t.message}" }
            ret = t
        }
        Nerve.globalContext.logger.debug(Flag.DEBUG_TIMING) { "Total interpretation time = $time" }
        return ret
    }
}

class InterpretationException(msg: String? = null, cause: Throwable? = null): RuntimeException(msg, cause){
    constructor(cause: Throwable): this(null, cause)
}