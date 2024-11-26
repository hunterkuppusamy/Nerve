package dev.hunter.nerve.core

import dev.hunter.nerve.core.components.intermediary.IntermediaryNode
import dev.hunter.nerve.core.components.resolved.ResolvedNode
import dev.hunter.nerve.core.components.resolved.VariableInitialization
import dev.hunter.nerve.core.components.token.*
import kotlin.reflect.KClass

class ParseBuilder {
    private val lanes = ArrayList<Lane>()
    private var currentLane: Lane? = null
    private var currentDepth = 1;

    fun <T: Token> start(kClass: KClass<T>): ParseBuilder {
        currentDepth = 1
        if (currentLane != null) lanes.add(currentLane!!)
        currentLane = Lane()
        with(kClass)
        return this
    }

    inline fun <reified T: Token> start(): ParseBuilder {
        return start(T::class)
    }

    fun <T: Token> with(kClass: KClass<T>, f: LaneFunction = null): ParseBuilder {
        currentLane!!.append(currentDepth++, kClass, f)
        return this
    }

    inline fun <reified T: Token> with(noinline f: LaneFunction = null): ParseBuilder {
        return with(T::class, f)
    }

    fun build(): BuiltParser {
        return BuiltParser(lanes)
    }

    override fun toString(): String {
        return lanes.joinToString(separator = "\n")
    }

}

class Lane {
    private val types = ArrayList<Triple<Int, KClass<out Token>, LaneFunction>>()
    override fun toString(): String = "Lane[types={${types.joinToString { it.second.simpleName!! }}}]"

    fun append(depth: Int, k: KClass<out Token>, f: LaneFunction = null) {
        types.add(Triple(depth, k, f))
    }

    fun parse(parser: BuiltParser, tokens: List<Token>): Pair<Int, IntermediaryNode>? {
        for ((i, token) in tokens.withIndex()) {
            val pair = types[i]
            val type = pair.second
            if (!type.isInstance(token)) return null
            val ret = pair.third?.invoke(ParseContext(tokens, parser))
            if (ret != null) {
                return pair.first to ret
            }
        }
        return null
    }
}

class BuiltParser(
    private val lanes: List<Lane>
){
    fun parse(tokens: List<Token>): List<IntermediaryNode> {
        var remaining: List<Token> = ArrayList(tokens)
        val nodes = ArrayList<IntermediaryNode>()
        do{
            var changed = false
            for (lane in lanes) {
                println("Remaining = $remaining")
                val ret = lane.parse(this, remaining)
                if (ret != null) {
                    changed = true
                    println("Remaining should drop by ${ret.first} / ${remaining.size}")
                    remaining = remaining.drop(ret.first)
                    nodes.add(ret.second)
                }
            }
            if (!changed) {
                throw ParseException("Statement $remaining could not be understood")
            }
        } while (remaining.isNotEmpty())
        return nodes
    }
}

data class ParseContext(
    val tokens: List<Token>,
    val parser: BuiltParser
)

typealias LaneFunction = ((ParseContext) -> IntermediaryNode)?

fun main(){
    val builder = ParseBuilder()
    builder.start<Keyword.Var>()
        .with<Identifier>()
        .with<Identifier>()
        .with<Operator.Assign>()
        .with<Constant> {
            val type = it.tokens[1] as Identifier
            val id = it.tokens[2] as Identifier
            val value = it.tokens[4] as Constant
            VariableInitialization(value.type, id, value)
        }

    builder.start<Keyword.MutVar>()
        .with<Identifier>()
        .with<Identifier>()
        .with<Operator.Assign>()
        .with<Constant> {
            val type = it.tokens[1] as Identifier
            val id = it.tokens[2] as Identifier
            val value = it.tokens[4] as Constant
            VariableInitialization(value.type, id, value)
        }

    val parse = builder.build()

    val nodes = parse.parse(Tokenizer(data = """
        Hello - Woa sa + asd fuck / y
        var two dick = "string"
    """.trimIndent()).tokenize())
    println(nodes)
}