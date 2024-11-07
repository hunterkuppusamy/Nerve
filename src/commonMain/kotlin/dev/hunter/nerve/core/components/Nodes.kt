package dev.hunter.nerve.core.components

import dev.hunter.nerve.core.*
import kotlin.math.pow
import kotlin.math.sign

import kotlin.time.measureTime

/**
 * A node in the [Abstract Syntax Tree] that forms the syntax of Nerve.
 *
 */
interface Node {
    suspend fun interpret(scope: ExecutionScope): Any?
    fun compile() {} // maybe this returns a list of instructions, not sure
}

/**
 * Like kotlin's [Unit] and java's [Void], but for Nerve
 */
object None

/**
 * A node that could return a value when evaluated
 */
interface OfValue: Node

/**
 * A [Node] that has two sides and applies some operation to both.
 *
 * Binary expressions can be chained together, and the [Parser] does this
 * in [Parser.parseExpression] and [Parser.parseTerm]
 */
data class BinaryExpression(
    val left: OfValue,
    val operator: Operator,
    val right: OfValue
): Node, OfValue {
    override fun toString(): String = "BinaryExpression[$left $operator $right]"
    private val operation: suspend BinaryExpression.(ExecutionScope) -> Any = run {
        when (val op = operator) {
            is Operator.Add -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble() + right.toDouble()
                    } else if (left is String && right is String) {
                        left + right
                    } else throw InterpretationException("Binary operands $left or $right is not a number or string")
                }
            }
            is Operator.Subtract -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble() - right.toDouble()
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.Multiply -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble() * right.toDouble()
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.Divide -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble() / right.toDouble()
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.Exponentiate -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble().pow(right.toDouble())
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.IsEqual -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    left == right
                }
            }
            is Operator.Modulate -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Number && right is Number) {
                        left.toDouble().mod(right.toDouble())
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.IsLessThan -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Comparable<*> && right is Comparable<*>) {
                        (left as Comparable<Any>).compareTo(right).sign == -1
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            is Operator.IsNotEqual -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    left != right
                }
            }
            is Operator.Range -> {
                {
                    val left = left.interpret(it)
                    val right = right.interpret(it)
                    if (left is Double && right is Double) {
                        left.toDouble()..right.toDouble()
                    } else if (left is Number && right is Number){
                        left.toInt()..right.toInt()
                    } else throw InterpretationException("Binary operands $left or $right is not a number")
                }
            }
            else -> throw ParseException("Unhandled operator $op") // parse exception because init{...} for BinaryExpression is during parsing
        }
    }
    override suspend fun interpret(scope: ExecutionScope): Any? {
        return operation(scope)
    }
}

/**
 * A [Node] that describes the invocation of a function with some arguments
 */
data class FunctionInvocation(
    val function: Token.Identifier,
    val arguments: List<Node>
): Node, OfValue {
    override suspend fun interpret(scope: ExecutionScope): Any? {
        val args = arguments.map {
            if (it is OfValue) it.interpret(scope)
            else throw InterpretationException("Invoked with wrong parameters? Parse error? $this")
        }
        val func = scope.functions[function.name] ?: throw InterpretationException("Function '${function.name}' is undefined")
        return func.invoke(scope, args)
    }

    override fun toString(): String = "FunctionInvoke[${function.name}(${arguments.joinToString { it.toString() }})]"
}

data class TemplateString(
    val line: List<OfValue>
): Node, OfValue {
    override suspend fun interpret(scope: ExecutionScope): Any? {
        var str = ""
        val i = line.iterator()
        while (i.hasNext()) {
            val value = i.next()
            str += value.interpret(scope)
        }
        return str
    }

    override fun toString(): String = "TemplateString($line)"
}

/**
 * A [Node] that denotes the definition of a new function with an [Identifier][Token.Identifier], Parameters,
 * and a body.
 *
 * Can be [invoked][Function.invoke0] just as [built-in functions][BuiltInFunctions] can.
 */
