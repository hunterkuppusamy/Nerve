package dev.hunter.nerve.core.components.type

import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.function.Function

/**
 * Like kotlin's [Unit] and java's [Void], but for Nerve
 */
object None: Value(NoneType, None)

object NoneType: Type("None", arrayOf()) {
    override val functions: MutableMap<String, Function> = mutableMapOf()
}