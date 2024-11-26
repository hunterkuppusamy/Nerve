package dev.hunter.nerve

import dev.hunter.nerve.core.components.token.Token
import kotlin.math.min
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
        val pos = checkPos(offset)
        val c = _arr[pos]
        if (!clazz.isInstance(c)) unexpectedToken(msg)
        _index++
        @Suppress("UNCHECKED_CAST") // I just check it
        return c as T
    }

    private fun checkPos(offset: Int): Int {
        val pos = _index + offset
        if (pos < 0) throw IllegalArgumentException("Under bounds access with index $_index and offset $offset")
        var i = 0
        if (pos >= _arr.size) throw IllegalArgumentException("End of buffer reached with index $_index and offset $offset (${_arr.joinToString {
            "(#${i++}) $it"
        }})")
        return pos
    }

    fun unexpectedToken(msg: (Token?) -> String?, offset: Int = 0): Nothing {
        val pos = checkPos(offset - 1)
        val c = _arr[pos]
        val message = msg(c) ?: "Unexpected Token"
        val upper = min(pos + 2, _arr.size - 1)
        val slice = _arr.slice(pos - 2..upper).map(Any::toString).toMutableList()
        slice[2] = "→${slice[2]}←"
        val str = slice.joinToString()
        throw UnexpectedTokenException("(#${c.line}) $message. { $str }")
    }

    inline fun <reified T: Token> get(msg: String? = null): T {
        return get(T::class, 0) { msg }
    }

    inline fun <reified T: Token> get(noinline msg: (Token?) -> String?): T {
        return get(T::class, 0, msg)
    }

    inline fun <reified T: Token> peek(offset: Int = 0, msg: String? = null): T? {
        val ret = try{
            get(T::class, offset) { msg }
        } catch (_: IllegalArgumentException) { null }
        move(-1)
        return ret
    }

    fun slice(r: IntRange): TokenBuffer {
        return TokenBuffer(_arr.slice(r))
    }

    fun slice(to: Int): TokenBuffer {
        return TokenBuffer(_arr.slice(_index..to))
    }

    fun remaining(): TokenBuffer {
        return slice(_arr.size - 1)
    }

    override fun toString(): String = _arr.toString()

    class UnexpectedTokenException(msg: String): Exception(msg)
}