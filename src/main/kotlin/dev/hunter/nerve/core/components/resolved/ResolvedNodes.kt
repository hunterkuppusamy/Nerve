package dev.hunter.nerve.core.components.resolved

import dev.hunter.nerve.core.*
import dev.hunter.nerve.core.components.*
import dev.hunter.nerve.core.components.function.Function
import dev.hunter.nerve.core.components.token.Constant
import dev.hunter.nerve.core.components.token.Identifier
import dev.hunter.nerve.core.components.token.Operator
import dev.hunter.nerve.core.components.token.Token
import dev.hunter.nerve.core.components.type.None
import dev.hunter.nerve.core.components.type.Type
import dev.hunter.nerve.core.standard.*

/**
 * A node in the [Abstract Syntax Tree] that forms the syntax of Nerve.
 *
 */
interface ResolvedNode {
    fun safeInterpret(scope: ExecutionScope): Any? =
        try { interpret(scope) }
        catch (r: FunctionReturnException) { r.value }
        catch (t: Throwable) { throw InterpretationException("Within $this", t) }
    fun interpret(scope: ExecutionScope): Value
    fun compile() {} // maybe this returns a list of instructions, not sure
}

interface Definition: ResolvedNode

/**
 * A node that could return a value when evaluated
 */
interface OfValue: ResolvedNode {
    val type: Type
}

/**
 * A [ResolvedNode] that has two sides and applies some operation to both.
 *
 * Binary expressions can be chained together, and the [Parser] does this
 * in [Parser.parseExpression] and [Parser.parseTerm]
 */
data class BinaryExpression(
    val left: OfValue,
    val operator: Operator,
    val right: OfValue
): ResolvedNode, OfValue {
    override fun toString(): String = "BinaryExpression[$left $operator $right]"
    override fun interpret(scope: ExecutionScope): Value = scope.op()

    override val type: Type =
        if (left.type == STRING_TYPE && right.type == STRING_TYPE) {
            STRING_TYPE
        } else if (left.type == FLOAT_TYPE && right.type == FLOAT_TYPE) {
            FLOAT_TYPE
        } else if (left.type == INTEGER_TYPE && right.type == INTEGER_TYPE){
            INTEGER_TYPE
        } else if (left.type == LONG_TYPE && right.type == LONG_TYPE){
            LONG_TYPE
        } else if (left.type == DOUBLE_TYPE && right.type == DOUBLE_TYPE){
            DOUBLE_TYPE
        } else {
            throw ParseException("Types dont make sense for $this (${left.type} - ${right.type})")
        }

    private val op: ExecutionScope.() -> Value =
        if (left.type == STRING_TYPE && right.type == STRING_TYPE) {{
            val v = values
            val ret = (v.first.value as String) + (v.second.value as String)
            Value(STRING_TYPE, ret)
        }} else if (left.type == FLOAT_TYPE && right.type == FLOAT_TYPE) {{
            val v = values
            val ret = (v.first.value as Float) + (v.second.value as Float)
            Value(FLOAT_TYPE, ret)
        }} else if (left.type == INTEGER_TYPE && right.type == INTEGER_TYPE){{
            val v = values
            val ret = (v.first.value as Int) + (v.second.value as Int)
            Value(INTEGER_TYPE, ret)
        }} else if (left.type == LONG_TYPE && right.type == LONG_TYPE){{
            val v = values
            val ret = (v.first.value as Long) + (v.second.value as Long)
            Value(LONG_TYPE, ret)
        }} else if (left.type == DOUBLE_TYPE && right.type == DOUBLE_TYPE){{
            val v = values
            val ret = (v.first.value as Double) + (v.second.value as Double)
            Value(DOUBLE_TYPE, ret)
        }} else {{
            throw ParseException("NO appropriate operation for ${this@BinaryExpression}")
        }}

    private val ExecutionScope.values: Pair<Value, Value> get() {
        return left.interpret(this) to right.interpret(this)
    }
}

/**
 * A [ResolvedNode] that describes the invocation of a function with some arguments
 */
data class FunctionInvocation(
    val function: Function,
    val arguments: List<ResolvedNode>
): ResolvedNode, OfValue {
    override val type: Type = function.returnType

    override fun interpret(scope: ExecutionScope): Value {
        val args = arguments.map {
            (it as OfValue).interpret(scope)
        }
        return try {
            function.invoke(scope, args)
            None
        } catch (r: FunctionReturnException) { return r.value }
    }

    override fun toString(): String = "FunctionInvoke[${function}(${arguments.joinToString { it.toString() }})]"
}

data class FunctionReturnException(val value: Value): Throwable("Unexpected return")

data class TemplateString(
    val line: List<OfValue>
): ResolvedNode, OfValue {
    override val type: Type = STRING_TYPE

    override fun interpret(scope: ExecutionScope): Value {
        var str = ""
        val i = line.iterator()
        while (i.hasNext()) {
            val value = i.next()
            str += value.safeInterpret(scope)
        }
        return Value(STRING_TYPE, str)
    }

    override fun toString(): String = "TemplateString($line)"
}

/**
 * A [ResolvedNode] that denotes the definition of a new function with an [Identifier][Token.Identifier], Parameters,
 * and a body.
 *
 * Can be [invoked][Function.invoke0] just as [built-in functions][BuiltInFunctions] can.
 */