data class FunctionDefinition(
    val function: Token.Identifier,
    val parameters: List<Token.Identifier>,
    val body: List<Node>
): Function(), Node {
    override suspend fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? {
        localScope.interpreter.debug { "Function ${function.name}" }
        val elap = measureTime{
            for ((i, arg) in parameters.withIndex()) {
                localScope.variables[arg.name] = Variable(arg.name, args[i], false)
            }
            for (node in body) {
                if (node is ReturnStatement) { // currently return cannot propogate through sections, ie an If Statement
                    return if (node.variable is Token.Identifier) localScope.getValueOf(node.variable)
                    else node.variable.interpret(localScope)
                }
                node.interpret(localScope)
            }
        }
        localScope.interpreter.debug(DebugFlag.TIMINGS) { "Time to compute function '${function.name}(${args.joinToString { "'" + it.toString() + "'" }})' was $elap" }
        return None
    }
    private val cachedName = "DeclaredFunction[${function.name}(${parameters.joinToString { it.name }})]"

    override suspend fun interpret(scope: ExecutionScope): Any? {
        scope.functions[function.name] = this
        return None
    }

    override fun toString(): String = cachedName
}

/**
 * A [Node] that describes the assignment of some [variable][Token.Identifier],
 * to a value.
 */
data class VariableInitialization(
    val variable: Token.Identifier,
    val expression: OfValue,
    val mutable: Boolean
): Node {
    private val _cached = "VariableInitialization[${if (mutable) "var*" else "var"} ${variable} = $expression]"
    override fun toString(): String = _cached
    override suspend fun interpret(scope: ExecutionScope): Any? {
        val value = expression.interpret(scope)
        scope.variables[variable.name] = Variable(variable.name, value, mutable)
        return None
    }
}

data class VariableReassignment(
    val variable: Token.Identifier,
    val expression: OfValue
): Node {
    override fun toString(): String = "VariableReassignment[${variable} = $expression]"
    override suspend fun interpret(scope: ExecutionScope): Any? {
        val value = expression.interpret(scope)
        val variable = scope.variables[variable.name] ?: throw InterpretationException("(At #${variable.line}) Variable $variable is undefined")
        variable.value = value
        return None
    }
}

data class IfStatement(
    val condition: OfValue, // should be a value of true or false, if not then not null
    val body: List<Node>
): Node {
    override suspend fun interpret(scope: ExecutionScope): Any? {
        var op =
            // optimised evaluation of literals
            if ((condition as? Constant.NaturalLiteral)?.value == 1L || (condition as? Constant.BooleanLiteral)?.value == true) true
            else {
                val value = condition.interpret(scope)
                value as? Boolean ?: (value as? Number == 1)
            }
        if (op) {
            for (line in body) {
                if (line is BreakStatement) break
                line.interpret(scope)
            }
        }
        return None
    }

    override fun toString(): String = "IfStatement[${condition} -> {${body.joinToString(", ")}}]"
}

/**
 * A [Node] that describes the returning of some value in a section.
 *
 * It is possible that in the future this node ends the execution of the [GlobalExecutionScope]
 */
data class ReturnStatement(
    val variable: OfValue
): Node {
    override suspend fun interpret(scope: ExecutionScope): Any? = variable.interpret(scope)
    override fun toString(): String = "ReturnFunction[$variable]"
}

data class ForLoop(
    val index: Token.Identifier,
    val expression: OfValue,
    val body: List<Node>
): Node {
    override suspend fun interpret(scope: ExecutionScope): Any? {
        val res = expression.interpret(scope)
        val local = LocalExecutionScope(scope)
        var first = true
        when (res) {
            is Iterable<*> -> {
                val iter = res.iterator()
                while (iter.hasNext()) {
                    val i = iter.next()
                    if (first) {
                        local.setVar(index, i, false)
                        first = false
                    }
                    else local.getVar(index).value = i
                    bdy(local)
                }
            }
            null -> throw InterpretationException("Expression in for loop is null")
            else -> throw InterpretationException("Unhandled expression in for loop: $res of type ${res::class.simpleName}")
        }
        return None
    }

    private suspend fun bdy(scope: ExecutionScope) {
        for (line in body){
            if (line is BreakStatement) break
            line.interpret(scope)
        }
    }

    override fun toString(): String = "ForLoop[$index in $expression -> {${body.joinToString(", ")}}]"
}

data object BreakStatement: Node {
    override suspend fun interpret(scope: ExecutionScope): Any? = None
}