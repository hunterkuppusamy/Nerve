package dev.hunter.nerve.core.components.token

sealed class Separator(private val str: String): Token(){
    class LeftParen(override val line: Int): Separator("(")
    class RightParen(override val line: Int): Separator(")")
    class LeftBrace(override val line: Int): Separator("{")
    class RightBrace(override val line: Int): Separator("}")
    class LeftBracket(override val line: Int): Separator("[")
    class RightBracket(override val line: Int): Separator("]")
    class Comma(override val line: Int): Separator(",")
    class RightChevron(override val line: Int): Separator(">")

    override fun toString(): String = "<$str>"
}