data class FunctionDefinition(
    val function: Identifier,
    val parameters: Map<Identifier, Identifier>,
    override val returnType: Type,
    val body: List<ResolvedNode>
): Function(), Definition {
    override fun invoke0(localScope: ExecutionScope, args: List<Value>): Nothing? {
        var ret: FunctionReturnException?
        try{
            for ((i, arg) in parameters.entries.withIndex()) {
                localScope.setVar(arg.value.name, args[i])
            }
            for (node in body) {
                node.safeInterpret(localScope)
            }
            ret = null
        }catch (r: FunctionReturnException) {
            ret = r
        }
        // the interp of ReturnStatement throws, which stops the function
        val e = ret // need final variable for smart casting
        return if (e == null) null else throw e
    }
    private val cachedName = "DeclaredFunction[${function.name}(${parameters.entries.joinToString { "${it.key.name} ${it.value.name}" }})]"

    override fun interpret(scope: ExecutionScope): Value {
        scope.context.globalFunctions[function.name] = this
        return None
    }

    override fun toString(): String = cachedName
}

/**
 * A [ResolvedNode] that describes the assignment of some [variable][Token.Identifier],
 * to a value.
 */
data class VariableInitialization(
    val type: Type,
    val variable: Identifier,
    val expression: OfValue
): ResolvedNode {
    private val _cached = "VariableInitialization[$variable = $expression]"
    override fun toString(): String = _cached
    override fun interpret(scope: ExecutionScope): Value {
        val value = expression.interpret(scope)
        scope.setVar(variable.name, Value(type, value))
        return None
    }
}

data class VariableReassignment(
    val type: Type,
    val variable: Identifier,
    val expression: OfValue
): ResolvedNode {
    override fun toString(): String = "VariableReassignment[${variable} = $expression]"
    override fun interpret(scope: ExecutionScope): Value {
        val value = expression.interpret(scope)
        scope.modVar(variable.name, Value(type, value))
        return None
    }
}

data class IfTree(
    val branches: List<Branch>
): ResolvedNode {
    override fun interpret(scope: ExecutionScope): Value {
        for (branch in branches) {
            val brk = branch.interpret(scope)
            if (brk) break
        }
        return None
    }

    private val cached = "IfTree[${branches.joinToString()}]"
    override fun toString(): String = cached

    data class Branch(
        val condition: OfValue, // should be a value of true or false, if not then not null
        val body: List<ResolvedNode>
    ){
        private val constant: Boolean? = if (condition is Constant) {
            if (condition.variable.type == BOOLEAN_TYPE) condition.variable.value as Boolean
            else throwCannotEvaluate
        } else null

        fun interpret(scope: ExecutionScope): Boolean {
            val op = constant ?: run {
                val value = condition.interpret(scope).value
                value as? Boolean ?: throwCannotEvaluate
            }
            if (op) {
                for (line in body) {
                    if (line is BreakStatement) break
                    line.interpret(scope)
                }
            }
            return op
        }

        private val throwCannotEvaluate: Nothing get() = throw ParseException("Expression $condition does not make sense or evaluate to true or false")
    }
}

/**
 * A [ResolvedNode] that describes the returning of some value in a section.
 *
 * It is possible that in the future this node ends the execution of the [GlobalExecutionScope]
 * when executed outside any function or class
 */
data class ReturnStatement(
    val variable: OfValue
): ResolvedNode {
    override fun interpret(scope: ExecutionScope): Value = throw FunctionReturnException(variable.interpret(scope))
    override fun toString(): String = "ReturnFunction[$variable]"
}

data class ForLoop(
    val type: Type,
    val index: Identifier,
    val expression: OfValue,
    val body: List<ResolvedNode>
): ResolvedNode {
    override fun interpret(scope: ExecutionScope): Value {
        val res = expression.interpret(scope).value
        var first = true
        val iter = (res as Iterable<*>).iterator()
        while (iter.hasNext()) {
            val i = iter.next()
            if (first) {
                scope.setVar(index.name, Value(type, i))
                first = false
            }
            else scope.modVar(index.name, Value(type, i))
            bdy(scope)
        }
        return None
    }

    private fun bdy(scope: ExecutionScope) {
        for (line in body){
            if (line is BreakStatement) break
            line.interpret(scope)
        }
    }

    override fun toString(): String = "ForLoop[$index in $expression -> {${body.joinToString(", ")}}]"
}

data object BreakStatement: ResolvedNode {
    override fun interpret(scope: ExecutionScope): Value = None
}

class TypeDefinition(
    identifier: Identifier,
    parents: Array<out Type>
): Type(identifier.name, parents), Definition {

    override fun interpret(scope: ExecutionScope): Value {
        scope.context.types.add(this)
        return None
    }

    override val functions: MutableMap<String, Function> = HashMap() // always empty for now
}

class FreeVariable(
    val name: Identifier
): ResolvedNode {
    override fun interpret(scope: ExecutionScope): Value {
        if (scope.variables.remove(name.name) == null) throw InterpretationException("Freeing of '$name' failed, it was never defined")
        return None
    }

    override fun toString(): String = "FreeVariable[${name.name}]"
}