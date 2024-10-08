package dev.hunter.nerve.core

class Interpreter(
    val logMethod: (String) -> Unit = { println("Script: $it") },
    var debug: Boolean = false,
    val initialVars: Map<String, Any?>
) {
    constructor(
        logMethod: (String) -> Unit = { println("Script: $it") },
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

abstract class Function{
    fun invoke(scope: ExecutionScope, args: List<Any?>): Any?{
        val local = LocalExecutionScope(scope)
        return invoke0(local, args)
    }
    protected abstract fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any?
}

const val TEMPLATE_START_CHAR = '{'
const val TEMPLATE_END_CHAR = '}'

object FunctionRegistry {
    private val _entries = HashMap<String, Function>()
    val entries: Map<String, Function> get() = _entries

    fun register(name: String, function: Function) {
        _entries[name] = function
    }

    fun register(name: String, f: (ExecutionScope, List<Any?>) -> Any?) {
        val function = object: Function() {
            override fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? = f(localScope, args)
        }
        _entries[name] = function
    }

    init {
        register("print", BuiltInFunction.Print)
    }
}

sealed class BuiltInFunction(
    val short: (ExecutionScope, List<Any?>) -> Any?
): Function() {
    override fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? = short(localScope, args)
    data object Print: BuiltInFunction({ scope, args ->
        if (args.size > 1) throw RuntimeException("Print has 1 argument, a string")
        val str = args[0]
        val ret = if (str is OfValue) scope.computeValuable(str).toString() else str.toString()
        scope.interpreter.logMethod(ret)
    })
}