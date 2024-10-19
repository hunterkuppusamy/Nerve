package dev.hunter.nerve.core

/**
 * A node in the [Abstract Syntax Tree] that forms the syntax of my language.
 *
 * A node has no defined structure by itself, but the structure is formed when the [Parser]
 * constructs an implementation of [Node].
 *
 * Then, the [Interpreter] must implement some way to handle any node.
 */
interface Node

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
    override fun toString(): String = "BinaryExpression($left $operator $right)"
}

/**
 * A [Node] that describes the invocation of a function with some arguments
 */
data class FunctionInvoke(
    val function: Token.Identifier,
    val arguments: List<Node>
): Node, OfValue {
    override fun toString(): String = "FunctionInvoke(${function.name}$arguments)"
}

data class TemplateString(
    val line: List<OfValue>
): Node, OfValue{
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
    override fun invoke0(localScope: ExecutionScope, args: List<Any?>): Any? {
        for ((i, arg) in parameters.withIndex()) {
            localScope.setVar(arg, args[i])
        }
        for (node in body) {
            if (node is ReturnFunction) {
                return if (node.variable is Token.Identifier) localScope.getVar(node.variable)
                else localScope.computeValuable(node.variable)
            }
            localScope.interpret(node)
        }
        return Unit
    }
    private val cachedName = "DeclaredFunction(${function.name}[${parameters.joinToString { it.name }}])"
    override fun toString(): String = cachedName
}

/**
 * A [Node] that describes the assignment of some [variable][Token.Identifier],
 * to a value.
 */
data class VariableAssignment(
    val variable: Token.Identifier,
    val expression: OfValue
): Node {
    override fun toString(): String = "VariableAssignment(${variable} = $expression)"
}

data class IfStatement(
    val condition: OfValue, // should be a value of true or false, if not then not null
    val body: List<Node>
): Node {
    override fun toString(): String = "IfStatement(${condition} -> [${body.joinToString(", ")}])"
}

/**
 * A [Node] that describes the returning of some value in a function.
 *
 * It is possible that in the future this node ends the execution of the [GlobalExecutionScope]
 */
data class ReturnFunction(
    val variable: OfValue
): Node {
    override fun toString(): String = "ReturnFunction($variable)"
}

data object BreakStatement: Node