package dev.hunter.nerve.core

class Parser(
    private val tokens: Array<Token>,
    val debug: Boolean = false
) {
    private var currentIndex = 0
    private val current: Token? get() {
        val ret = tokens.getOrNull(currentIndex)
        return ret
    }
    val nodes = ArrayList<Node>()

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
            if (debug){
                println("starting new statement at -> #${current?.line} ${current.toString()}")
            }
            val node = parseStatement()
            nodes.add(node)
        } while (currentIndex < tokens.size)
        return nodes
    }

    private fun parseStatement(): Node {
        when (val entry = current){
            is Token.Identifier -> {
                consume() // consume id
                when (val next = current){
                    is Token.Equals -> {
                        consume() // consume assignment
                        val expr = parseExpression()
                        if (expr !is OfValue) throwParseException("Expected yielding expression for variable assignment")
                        return VariableAssignment(entry, expr)
                    }
                    is Token.Operator -> {
                        when (next.kind){
                            OperatorKind.ADD -> {
                                consume() // consume assignment
                                val expr = parseExpression()
                                if (expr !is OfValue) throwParseException("Expected yielding value for variable modification")
                                return BinaryExpression(entry, next.kind, expr)
                            }
                            else -> throwParseException("Unhandled operator: $next")
                        }
                    }
                    is Token.Separator -> {
                        when (next.kind){
                            SeparatorKind.LEFT_PAREN -> {
                                consume() // left paren
                                val params = ArrayList<OfValue>()
                                do {
                                    if (current == null || current is Token.Separator) break
                                    val thing = parseExpression()
                                    if (thing !is OfValue) throwParseException("Expected yielding expression for function argument")
                                    params.add(thing)
                                } while (true)
                                consume() // right paren
                                return FunctionInvoke(entry, params)
                            }
                            else -> throwParseException("Expected left parenthesis for function invocation: $next")
                        }
                    }
                    else -> throwParseException("Unhandled identifier: $next")
                }
            }
            is Token.Keyword -> {
                when (entry.kind){
                    KeywordKind.FUN -> {
                        consume() // keyword
                        val identifier = current as? Token.Identifier ?: throwParseException("Expected identifier after function declaration: $entry")
                        consume() // id
                        if ((current as? Token.Separator)?.kind != SeparatorKind.LEFT_PAREN) throwParseException("Expected left parenthesis for parameters of function: $entry")
                        consume() // left paren
                        val params = ArrayList<Token.Identifier>()
                        var right = current
                        while ((right !is Token.Separator) || right.kind != SeparatorKind.RIGHT_PAREN){
                            if (right !is Token.Identifier) throwParseException("Expected identifier in parameters of function: $entry")
                            params.add(right)
                            consume() // last param
                            right = current
                        }
                        consume() // right paren
                        return FunctionDefinition(identifier, params, parseBody("function ${identifier.value} at line ${identifier.line}"))
                    }
                    KeywordKind.RETURN -> {
                        consume() // return
                        val value = parseExpression()
                        if (value !is OfValue) throwParseException("Expected some value after return")
                        return ReturnFunction(value)
                    }
                    KeywordKind.IF -> {
                        consume() // if
                        val left = consume()
                        if (left !is Token.Separator || left.kind != SeparatorKind.LEFT_PAREN) throwParseException("Expected left paren to start IF expression")
                        val operand = parseExpression()
                        val right = consume()
                        // if (right !is Token.Separator || right.kind != SeparatorKind.RIGHT_PAREN) throwParseException("Expected right paren to end IF expression")
                        if (operand !is OfValue) throwParseException("Expected condition to return true or false")
                        return IfStatement(operand, parseBody("If statement at line #${entry.line}"))
                    }
                    else -> throwParseException("Unhandled keyword: $entry")
                }
            }
            is OfValue -> return parseValuable()
            else -> throwParseException("Unhandled entry: $entry")
        }
    }

    private fun parseBody(function: String): List<Node> {
        val left = consume()
        if (left !is Token.Separator || left.kind != SeparatorKind.LEFT_BRACE) throwParseException("Expected left brace to start body: $function")
        val body = ArrayList<Node>()
        do {
            val next = current
            // handle empty function body
            if (next is Token.Separator && next.kind == SeparatorKind.RIGHT_BRACE) break
            val line = parseStatement()
            body.add(line)
        } while (current !is Token.Separator)
        consume() // right brace
        return body
    }

    private fun parseExpression(): Node {
        var left = parseTerm()

        while (true) {
            val token = current
            if (token is Token.Operator) {
                consume() // Consume the operator
                val right = parseTerm()
                if (right !is OfValue) throwParseException("Right side of expression does not yield a result")
                if (left !is OfValue) throwParseException("Right side of expression does not yield a result")
                left = BinaryExpression(left, token.kind, right)
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
            if (token is Token.Operator && (token.kind == OperatorKind.MULTIPLY || token.kind == OperatorKind.DIVIDE)) {
                consume() // Consume the operator
                val right = parseValuable()
                left = BinaryExpression(left, token.kind, right)
            } else {
                break
            }
        }

        return left
    }

    private fun parseValuable(): OfValue {
        return when (val token = current){
            is Token.TemplateStringLiteral -> {
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
                when (val next = current){
                    is Token.Separator -> {
                        when (next.kind) {
                            SeparatorKind.LEFT_PAREN -> {
                                consume() // left paren
                                val params = ArrayList<OfValue>()
                                do {
                                    if (current == null || current is Token.Separator) break
                                    val thing = parseExpression()
                                    if (thing !is OfValue) throwParseException("Expected yielding expression for function argument")
                                    params.add(thing)
                                } while (true)
                                consume() // right paren
                                return FunctionInvoke(token, params)
                            }
                            else -> token
                        }
                    }
                    else -> token
                }
            }
            else -> throwParseException("Unhandled valuable: $token")
        }
    }

    private fun throwParseException(msg: String): Nothing {
        println(tokens.contentDeepToString())
        println(nodes)
        throw ParseException("At line #${current?.line} -> $msg")
    }
}

class ParseTree(

)

interface ParseTreeBuilder {
    fun addCond(f: (Token) -> Boolean): ParseTreeBuilder
    fun addResult(f: (Token) -> Any): ParseTreeBuilder
    fun build(): ParseTree
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
 * A [Node] that has two sides and applies some operation to both.
 *
 * Binary expressions can be chained together, and the [Parser] does this
 * in [Parser.parseExpression] and [Parser.parseTerm]
 */
data class BinaryExpression(
    val left: OfValue,
    val operator: OperatorKind,
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
 * Can be [invoked][Function.invoke] just as [built-in functions][BuiltInFunctions] can.
 */
data class FunctionDefinition(
    val function: Token.Identifier,
    val parameters: List<Token.Identifier>,
    val body: List<Node>
): Function, Node {
    override fun invoke(parentScope: ExecutionScope, args: List<Any?>): Any? {
        val scope = LocalExecutionScope(parentScope)
        if (parameters.size != args.size) throw RuntimeException("Incorrect number of parameters used to invoke ${function.value}(${args.size})")
        for ((i, arg) in parameters.withIndex()) {
            scope.setVar(arg, args[i])
        }
        for (node in body) {
            if (node is ReturnFunction) {
                return if (node.variable is Token.Identifier) scope.getVar(node.variable)
                else node.variable
            }
            scope.interpret(node)
        }
        return Unit
    }
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
    val operand: OfValue, // should be a value of true or false, if not then not null
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

class ParseException(message: String) : Exception(message)