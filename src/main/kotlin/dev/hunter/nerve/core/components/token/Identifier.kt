package dev.hunter.nerve.core.components.token

class Identifier(override val line: Int, val name: String): Token() {
    override fun toString(): String = "|$name|"
}