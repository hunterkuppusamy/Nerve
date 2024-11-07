package dev.hunter.nerve.core

import dev.hunter.nerve.CanDebug
import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.core.Variable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking
import dev.hunter.nerve.core.components.Node

enum class DebugFlag {
    TIMINGS,
    STATE,
    NON_FATAL_ERRORS
}

class Interpreter(
    internal var logMethod: (String) -> Unit = { println("Script: $it") },
    var debug: EnumSet<DebugFlag> = EnumSet(),
    initialVars: Map<String, Variable> = emptyMap(),
): CanDebug {
    constructor(
        logMethod: (String) -> Unit = { println("Script: $it") },
        debug: EnumSet<DebugFlag> = EnumSet(),
        vararg initialVars: Pair<String, Variable>
    ) : this(logMethod, debug, initialVars.toMap())

    private val global = GlobalExecutionScope(this, initialVars)

    val time get() = global.time

    suspend fun suspendInterpret(nodes: Collection<Node>): Throwable? {
        var ret: Throwable? = null
        try {
            for (node in nodes) {
                global.interpret(node)
            }
        } catch (t: Throwable) {
            debug(DebugFlag.NON_FATAL_ERRORS) { "Interpretation threw an exception: ${t.message}" }
            ret = t
        }
        debug(DebugFlag.TIMINGS) { "Total interpretation time = $time" }
        return ret
    }

    fun interpret(nodes: Collection<Node>): Throwable? = runBlocking{ suspendInterpret(nodes) }

    override fun debug(flag: DebugFlag?, message: () -> String) {
        if (if (flag != null) debug.contains(flag) else debug.size > 0) logMethod("[${flag ?: "ANY"}] DEBUG: ${message()}") // lazily invoke the message, only if debugging
    }
}

class InterpretationException(msg: String? = null, cause: Throwable? = null): RuntimeException(msg, cause){
    constructor(cause: Throwable): this(null, cause)
}