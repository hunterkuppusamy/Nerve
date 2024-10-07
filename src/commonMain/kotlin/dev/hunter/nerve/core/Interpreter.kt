package dev.hunter.nerve.core

import dev.hunter.nerve.logger

class Interpreter(
    val logMethod: (String) -> Unit = { println(it) },
    var debug: Boolean = false,
    val initialVars: Map<String, Any?>
) {
    constructor(
        logMethod: (String) -> Unit = { println(it) },
        debug: Boolean = false,
        vararg initialVars: Pair<String, Any?>
    ) : this(logMethod, debug, initialVars.toMap())

    private val global = GlobalExecutionScope(this)

    val time get() = global.time

    fun interpret(nodes: Collection<Node>){
        for (node in nodes){
            global.interpret(node)
        }
    }
}

interface Function{
    fun invoke(parentScope: ExecutionScope, args: List<Any?>): Any?
}

const val TEMPLATE_START_CHAR = '{'
const val TEMPLATE_END_CHAR = '}'

enum class BuiltInFunctions(val m: (ExecutionScope, List<Any?>) -> Any?): Function {
    PRINT({ scope, args ->
        if (args.size > 1) throw RuntimeException("Print has 1 argument, a string")
        val str = args[0]
        val ret = if (str is OfValue) scope.computeValuable(str).toString() else str.toString()
        scope.interpreter.logMethod("Script: $ret")
    });

    override fun invoke(parentScope: ExecutionScope, args: List<Any?>): Any? {
        return m(parentScope, args)
    }
}