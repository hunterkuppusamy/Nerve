package dev.hunter.nerve.core

import dev.hunter.nerve.*
import dev.hunter.nerve.core.components.resolved.*
import dev.hunter.nerve.core.components.token.*
import dev.hunter.nerve.core.components.type.Type
import java.util.concurrent.atomic.AtomicInteger

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
    context: NerveContext = Nerve.globalContext,
    tokens: List<Token>,
    scope: ParsingScope?
): Contextual(context) {
    private val buf: TokenBuffer = TokenBuffer(tokens)
    private val nodes = ArrayList<ResolvedNode>()
    private val scope = scope ?: ParsingScope(context)
    internal val bodyBuffer: ArrayList<ResolvedNode> = ArrayList()

    // linear history of all created nodes
    private val nodeHistory = LinkedHashSet<ResolvedNode>()

    private val definedFunctions = run {
        val ret = HashMap(context.types.flatMap { it.functions.entries }.associate { it.key to it.value })
        ret.putAll(context.globalFunctions)
        ret
    }

    constructor(
        context: NerveContext = Nerve.globalContext,
        tokens: List<Token>
    ): this(context, tokens, null)

    /*
     * Parses the [tokens] into a collection of [nodes][Node].
     *
     * These nodes make up the hierarchy that is the syntax of my language.
     *
     * Nodes are interpreted by the [Interpreter] to provide functionality
     */
    fun parse(): NodeScript {
        // initial parsing: Tokens -> Nodes
        resolveNodes()

        // no scope needs ot be taken into account for functions, as they can only be declared globally
        // Checking if each function invocation corresponds to a defined function
        for (node in nodes) {
            if (node !is FunctionInvocation) continue
            if (!definedFunctions.containsValue(node.function)) throwParseException("Function '${node.function}' is not defined")
        }

        val lines = nodes.joinToString(separator = "", prefix = "--- CURRENT NODES:\n", postfix = "--- END OF NODES.") { "-> $it\n" }
        context.debug(Flag.DEBUG_STATE_CHANGE) { lines }

        return NodeScript(nodes)
    }

    private fun resolveNodes() {
        try{
            do {
                // weird edge case...
                // the last token doesnt get consumed... so a new statement tries to parse
                // using the last token of the last statement as the first token of a new statement (undesired)
                if (buf.pos == buf.size - 1) break

                scope.apply {
                    val node = parseStatement()
                    nodes.add(node)
                }
            } while (buf.pos < buf.size)
        }catch (t: Throwable){
            val lines = nodes.joinToString(separator = "", prefix = "--- CURRENT NODES:\n", postfix = "--- END OF NODES.") { "-> $it\n" }
            context.logger.logMethod(LogContext(context, lines))
            throw ParseException(cause = t, message = "While resolving nodes")
        }
    }

    private fun ParsingScope.parseStatement(): ResolvedNode {
        val token = buf.get<Token>()
        context.debug { "Parsing token $token -> at ${buf.pos}:${buf.remaining()}" }
        when (token){
            is Keyword.Fun -> {
                val identifier = buf.get<Identifier>("Expected identifier after function definition")
                try{
                    buf.get<Separator.LeftParen>("Expected left parenthesis for parameters of function")
                    val params = LinkedHashMap<Identifier, Identifier>() // insertion order matters big time
                    start(this@Parser) {
                        do {
                            val type = buf.get<Token>("Expected a token, got EOL")
                            if (type is Separator.RightParen) break
                            else if (type !is Identifier) throwParseException("Expected a token or closing bracket after function definition")
                            val param =
                                buf.get<Identifier>("Expected an identifier after a type reference in function definition")
                            println("Param = $param")
                            params[type] = param
                            val comma = buf.get<Separator>(msg = "Expected separator after function parameter")
                            if (comma is Separator.RightParen) break
                            if (comma !is Separator.Comma) throwParseException("Expected comma after parameter '$type' in function definition: $identifier")
                        } while (true)
                    }
                    buf.get<Separator.RightChevron>("Expected right arrow '>' to succeed function parameters and define a return type")
                    val retType = buf.get<Identifier>("Expected return type")
                    val def = FunctionDefinition(identifier, params, context.getType(retType), start(this@Parser) {
                        params.forEach { addVar(false, it.key, it.value) }
                        parseBody("function ${identifier.name}")
                    })
                    definedFunctions[identifier.name] = def
                    return def
                }catch (t: Throwable) {
                    throwParseException("During parsing of function '${identifier.name}'s definition", t)
                }
            }
            is Keyword.Return -> {
                val value = parseExpression()
                return ReturnStatement(value)
            }
            is Keyword.Type -> {
                val name = buf.get<Identifier>("Expected identifier after type definition")
                return TypeDefinition(name, arrayOf())
            }
            is Keyword.If -> {
                val branches = ArrayList<IfTree.Branch>(2)
                branches.add(run {
                    buf.get<Separator.LeftParen>("Expected left paren to start an if statement")
                    val condition = parseExpression()
                    buf.get<Separator.RightParen>("Expected right paren to start an if statement")
                    IfTree.Branch(condition, start(this@Parser){ parseBody("If statement") })
                })
                while (buf.peek<Keyword>() is Keyword.ElseIf) {
                    buf.get<Keyword.ElseIf>("Expected elseif or eif")
                    buf.get<Separator.LeftParen>("Expected left paren to start an else if statement")
                    val condition = parseExpression()
                    buf.get<Separator.RightParen>("Expected right paren to start an else if statement")
                    val b = IfTree.Branch(condition, start(this@Parser){ parseBody("Elseif statement") })
                    branches.add(b)
                }
                if (buf.peek<Keyword>() is Keyword.Else) {
                    val key = buf.get<Keyword.Else>("Expected else")
                    val b = IfTree.Branch(Constant.BooleanLiteral(key.line, true), start(this@Parser){ parseBody("else statement") })
                    branches.add(b)
                }
                return IfTree(branches)
            }
            is Keyword.For -> {
                val type = buf.get<Identifier>("Expected type identifier after for loop definition")
                val id = buf.get<Identifier>("Expected variable identifier after for loop definition")
                val n = buf.get<Identifier>("Expected 'in' after for loop definition")
                if (n.name != "in") throwParseException("'${n.name}' is not 'in'")
                buf.get<Separator.LeftParen>{ "Expected left paren to start a for loop, got $it" }
                val bounds = parseExpression()
                if (bounds is Constant) throwParseException("For loop bound (${bounds.type.name}) is not an iterable type")
                buf.get<Separator.RightParen>{ "Expected right paren to start a for loop, got $it" }
                return ForLoop(context.getType(type), id, bounds, start(this@Parser) {
                    addVar(false, type, id)
                    parseBody("For loop")
                })
            }
            is Keyword.Var -> {
                val typeId = buf.get<Identifier>("Expected identifier after variable definition (var ...)")
                val varId = buf.get<Identifier>("Expected another identifier after variable definition (var ...)")
                buf.get<Operator.Assign>("Expected assignment operator after variable definition (var ...)")
                val expr = parseExpression()
                isNotDefined(varId)
                addVar(false, typeId, varId)
                return VariableInitialization(context.getType(typeId), varId, expr)
            }
            is Keyword.MutVar -> {
                val typeId = buf.get<Identifier>("Expected identifier after variable definition (var* ...)")
                val varId = buf.get<Identifier>("Expected another identifier after variable definition (var* ...)")
                buf.get<Operator.Assign>("Expected assignment operator after variable definition (var* ...)")
                val expr = parseExpression()
                isNotDefined(varId)
                addVar(true, typeId, varId)
                return VariableInitialization(context.getType(typeId), varId, expr)
            }
            is Keyword -> throwParseException("Unhandled keyword '${token::class.simpleName}'")
            is Identifier -> {
                when (val next = buf.get<Token>()){
                    is Operator.Assign -> {
                        val expr = parseExpression()
                        isMutable(token) // throw if the variable is not mutable
                        return VariableReassignment(typeOf(token), token, expr)
                    }
                    is Operator -> {
                        val expr = parseExpression()
                        return BinaryExpression(GetVariable(typeOf(token), token), next, expr)
                    }
                    is Separator.LeftParen -> {
                        return parseFunctionInvocation(token)
                    }
                    else -> throwParseException("Expected an operator or parenthesis after an identifier")
                }
            }
            else -> buf.unexpectedToken({ "Unhandled start of statement $it" })
        }
    }

    private fun ParsingScope.parseBody(function: String): List<ResolvedNode> {
        buf.get<Separator.LeftBrace>("Expected left brace to start body")
        bodyBuffer.clear()
        try {
            do {
                val next = buf.peek<Token>()
                // handle empty body
                if (next is Separator.RightBrace) break
                val line = parseStatement()
                println("Adding $line to body $function")
                bodyBuffer.add(line)
            } while (true)
            buf.get<Separator.RightBrace>("Expected right brace, but we already found one because it broke the while loop...")
            return bodyBuffer
        }catch (t: Throwable) {
            throwParseException(function, t)
        }
    }

    private fun parseExpression(): OfValue {
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
        val token = buf.get<Token>()
        context.debug { "Parsing valuable $token -> at ${buf.pos}:${buf.remaining()}" }
        return when (token){
            is StringTemplate -> {
                val values = ArrayList<OfValue>()
                for (piece in token.tokens) {
                    when (piece) {
                        is List<*> -> {
                            val node = Parser(
                                context = context,
                                tokens = piece as? List<Token>
                                    ?: throw IllegalStateException("Somehow there is an list of something other than tokens: ${piece::class.simpleName}"),
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
            is Identifier -> {
                when (buf.peek<Token>()){
                    is Separator.LeftParen -> {
                        buf.get<Separator.LeftParen>()
                        return parseFunctionInvocation(token)
                    }
                    else -> {
                        isDefined(token)
                        GetVariable(typeOf(token), token)
                    }
                }
            }
            is Keyword.Null -> token
            else -> throwParseException("Unhandled valuable: $token")
        }
    }

    private fun ParsingScope.parseFunctionInvocation(id: Identifier): FunctionInvocation {
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
            // cant really do compile time type checking without a type being propagated from tokenization,
            // and evaluating the entire call tree to the literals. Functions would also need static return types
            // this evolution would require a refactor entirely, and a lot of rewriting. Maybe another branch can be made?
            // StaticTyping branch?
            // although i would prefer if all type checking was inferred to keep the language simple yet efficient during runtime (the absence of functions checking their arguments)
        } catch (t: Throwable) {
            throwParseException("Function invocation '$id'", t)
        }
        println("Tokens left: ${buf.remaining()}")
        val func = definedFunctions[id.name]
            ?: throwParseException("Function '$id' is not defined")
        return FunctionInvocation(func, args)
    }

    private fun throwParseException(msg: String, cause: Throwable? = null): Nothing = throw ParseException("At line #${buf.peek<Token>()?.line} -> $msg", cause)
}

class ParseException(message: String? = null, override val cause: Throwable?= null) : Exception(message)

internal class ParsingScope private constructor(
    val context: NerveContext,
    parent: ParsingScope? = null
){
    constructor(context: NerveContext): this(context,null)

    // private val children: ArrayList<ParsingScope> = ArrayList()
    private val thisVars: ArrayList<Var> = ArrayList(2)
    private val parentVars = parent?.thisVars ?: emptyList()

    data class Var(
        val name: Identifier,
        val mutable: Boolean,
        val type: Identifier
    )

    fun <T> start(parser: Parser, f: ParsingScope.() -> T): T {

        val local = ParsingScope(context,this)
        val ret = local.f()
        local.close(parser)
        // children.add(local)
        return ret
    }

    val index: AtomicInteger = parent?.index ?: AtomicInteger(0)
    private var reduce = 0

    fun addVar(mut: Boolean, type: Identifier, name: Identifier): Var {
        val variable = getVar(name)
        if (variable == null) {
            thisVars.add(Var(name, mut, type))
        }
        reduce--
        return getVar(name) ?: throw ParseException("HOW TF")
    }

    private fun getVar(id: Identifier): Var? {
        return thisVars.firstOrNull { it.name.name == id.name } ?: parentVars.firstOrNull { it.name.name == id.name }
    }

    fun isNotDefined(id: Identifier): Nothing? = if (getVar(id) == null) null
    else throw ParseException("(#${id.line}) Variable $id is already defined here")

    fun isDefined(id: Identifier): Nothing? {
        val variable = getVar(id)
        return if (variable == null)
            throw ParseException("(#${id.line}) Variable $id is undefined here")
        else null
    }

    fun isMutable(id: Identifier): Nothing? {
        isDefined(id)
        val vari = getVar(id)!!
        return if (!vari.mutable) throw ParseException("Variable $id is immutable")
        else null
    }

    fun typeOf(id: Identifier): Type {
        isDefined(id)
        val vari = getVar(id)!!
        val typeName = vari.type
        return context.getType(typeName)
    }

    fun close(parser: Parser) {
        index.addAndGet(reduce)
        thisVars.forEach {
            //parser.bodyBuffer.add(FreeVariable(it.name))
        }
    }
}

/**
 * Maybe eventually NodeScripts are just turned into instructions at runtime
 * to be run as bytecode (or whatever target i choose)
 */
interface Script

class CompiledScript(

): Script

data class NodeScript(
    internal val nodes: Collection<ResolvedNode>
): Script