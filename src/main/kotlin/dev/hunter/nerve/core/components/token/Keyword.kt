package dev.hunter.nerve.core.components.token

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.resolved.OfValue
import dev.hunter.nerve.core.components.type.None
import dev.hunter.nerve.core.components.type.NoneType

sealed class Keyword: Token(){
    class If(override val line: Int): Keyword()
    class Else(override val line: Int): Keyword()
    class ElseIf(override val line: Int): Keyword()
    class While(override val line: Int): Keyword()
    class Do(override val line: Int): Keyword()
    class Return(override val line: Int): Keyword()
    class Break(override val line: Int): Keyword()
    class For(override val line: Int): Keyword()
    class Continue(override val line: Int): Keyword()
    class Fun(override val line: Int): Keyword()
    class Var(override val line: Int): Keyword()
    class MutVar(override val line: Int): Keyword()
    class Type(override val line: Int): Keyword()
    // class In(override val line: Int): Keyword()
    class Null(override val line: Int): Keyword(), OfValue {
        override val type: dev.hunter.nerve.core.components.type.Type = NoneType
        override fun interpret(scope: ExecutionScope): Value = None
    }

    private val _cachedName = "\$${this::class.simpleName!!.uppercase()}\$"

    override fun toString(): String = _cachedName

    companion object{
        fun byName(name: String, line: Int): Keyword? {
            return when (name) { // case sensitive
                "if" -> If(line)
                "elseif" -> ElseIf(line)
                "eif" -> ElseIf(line)
                "else" -> Else(line)
                "var" -> Var(line)
                "var*" -> MutVar(line) // not tokenized through this function
                "for" -> For(line)
                "while" -> While(line)
                "do" -> Do(line)
                "return" -> Return(line)
                "break" -> Break(line)
                "continue" -> Continue(line)
                "type" -> Type(line)
                "fun" -> Fun(line)
                "null" -> Null(line)
                else -> null
            }
        }
    }
}