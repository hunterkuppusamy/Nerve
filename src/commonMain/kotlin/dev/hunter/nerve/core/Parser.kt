package dev.hunter.nerve.core

import dev.hunter.nerve.CanDebug
import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.platform

/**
 * TODO for improving this version of the parser.
 * I think creating an entirely new parser is too high level for me, for now
 *
 * 1. Improve the `consume()` function, and maybe introduce a reified type parameter because there is a lot of one line conditional type checking
 *      This probably shouldn't affect the large when trees
 *
 * 2.
 */
class Parser(
    private val tokens: Array<Token>,
    private val debug: EnumSet<DebugFlag> = EnumSet()
): CanDebug {
    private var currentIndex = 0
    private val current: Token? get() {
        val ret = tokens.getOrNull(currentIndex)
        return ret
    }
    private val nodes = ArrayList<Node>()

    private fun consume(): Token? {
        val ret = current
        currentIndex++
        return ret
    }

    /*
     * Parses the [tokens] into a collection of [nodes][Node].
     *
     * These nodes make up the hierarchy that is the syntax of my language.
     *
     * Nodes are interpreted by the [Interpreter] to provide functionality
     */
    fun parse(): Collection<Node> {
        do {
            if (debug.contains(DebugFlag.STATE)){
                println("starting new statement at -> #${current?.line} ${current.toString()}")
            }
            val node = parseStatement()
            nodes.add(node)
        } while (currentIndex < tokens.size)
        return nodes
    }

    private fun parseStatement(): Node {
        when (val token = current){
            is Token.Identifier -> {
                consume() // consume id
                when (val next = current){
                    is Operator.Assign -> {
                        consume() // consume assignment
                        val expr = parseExpression()
                        if (expr !is OfValue) throwParseException("Expected yielding expression for variable assignment")
                        return VariableAssignment(token, expr)
                    }
                    is Operator -> {
                        consume() // consume assignment
                        val expr = parseExpression()
                        if (expr !is OfValue) throwParseException("Expected yielding value for variable modification")
                        return BinaryExpression(token, next, expr)
                    }
                    is Separator.LeftParen -> {
                        return parseFunctionInvocation(token)
                    }
                    else -> throwParseException("Expected an operator or parenthesis after an identifier")
                }
            }
            is Keyword.Fun -> {
                consume() // keyword
                val identifier = current as? Token.Identifier ?: throwParseException("Expected identifier after function declaration: $token")
                consume() // id
                if (current !is Separator.LeftParen) throwParseException("Expected left parenthesis for parameters of function: $token")
                consume() // left paren
                val params = ArrayList<Token.Identifier>()
                do {
                    val right = current
                    if (right !is Token.Identifier) throwParseException("Expected identifier in parameters of function: $identifier -> got $right")
                    params.add(right)
                    consume() // last param
                    val comma = consume()
                    if (comma is Separator.RightParen) break
                    if (comma !is Separator.Comma) throwParseException("Expected comma after parameter '$right' in function declaration: $identifier")
                } while (true)
                return FunctionDefinition(identifier, params, parseBody("function ${identifier.name} at line ${identifier.line}"))
            }
            is Keyword.Return -> {
                consume() // return
                val value = parseExpression()
                if (value !is OfValue) throwParseException("Expected some value after return")
                return ReturnFunction(value)
            }
            is Keyword.If -> {
                consume() // if
                val left = consume()
                if (left !is Separator.LeftParen) throwParseException("Expected left paren to start IF expression: $left")
                val condition = parseExpression()
                val right = consume()
                if (right !is Separator.RightParen) throwParseException("Expected right paren to end IF expression: $right")
                if (condition !is OfValue) throwParseException("Expected condition to return true or false")
                return IfStatement(condition, parseBody("If statement at line #${token.line}"))
            }
            // do I need this? Do I want to support it?
            // is OfValue -> return parseValuable()
            else -> throwParseException("Unhandled token: $token")
        }
    }

    private fun parseBody(function: String): List<Node> {
        val left = consume() // left paren
        if (left !is Separator.LeftBrace) throwParseException("Expected left brace to start body: $left")
        try {
            val body = ArrayList<Node>()
            do {
                val next = current
                // handle empty function body
                if (next is Separator.RightBrace) break
                val line = parseStatement()
                body.add(line)
            } while (true)
            consume() // right brace
            return body
        }catch (p: ParseException) {
            throwParseException(function, p)
        }
    }


    private fun parseExpression(): Node {
        var left = parseTerm()

        while (true) {
            val token = current
            if (token is Operator) {
                consume() // Consume the operator
                val right = parseTerm()
                if (right !is OfValue) throwParseException("Right side of expression does not yield a result")
                if (left !is OfValue) throwParseException("Right side of expression does not yield a result")
                left = BinaryExpression(left, token, right)
            } else {
                break
            }
        }

        return left
    }

    private fun parseTerm(): Node {
        var left = parseValuable()

        while (true) {
            val token = current
            if (token is Operator) {
                consume() // Consume the operator
                val right = parseValuable()
                left = BinaryExpression(left, token, right)
            } else {
                break
            }
        }

        return left
    }

    private fun parseValuable(): OfValue {
        return when (val token = current){
            is Token.StringTemplate -> {
                consume() // template
                val values = ArrayList<OfValue>()
                for (piece in token.tokens) {
                    when (piece) {
                        is Array<*> -> {
                            val node = Parser(
                                piece as? Array<Token>
                                    ?: throw IllegalStateException("Somehow there is an array of something other than tokens: ${piece::class.simpleName}"),
                                debug
                            ).parseExpression()
                            if (node !is OfValue) throwParseException("Expression in string template does not have a value: $node")
                            values.add(node)
                        }
                        is OfValue -> values.add(piece)
                        // is String -> values.add(Token.StringLiteral(token.line, piece))
                        else -> throw IllegalArgumentException("arr = [$piece] : ${piece::class.simpleName}")
                    }
                }
                TemplateString(values)
            }
            is Constant -> {
                consume()
                token
            }
            is Token.Identifier -> {
                consume() // id
                when (current){
                    is Separator.LeftParen -> {
                        return parseFunctionInvocation(token)
                    }
                    else -> token
                }
            }
            is Keyword.Null -> {
                consume()
                token
            }
            else -> throwParseException("Unhandled valuable: $token")
        }
    }

    private fun parseFunctionInvocation(id: Token.Identifier): FunctionInvoke {
        consume() // left paren
        val args = ArrayList<OfValue>()
        do {
            val cur = current
            if (cur is Separator.RightParen) {
                consume()
                break
            } // handle no arg function
            val arg = parseExpression()
            val comma = consume()
            if (arg !is OfValue) throwParseException("Expected expression in arguments of function $id")
            args.add(arg)
            if (comma is Separator.RightParen) break
            if (comma !is Separator.Comma) throwParseException("Expected comma to delimit arguments in function $id")
        } while (true)
        return FunctionInvoke(id, args)
    }

    private fun throwParseException(msg: String, cause: Throwable? = null): Nothing {
        throw ParseException("At line #${current?.line} -> $msg", cause)
    }

    override fun debug(flag: DebugFlag?, message: () -> String) {
        if (if (flag != null) debug.contains(flag) else debug.size > 0) platform.logger.info("[${flag ?: "ANY"}] DEBUG: ${message()}") // lazily invoke the message, only if debugging
    }
}

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
): Node, OfValue

/**
 * A [Node] that describes the invocation of a function with some arguments
 */
data class FunctionInvoke(
    val function: Token.Identifier,
    val arguments: List<Node>
): Node, OfValue

data class TemplateString(
    val line: List<OfValue>
): Node, OfValue

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
    private val cachedName = "DeclaredFunction_${function.name}(${parameters.joinToString { it.name }})"
    override fun toString(): String = cachedName
}

/**
 * A [Node] that describes the assignment of some [variable][Token.Identifier],
 * to a value.
 */
data class VariableAssignment(
    val variable: Token.Identifier,
    val expression: OfValue
): Node

data class IfStatement(
    val condition: OfValue, // should be a value of true or false, if not then not null
    val body: List<Node>
): Node

/**
 * A [Node] that describes the returning of some value in a function.
 *
 * It is possible that in the future this node ends the execution of the [GlobalExecutionScope]
 */
data class ReturnFunction(
    val variable: OfValue
): Node

object BreakStatement: Node

class ParseException(message: String, override val cause: Throwable?) : Exception(message)