package dev.hunter.nerve.core

import dev.hunter.nerve.CanDebug
import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.platform
import java.nio.Buffer
import kotlin.reflect.KClass

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
    tokens: List<Token>,
    private val debug: EnumSet<DebugFlag> = EnumSet()
): CanDebug {
    private val buf: TokenBuffer = TokenBuffer(tokens)
    private var currentIndex = 0
    private val nodes = ArrayList<Node>()

    /*
     * Parses the [tokens] into a collection of [nodes][Node].
     *
     * These nodes make up the hierarchy that is the syntax of my language.
     *
     * Nodes are interpreted by the [Interpreter] to provide functionality
     */
    fun parse(): Collection<Node> {
        do {
            debug(DebugFlag.STATE) { "starting new statement at -> #${buf.peek<Token>().line} ${buf.peek<Token>()}" }
            val node = parseStatement()
            nodes.add(node)
        } while (buf.pos <= buf.size)
        return nodes
    }

    private fun parseStatement(): Node {
        when (val token = buf.get<Token>()){
            is Token.Identifier -> {
                when (val next = buf.get<Token>()){
                    is Operator.Assign -> {
                        val expr = parseExpression()
                        if (expr !is OfValue) throwParseException("Expected yielding expression for variable assignment")
                        return VariableAssignment(token, expr)
                    }
                    is Operator -> {
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
                val identifier = buf.get<Token.Identifier>("Expected identifier after function declaration")
                buf.get<Separator.LeftParen>("Expected left parenthesis for parameters of function")
                val params = ArrayList<Token.Identifier>()
                do {
                    val right = buf.get<Token.Identifier>("Expected identifier in parameters of function '$identifier'")
                    params.add(right)
                    val comma = buf.get<Separator>(msg = "Expected separator after function parameter")
                    if (comma is Separator.RightParen) break
                    if (comma !is Separator.Comma) throwParseException("Expected comma after parameter '$right' in function declaration: $identifier")
                } while (true)
                return FunctionDefinition(identifier, params, parseBody("function ${identifier.name} at line ${identifier.line}"))
            }
            is Keyword.Return -> {
                val value = parseExpression()
                if (value !is OfValue) throwParseException("Expected some value after return")
                return ReturnFunction(value)
            }
            is Keyword.If -> {
                buf.get<Separator.LeftParen>("Expected left paren to start IF expression")
                val condition = parseExpression()
                buf.get<Separator.RightParen>("Expected right paren to start IF expression")
                if (condition !is OfValue) throwParseException("Expected condition to return true or false")
                return IfStatement(condition, parseBody("If statement at line #${token.line}"))
            }
            // do I need this? Do I want to support it?
            // is OfValue -> return parseValuable()
            else -> throwParseException("Unhandled token: $token")
        }
    }

    private fun parseBody(function: String): List<Node> {
        buf.get<Separator.LeftBrace>("Expected left brace to start body")
        try {
            val body = ArrayList<Node>()
            do {
                val next = buf.peek<Token>()
                // handle empty function body
                if (next is Separator.RightBrace) break
                val line = parseStatement()
                body.add(line)
            } while (true)
            buf.get<Separator.RightBrace>("SEVERE ERROR")
            return body
        }catch (p: ParseException) {
            throwParseException(function, p)
        }
    }


    private fun parseExpression(): Node {
        var left = parseTerm()

        while (true) {
            val token = buf.peek<Token>()
            if (token is Operator) {
                buf.get<Operator>() // Consume the operator
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
            val token = buf.peek<Token>()
            if (token is Operator) {
                buf.get<Operator>() // Consume the operator
                val right = parseValuable()
                left = BinaryExpression(left, token, right)
            } else {
                break
            }
        }

        return left
    }

    private fun parseValuable(): OfValue {
        return when (val token = buf.get<Token>()){
            is Token.StringTemplate -> {
                val values = ArrayList<OfValue>()
                for (piece in token.tokens) {
                    when (piece) {
                        is List<*> -> {
                            val node = Parser(
                                piece as? List<Token>
                                    ?: throw IllegalStateException("Somehow there is an list of something other than tokens: ${piece::class.simpleName}"),
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
            is Constant -> token
            is Token.Identifier -> {
                when (buf.peek<Token>()){
                    is Separator.LeftParen -> {
                        buf.get<Separator.LeftParen>()
                        return parseFunctionInvocation(token)
                    }
                    else -> token
                }
            }
            is Keyword.Null -> token
            else -> throwParseException("Unhandled valuable: $token")
        }
    }

    private fun parseFunctionInvocation(id: Token.Identifier): FunctionInvoke {
        val args = ArrayList<OfValue>()
        try {
            do {
                val cur = buf.peek<Token>()
                if (cur is Separator.RightParen) {
                    buf.get<Token>()
                    break
                } // handle no arg function
                val arg = parseExpression()
                val comma = buf.get<Token>()
                if (arg !is OfValue) throwParseException("Expected expression in arguments of function $id")
                args.add(arg)
                if (comma is Separator.RightParen) break
                if (comma !is Separator.Comma) throwParseException("Expected comma to delimit arguments in function $id")
            } while (true)
        } catch (t: Throwable) {
            throwParseException("Function invocation '$id'", t)
        }
        return FunctionInvoke(id, args)
    }

    private fun throwParseException(msg: String, cause: Throwable? = null): Nothing {
        throw ParseException("At line #${buf.peek<Token>().line} -> $msg", cause)
    }

    override fun debug(flag: DebugFlag?, message: () -> String) {
        if (if (flag != null) debug.contains(flag) else debug.size > 0) platform.logger.info("[${flag ?: "ANY"}] DEBUG: ${message()}") // lazily invoke the message, only if debugging
    }
}

class TokenBuffer(
    arr: Collection<Token>
) {
    private val _arr = ArrayList(arr)
    private var _index = 0
    val size get() = _arr.size
    val pos get() = _index

    fun move(offset: Int) {
        _index += offset
    }

    fun <T: Any> get(clazz: KClass<T>, offset: Int = 0, msg: String? = null): T {
        val pos = _index + offset
        if (pos < 0) throw IllegalArgumentException("Out of bounds access with index $_index and offset $offset")
        if (pos >= _arr.size) throw IllegalArgumentException("End of buffer reached with index $_index and offset $offset")
        val c = _arr[pos]
        _index++
        if (!clazz.isInstance(c)) throw UnexpectedTokenException(msg ?: "Unexpected token $c")
        @Suppress("UNCHECKED_CAST") // I just check it
        return c as T
    }

    inline fun <reified T: Token> get(msg: String? = null): T {
        return get(T::class, 0, msg)
    }

    inline fun <reified T: Token> peek(offset: Int = 0, msg: String? = null): T {
        val ret = get(T::class, offset, msg)
        move(-1)
        return ret
    }

    class UnexpectedTokenException(msg: String): Exception(msg)
}

class ParseException(message: String, override val cause: Throwable?) : Exception(message)