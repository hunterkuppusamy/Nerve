package dev.hunter.nerve.core

sealed class Token {
    abstract val line: Int
    data class Identifier(override val line: Int, val name: String): Token(), OfValue
    class StringTemplate(override val line: Int, val tokens: List<Any> /* terrible move */): Token(), OfValue // not a data class because of the array
    data class StringLiteral(override val line: Int, override val value: String): Token(), Constant
    data class NaturalLiteral(override val line: Int, override val value: Long): Token(), Constant
    data class FloatingLiteral(override val line: Int, override val value: Double): Token(), Constant
    data class BooleanLiteral(override val line: Int, override val value: Boolean): Token(), Constant

    override fun toString(): String {
        return when (this) {
            is Identifier -> "|$name|"
            is Constant -> "'$value'"
            is StringTemplate -> "StringTemplate[$tokens]"
            else -> this::class.simpleName ?: (this as Any).toString()
        }
    }
}

sealed class Separator: Token(){
    data class LeftParen(override val line: Int): Separator()
    data class RightParen(override val line: Int): Separator()
    data class LeftBrace(override val line: Int): Separator()
    data class RightBrace(override val line: Int): Separator()
    data class LeftBracket(override val line: Int): Separator()
    data class RightBracket(override val line: Int): Separator()
    data class Comma(override val line: Int): Separator()

    override fun toString(): String {
        // return this::class.simpleName!!
        return when (this) {
            is LeftParen -> "'('"
            is RightParen -> "')'"
            is LeftBrace -> "'{'"
            is RightBrace -> "'}'"
            is LeftBracket -> "'['"
            is RightBracket -> "']'"
            is Comma -> "','"
        }
    }
}

sealed class Operator: Token() {
    data class Add(override val line: Int): Operator()
    data class Subtract(override val line: Int): Operator()
    data class Divide(override val line: Int): Operator()
    data class Multiply(override val line: Int): Operator()
    data class Exponentiate(override val line: Int): Operator()
    data class Modulate(override val line: Int): Operator()
    data class Assign(override val line: Int): Operator()
    data class IsEqual(override val line: Int): Operator()
    data class IsNotEqual(override val line: Int): Operator()
    data class IsGreaterThan(override val line: Int): Operator()
    data class IsLessThan(override val line: Int): Operator()
}

sealed class Keyword: Token(){
    data class If(override val line: Int): Keyword()
    data class While(override val line: Int): Keyword()
    data class Do(override val line: Int): Keyword()
    data class Return(override val line: Int): Keyword()
    data class Break(override val line: Int): Keyword()
    data class Continue(override val line: Int): Keyword()
    data class Fun(override val line: Int): Keyword()
    data class Else(override val line: Int): Keyword()
    data class Null(override val line: Int): Keyword(), OfValue

    companion object{
        fun byName(name: String, line: Int): Keyword? {
            return when (name.lowercase()) {
                "if" -> If(line)
                "else" -> Else(line)
                "while" -> While(line)
                "do" -> Do(line)
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

/**
 * A node that is OfValue whose value is computed during 'compile time',
 * or in this case tokenization time
 */
interface Constant: OfValue {
    val value: Any
}