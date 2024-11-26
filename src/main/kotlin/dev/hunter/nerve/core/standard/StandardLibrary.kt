package dev.hunter.nerve.core.standard

import dev.hunter.nerve.core.components.function.Function
import dev.hunter.nerve.core.components.type.Type
import dev.hunter.nerve.core.standard.functions.Print

object StandardLibrary: Type("Standard", arrayOf()) {
    override val functions: MutableMap<String, Function> = listOf(
        Print
    ).associateBy { it.name }.toMutableMap()
}