package dev.hunter.nerve

import dev.hunter.nerve.core.Tokenizer

fun main(): Unit {
    val tok = Tokenizer("fun helloWorld(arg){ print(\"hello\"".toCharArray()).tokenize()
    println(tok.contentDeepToString())
}

interface Platform {
    val name: String
    val logger: Logger
}

expect val platform: Platform

interface Logger {
    fun info(message: String)
    fun warning(message: String)
    fun error(message: String)
}

internal val logger = platform.logger
internal val debugLog = platform.logger