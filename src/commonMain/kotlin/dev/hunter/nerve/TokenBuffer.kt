package dev.hunter.nerve

import dev.hunter.nerve.core.components.Token
import kotlin.reflect.KClass

class TokenBuffer(
    arr: Collection<Token>
) {
    private val _arr = ArrayList(arr)
    private var _index = 0
    val size get() = _arr.size
    val pos get() = _index

    fun move(offset: Int) {
        _index += offset
    }

    fun <T: Token> get(clazz: KClass<T>, offset: Int = 0, msg: (Token?) -> String? = { null }): T {
        val pos = _index + offset
        if (pos < 0) throw IllegalArgumentException("Under bounds access with index $_index and offset $offset")
        if (pos >= _arr.size) throw IllegalArgumentException("End of buffer reached with index $_index and offset $offset")
        val c = _arr[pos]
        _index++
        if (!clazz.isInstance(c)) throw UnexpectedTokenException(msg(c as? Token?) ?: "Unexpected token $c")
        @Suppress("UNCHECKED_CAST") // I just check it
        return c as T
    }

    inline fun <reified T: Token> get(msg: String? = null): T {
        return get(T::class, 0, { msg })
    }

    inline fun <reified T: Token> get(noinline msg: (Token?) -> String?): T {
        return get(T::class, 0, msg)
    }

    inline fun <reified T: Token> peek(offset: Int = 0, msg: String? = null): T? {
        val ret = try{ get(T::class, offset, { msg }) } catch (_: IllegalArgumentException) { null }
        move(-1)
        return ret
    }

    class UnexpectedTokenException(msg: String): Exception(msg)
}