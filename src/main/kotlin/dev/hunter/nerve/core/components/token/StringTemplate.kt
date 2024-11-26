package dev.hunter.nerve.core.components.token

class StringTemplate(override val line: Int, val tokens: List<Any> /* terrible move */): Token() {// not a data class because of the array
    private val _cachedString = ">$tokens<"
    override fun toString(): String = _cachedString
}