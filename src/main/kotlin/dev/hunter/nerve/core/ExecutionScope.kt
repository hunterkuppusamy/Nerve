package dev.hunter.nerve.core

import dev.hunter.nerve.Nerve
import dev.hunter.nerve.NerveContext
import dev.hunter.nerve.core.components.*
import dev.hunter.nerve.core.components.resolved.OfValue
import dev.hunter.nerve.core.components.token.Identifier
import dev.hunter.nerve.core.components.type.Type
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds

@Suppress("MemberVisibilityCanBePrivate")
class ExecutionScope(
    val context: NerveContext = Nerve.globalContext,
    initialVars: Map<String, Variable>
): AutoCloseable {

    /**
     * All [variables][Variable] within this scope
     * @see LocalExecutionScope.variables
     * @see GlobalExecutionScope.variables
     */
    internal val variables = HashMap<String, Variable>(initialVars)

    /**
     * Total execution time in ms
     */
    var time: Duration = 0.nanoseconds

    fun modVar(id: String, value: Any?) {
        val variable = getVar(id)
        variable.value.value = value
    }

    fun setVar(id: String, value: Value) {
        val vari = Variable(id, value)
        println("$vari")
        variables[id] = vari
    }

    fun getVar(id: String): Variable {
        return variables[id] ?: throw InterpretationException("$id is undefined somehow")
    }

    override fun close() {
        // eventually i want a dedicated node to be added during parsing (after resolveNodes)
        // to clear a variable, like rust lifetimes for local variables
        variables.clear()
        // dont clear functions as those are defined globally
    }
}

class GetVariable(
    override val type: Type,
    val identifier: Identifier
): OfValue {
    override fun interpret(scope: ExecutionScope): Value = scope.getVar(identifier.name).value

    override fun toString(): String = "GetVar[${type.name} ${identifier.name}]"
}

class Variable(
    val identifier: String,
    val value: Value
): OfValue {
    override val type: Type = value.type
    override fun interpret(scope: ExecutionScope): Value = value
    override fun toString(): String = "Var[$identifier = ${type.name} $value]"
}

open class Value(
    val type: Type,
    var value: Any?
)