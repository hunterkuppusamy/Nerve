package dev.hunter.nerve

fun main(): Unit = application {
    Window(
        onCloseRequest = ::exitApplication,
        title = "NerveRuntime",
    ) {
        App()
    }
}

interface Platform {
    val name: String
    val logger: Logger
}

interface Logger {
    fun info(message: String)
    fun warning(message: String)
    fun error(message: String)
}

expect val platform: Platform

internal val info = platform.logger
internal val debugLog = platform.logger
