package dev.hunter.nerve.core.components.type

import dev.hunter.nerve.core.Value
import dev.hunter.nerve.core.components.function.Function

abstract class Type(
    val name: String,
    val parents: Array<out Type>
){
    abstract val functions: MutableMap<String, Function>

    fun isInstance(other: Value): Boolean = other.type == this

    override fun toString(): String = "Type[$name]"
}