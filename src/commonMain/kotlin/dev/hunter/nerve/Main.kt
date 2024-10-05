package dev.hunter.nerve

import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer

fun main() {
    platform.entry()
    val tok = Tokenizer("""
        fun helloWorld(arg){ 
            print('{arg}') 
        }
        helloWorld(1)
        """.trimIndent().toCharArray()).tokenize()
    val nodes = Parser(tok).parse()
    val it = Interpreter().interpret(nodes)
}

interface Platform {
    val name: String
    val logger: Logger
    val entry: () -> Unit
}

expect val platform: Platform

interface Logger {
    fun info(message: String)
    fun warning(message: String)
    fun error(message: String)
}

internal val logger get() = platform.logger
internal val debugLog get() = platform.logger