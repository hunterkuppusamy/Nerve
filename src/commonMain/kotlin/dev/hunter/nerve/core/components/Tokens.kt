package dev.hunter.nerve.core.components

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.InterpretationException

sealed class Token {
    abstract val line: Int
    class Identifier(override val line: Int, val name: String): Token(), OfValue {
        override suspend fun interpret(scope: ExecutionScope): Any? = scope.getValueOf(this)
        override fun toString(): String = "|$name|"
    }
    class StringTemplate(override val line: Int, val tokens: List<Any> /* terrible move */): Token() {// not a data class because of the array
        private val _cachedString = ">$tokens<"
        override fun toString(): String = _cachedString
    }
}

/**
 * A node that is [OfValue] whose value is computed during 'compile time',
 * or in this case [tokenization][Tokenizer] time
 */
sealed class Constant: Token(), OfValue {
    class StringLiteral(override val line: Int, override val value: String): Constant() {
        override fun toString(): String = "\"$value\""
    }
    class NaturalLiteral(override val line: Int, override val value: Long): Constant()
    class FloatingLiteral(override val line: Int, override val value: Double): Constant()
    class BooleanLiteral(override val line: Int, override val value: Boolean): Constant()

    abstract val value: Any
    override suspend fun interpret(scope: ExecutionScope): Any? = value
    override fun toString(): String = "'$value'"
}

sealed class Separator(private val str: String): Token(){
    class LeftParen(override val line: Int): Separator("(")
    class RightParen(override val line: Int): Separator(")")
    class LeftBrace(override val line: Int): Separator("{")
    class RightBrace(override val line: Int): Separator("}")
    class LeftBracket(override val line: Int): Separator("[")
    class RightBracket(override val line: Int): Separator("]")
    class Comma(override val line: Int): Separator(",")

    override fun toString(): String = "<$str>"
}

sealed class Operator(private val str: String): Token() {
    class Add(override val line: Int): Operator("+")
    class Subtract(override val line: Int): Operator("-")
    class Divide(override val line: Int): Operator("/")
    class Multiply(override val line: Int): Operator("*")
    class Exponentiate(override val line: Int): Operator("^")
    class Modulate(override val line: Int): Operator("%")
    class Assign(override val line: Int): Operator("=")
    class IsEqual(override val line: Int): Operator("==")
    class IsNotEqual(override val line: Int): Operator("!=")
    class IsGreaterThan(override val line: Int): Operator(">")
    class IsLessThan(override val line: Int): Operator("<")
    class Range(override val line: Int): Operator("...")

    override fun toString(): String = "[$str]"
}

sealed class Keyword: Token(){
    class If(override val line: Int): Keyword()
    class While(override val line: Int): Keyword()
    class Do(override val line: Int): Keyword()
    class Return(override val line: Int): Keyword()
    class Break(override val line: Int): Keyword()
    class For(override val line: Int): Keyword()
    class Continue(override val line: Int): Keyword()
    class Fun(override val line: Int): Keyword()
    class Var(override val line: Int): Keyword()
    class MutVar(override val line: Int): Keyword()
    class Else(override val line: Int): Keyword()
    // class In(override val line: Int): Keyword()
    class Null(override val line: Int): Keyword(), OfValue{
        override suspend fun interpret(scope: ExecutionScope): Any? = null
    }

    private val _cachedName = "\$${this::class.simpleName!!.uppercase()}\$"

    override fun toString(): String = _cachedName

    companion object{
        fun byName(name: String, line: Int): Keyword? {
            return when (name.lowercase()) {
                "if" -> If(line)
                "else" -> Else(line)
                "var" -> Var(line)
                "var*" -> MutVar(line) // not really tokenized through this function
                "for" -> For(line)
                "while" -> While(line)
                "do" -> Do(line)
                // "in" -> In(line)
                "return" -> Return(line)
                "break" -> Break(line)
                "continue" -> Continue(line)
                "fun" -> Fun(line)
                "null" -> Null(line)
                else -> null
            }
        }
    }
}

const val TEMPLATE_START_CHAR = '{'
const val TEMPLATE_END_CHAR = '}'