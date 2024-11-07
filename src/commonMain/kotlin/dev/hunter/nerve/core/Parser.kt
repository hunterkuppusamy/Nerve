package dev.hunter.nerve.core

import dev.hunter.nerve.CanDebug
import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.TokenBuffer
import dev.hunter.nerve.core.components.*
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
class Parser private constructor(
    tokens: List<Token>,
    private val debug: EnumSet<DebugFlag>,
    scope: ParsingScope?
): CanDebug {
    private val buf: TokenBuffer = TokenBuffer(tokens)
    private val nodes = ArrayList<Node>()
    private val scope = scope ?: ParsingScope()
    private val definedFunctions = ArrayList(FunctionRegistry.entries.values.map { it.name })

    constructor(
        tokens: List<Token>,
        debug: EnumSet<DebugFlag> = EnumSet()
    ): this(tokens, debug, null)

    /*
     * Parses the [tokens] into a collection of [nodes][Node].
     *
     * These nodes make up the hierarchy that is the syntax of my language.
     *
     * Nodes are interpreted by the [Interpreter] to provide functionality
     */
    fun parse(): Collection<Node> {
        // initial parsing: Tokens -> Nodes
        resolveNodes()

        // no scope needs ot be taken into account for functions, as they can only be declared globally
        // Checking if each function invocation corresponds to a defined function
        for (node in nodes) {
            if (node !is FunctionInvocation) continue
            if (!definedFunctions.contains(node.function.name)) throwParseException("Function '${node.function.name}(${node.arguments.joinToString{ it::class.simpleName ?: "Anonymous?" }})' is not defined")
        }

        return nodes
    }

    private fun resolveNodes() {
        try{
            do {
                debug(DebugFlag.STATE) { "starting new statement at -> #${buf.peek<Token>()?.line}" }
                debug(DebugFlag.STATE) { "Starting statement with vars ${scope.vars}" }
                scope.apply {
                    val node = parseStatement()
                    nodes.add(node)
                }
            } while (buf.pos < buf.size)
        }catch (t: Throwable){
            println(nodes)
            throw ParseException(cause = t)
        }
    }

    private fun ParsingScope.parseStatement(): Node {
        when (val token = buf.get<Token>()){
            is Keyword.Fun -> {
                val identifier = buf.get<Token.Identifier>("Expected identifier after function declaration")
                buf.get<Separator.LeftParen>("Expected left parenthesis for parameters of function")
                val params = ArrayList<Token.Identifier>()
                start {
                    do {
                        val right = buf.get<Token>("Expected a token, got EOL")
                        if (right is Token.Identifier) params.add(right)
                        else if (right is Separator.RightParen) break
                        else throw ParseException("Expected either a parameter or right parenthesis after function '${identifier.name}'")
                        val comma = buf.get<Separator>(msg = "Expected separator after function parameter")
                        if (comma is Separator.RightParen) break
                        if (comma !is Separator.Comma) throwParseException("Expected comma after parameter '$right' in function declaration: $identifier")
                    } while (true)
                }
                definedFunctions.add(identifier.name)
                return FunctionDefinition(identifier, params, start{
                    params.forEach { addVar(it, false) }
                    parseBody("function ${identifier.name}")
                })
            }
            is Keyword.Return -> {
                val value = parseExpression()
                return ReturnStatement(value)
            }
            is Keyword.If -> {
                buf.get<Separator.LeftParen>("Expected left paren to start an if statement")
                val condition = parseExpression()
                buf.get<Separator.RightParen>("Expected right paren to start an if statement")
                return IfStatement(condition, start{ parseBody("If statement") })
            }
            is Keyword.For -> {
                val index = buf.get<Token.Identifier>("Expected identifier after for loop declaration")
                val n = buf.get<Token.Identifier>("Expected 'in' after for loop declaration")
                if (n.name != "in") throwParseException("Expected 'in' after for loop declaration")
                buf.get<Separator.LeftParen>{ "Expected left paren to start a for loop, got $it" }
                val bounds = parseExpression()
                if (bounds is Constant) throwParseException("For loop bound is not an iterable type")
                buf.get<Separator.RightParen>{ "Expected right paren to start a for loop, got $it" }
                return ForLoop(index, bounds, start {
                    addVar(index, false)
                    parseBody("For loop")
                })
            }
            is Keyword.Var -> {
                val varId = buf.get<Token.Identifier>("Expected identifier after variable definition (var)")
                buf.get<Operator.Assign>("Expected assignment operator after variable definition (var)")
                val expr = parseExpression()
                addVar(varId, false)
                return VariableInitialization(varId, expr, true)
            }
            is Keyword.MutVar -> {
                val varId = buf.get<Token.Identifier>("Expected identifier after variable definition (var*)")
                buf.get<Operator.Assign>("Expected assignment operator after variable definition (var*)")
                val expr = parseExpression()
                addVar(varId, true)
                return VariableInitialization(varId, expr, false)
            }
            is Keyword -> throwParseException("Unhandled keyword '${token::class.simpleName}'")
            is Token.Identifier -> {
                when (val next = buf.get<Token>()){
                    is Operator.Assign -> {
                        val expr = parseExpression()
                        isMutable(token) // throw if the variable is not mutable
                        return VariableReassignment(token, expr)
                    }
                    is Operator -> {
                        val expr = parseExpression()
                        return BinaryExpression(token, next, expr)
                    }
                    is Separator.LeftParen -> {
                        return parseFunctionInvocation(token)
                    }
                    else -> throwParseException("Expected an operator or parenthesis after an identifier")
                }
            }
            else -> throwParseException("Unhandled token: $token")
        }
    }

    private fun ParsingScope.parseBody(function: String): List<Node> {
        buf.get<Separator.LeftBrace>("Expected left brace to start body")
        try {
            val body = ArrayList<Node>(5)
            do {
                val next = buf.peek<Token>()
                // handle empty body
                if (next is Separator.RightBrace) break
                val line = parseStatement()
                body.add(line)
            } while (true)
            buf.get<Separator.RightBrace>("Expected right brace, but we already found one because it broke the while loop...")
            return body
        }catch (p: ParseException) {
            throwParseException(function, p)
        }
    }

    private fun parseExpression(): OfValue{
        return scope.parseExpression()
    }

    private fun ParsingScope.parseExpression(): OfValue {
        var left = parseTerm()

        while (true) {
            val token = buf.peek<Token>()
            if (token is Operator) {
                buf.get<Operator>() // Consume the operator
                val right = parseTerm()
                left = BinaryExpression(left, token, right)
            } else {
                break
            }
        }

        return left
    }

    private fun ParsingScope.parseTerm(): OfValue {
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

    private fun ParsingScope.parseValuable(): OfValue {
        return when (val token = buf.get<Token>()){
            is Token.StringTemplate -> {
                val values = ArrayList<OfValue>()
                for (piece in token.tokens) {
                    when (piece) {
                        is List<*> -> {
                            val node = Parser(
                                tokens = piece as? List<Token>
                                    ?: throw IllegalStateException("Somehow there is an list of something other than tokens: ${piece::class.simpleName}"),
                                debug = debug,
                                scope = this
                            ).parseExpression()
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
                    else -> {
                        isDefined(token)
                        token
                    }
                }
            }
            is Keyword.Null -> token
            else -> throwParseException("Unhandled valuable: $token")
        }
    }

    private fun ParsingScope.parseFunctionInvocation(id: Token.Identifier): FunctionInvocation {
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
                args.add(arg)
                if (comma is Separator.RightParen) break
                if (comma !is Separator.Comma) throwParseException("Expected comma to delimit arguments in function $id")
            } while (true)
            // val call = FunctionRegistry.getFromId(id.name)
            // cant really do compile time type checking without a type being propagated from tokenization,
            // and evaluating the entire call tree to the literals. Functions would also need static return types
            // this evolution would require a refactor entirely, and a lot of rewriting. Maybe another branch can be made?
            // StaticTyping branch?
            // although i would prefer if all type checking was inferred to keep the language simple yet efficient during runtime (the absence of functions checking their arguments)
        } catch (t: Throwable) {
            throwParseException("Function invocation '$id'", t)
        }
        return FunctionInvocation(id, args)
    }

    private fun throwParseException(msg: String, cause: Throwable? = null): Nothing = throw ParseException("At line #${buf.peek<Token>()?.line} -> $msg", cause)

    override fun debug(flag: DebugFlag?, message: () -> String) {
        if (if (flag != null) debug.contains(flag) else debug.size > 0) platform.logger.info("[${flag ?: "ANY"}] DEBUG: ${message()}") // lazily invoke the message, only if debugging
    }
}

class ParseException(message: String? = null, override val cause: Throwable?= null) : Exception(message)

internal class ParsingScope private constructor(
    parent: ParsingScope? = null
){
    constructor(): this(null)

    // private val children: ArrayList<ParsingScope> = ArrayList()
    private val definedVars: ArrayList<Var> = ArrayList(parent?.definedVars ?: ArrayList(0))

    val vars: List<Var> get() = definedVars

    data class Var(
        val name: String,
        val mutable: Boolean
    )

    fun <T> start(f: ParsingScope.() -> T): T {
        val local = ParsingScope(this)
        val ret = local.f()
        // children.add(local)
        return ret
    }

    fun addVar(id: Token.Identifier, mut: Boolean) = definedVars.add(Var(id.name, mut))

    fun isDefined(id: Token.Identifier): Nothing? = if (definedVars.any { it.name == id.name }) null
        else throw ParseException("(#${id.line}) Variable '$id' is undefined here")

    fun isMutable(id: Token.Identifier): Nothing? {
        isDefined(id)
        val variable = definedVars.first { it.name == id.name }
        return if (!variable.mutable) throw ParseException("Variable '$id' is immutable")
        else null
    }
}