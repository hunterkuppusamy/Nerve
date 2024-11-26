package dev.hunter.nerve.core.components.token

abstract class Token {
    abstract val line: Int
}

const val TEMPLATE_START_CHAR = '{'
const val TEMPLATE_END_CHAR = '}'