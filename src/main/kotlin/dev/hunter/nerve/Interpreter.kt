package dev.hunter.nerve

class Interpreter {
    private val global = GlobalExecutionScope()

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
        info.info("Script: $ret")
    });

    override fun invoke(parentScope: ExecutionScope, args: List<Any?>): Any? {
        return m(parentScope, args)
    }
}