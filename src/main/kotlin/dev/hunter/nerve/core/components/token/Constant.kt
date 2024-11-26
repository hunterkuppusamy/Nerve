package dev.hunter.nerve.core.components.token

import dev.hunter.nerve.core.ExecutionScope
import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.resolved.OfValue
import dev.hunter.nerve.core.components.type.Type
import dev.hunter.nerve.core.standard.*

/**
 * A node that is [OfValue] whose value is computed during 'compile time',
 * or in this case [tokenization][Tokenizer] time
 */
sealed class Constant(
    override val type: Type
): Token(), OfValue {
    class StringLiteral(override val line: Int, value: String): Constant(STRING_TYPE) {
        override val variable: Value = Value(STRING_TYPE, value)
        override fun toString(): String = "'${variable.value}'"
    }
    class IntegerLiteral(override val line: Int, value: Int): Constant(INTEGER_TYPE){
        override val variable: Value = Value(INTEGER_TYPE, value)
        override fun toString(): String = "${variable.value}i"
    }
    class LongLiteral(override val line: Int, value: Long): Constant(LONG_TYPE){
        override val variable: Value = Value(LONG_TYPE, value)
        override fun toString(): String = "${variable.value}L"
    }
    class FloatLiteral(override val line: Int, value: Float): Constant(FLOAT_TYPE){
        override val variable: Value = Value(FLOAT_TYPE, value)
        override fun toString(): String = "${variable.value}f"
    }
    class DoubleLiteral(override val line: Int, value: Double): Constant(DOUBLE_TYPE){
        override val variable: Value = Value(DOUBLE_TYPE, value)
        override fun toString(): String = "${variable.value}d"
    }
    class BooleanLiteral(override val line: Int, value: Boolean): Constant(BOOLEAN_TYPE){
        override val variable: Value = Value(BOOLEAN_TYPE) { value }
        override fun toString(): String = "${variable.value}"
    }

    abstract val variable: Value
    override fun interpret(scope: ExecutionScope): Value = variable
}