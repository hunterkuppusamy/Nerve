package dev.hunter.nerve

actual val platform: Platform = object: Platform {
    override val name: String= "JVM@${System.getenv("JAVA_HOME")}"
    override val logger: Logger = object: Logger {
        override fun info(message: String) = println(message)
        override fun warning(message: String) = println("WARNING: $message")
        override fun error(message: String) = println("ERROR: $message")
    }
}