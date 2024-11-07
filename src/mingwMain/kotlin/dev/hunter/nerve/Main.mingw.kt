package dev.hunter.nerve

actual val platform: Platform = object: Platform {
    override val name: String
        get() = TODO("Not yet implemented")
    override val logger: Logger
        get() = TODO("Not yet implemented")
    override val entry: () -> Unit = {
        throw InterpretationException("HELP")
    }
}