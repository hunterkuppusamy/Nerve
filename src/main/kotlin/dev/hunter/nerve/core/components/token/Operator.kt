package dev.hunter.nerve.core.components.token

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