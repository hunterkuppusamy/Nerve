package dev.hunter.nerve.core

import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.core.components.*
import dev.hunter.nerve.core.components.Function
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.measureTime

@Suppress("MemberVisibilityCanBePrivate")
abstract class ExecutionScope: AutoCloseable {
    /**
     * All variables[Variable] within this scope
     * @see LocalExecutionScope.variables
     * @see GlobalExecutionScope.variables
     */
    internal abstract val variables: HashMap<String, Variable>

    /**
     * All functions[Function] within this scope
     * @see LocalExecutionScope.functions
     * @see GlobalExecutionScope.functions
     */
    internal abstract val functions: HashMap<String, Function>

    /**
     * A reference to the global scope
     */
    abstract val global: GlobalExecutionScope

    /**
     * Whether the scope should log debug information
     */
    abstract val debug: EnumSet<DebugFlag>

    open val interpreter: Interpreter get() = global.interpreter

    /**
     * Total execution time in ms
     */
    var time: Duration = 0.nanoseconds

    /**
     * Interpret a [Node]
     */
    suspend fun interpret(node: Node){
        val elapsed = measureTime {
            node.interpret(this)
        }
        interpreter.debug(DebugFlag.TIMINGS) { "Node $node took $elapsed" }
        time += elapsed
    }

    fun setVar(id: Token.Identifier, value: Any?, mutable: Boolean){
        variables[id.name] = Variable(id.name, value, mutable)
    }

    fun getVar(id: Token.Identifier): Variable {
        if (!variables.containsKey(id.name)) throw InterpretationException("#${id.line} -> Variable '${id.name}' is not defined'")
        val ret = variables[id.name]
        return ret!!
    }

    fun getValueOf(id: Token.Identifier): Any? {
        val variable = getVar(id)
        return variable.value
    }

    fun getVarOrNull(id: Token.Identifier): Any? {
        return variables[id.name]
    }

    override fun close() {
        variables.clear()
        // dont clear functions as those are defined globally
    }
}

class GlobalExecutionScope(
    override val interpreter: Interpreter,
    initVariables: Map<String, Variable>
) : ExecutionScope() {
    override val variables: HashMap<String, Variable> = HashMap(initVariables)
    override val functions: HashMap<String, Function> = HashMap(FunctionRegistry.entries)
    override val global: GlobalExecutionScope = this
    override val debug: EnumSet<DebugFlag> get() = interpreter.debug
}

class LocalExecutionScope(
    private val parent: ExecutionScope,
): ExecutionScope() {
    override val variables: HashMap<String, Variable> = HashMap(parent.variables)

    /**
     * Functions are not changed within anything but the global scope
     * @see [ExecutionScope.functions]
     */
    override val functions: HashMap<String, Function> get() = parent.functions
    override val global = parent.global
    override val debug = parent.debug
}

data class Variable(
    val identifier: String,
    var value: Any?,
    val mutable: Boolean
)