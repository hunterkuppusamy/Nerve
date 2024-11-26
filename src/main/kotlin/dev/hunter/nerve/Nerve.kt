package dev.hunter.nerve

import dev.hunter.nerve.core.*
import dev.hunter.nerve.core.components.function.Function
import dev.hunter.nerve.core.components.token.Identifier
import dev.hunter.nerve.core.components.type.Type
import dev.hunter.nerve.core.standard.PrimitiveTypes
import dev.hunter.nerve.core.standard.StandardLibrary

@Suppress("unused")
/**
 * API
 */
object Nerve {
    var globalContext = NerveContext()
}

class NerveContext(
    val flags: EnumSet<Flag> = EnumSet.none(),
) {
    private var _logger: NerveLogger = NerveLogger(this)

    val logger get() = _logger

    val types: MutableSet<Type> = HashSet(PrimitiveTypes)

    fun getType(name: Identifier): Type {
        return types.firstOrNull { it.name == name.name } ?: throw ParseException("Type $name is undefined")
    }

    val globalFunctions: MutableMap<String, Function> = HashMap(StandardLibrary.functions)

    fun run(data: CharArray, log: (LogContext) -> Unit = { println("Script: ${it.msg}") }, vararg debug: Flag): Throwable? {
        val flags = EnumSet.of(*debug)
        val context = NerveContext(flags)
        context.logger.logMethod = log
        try{
            val tokens = Tokenizer(context, data).tokenize()
            val nodes = Parser(context, tokens).parse()
            val it = Interpreter(context, script = nodes)
            return it.interpret()
        }catch(t: Throwable){
            return t
        }
    }

    fun debug(flag: EnumSet<Flag> = EnumSet.none(), message: () -> String) {
        logger.debug(flag, message)
    }

    fun debug(vararg flags: Flag, message: () -> String) {
        debug(EnumSet.of(*flags), message)
    }
}

class NerveLogger(
    context: NerveContext
): Contextual(context) {
    var logMethod: (LogContext) -> Unit = { println(it.msg) }
        get() {
            return field
        }
        set(value) {
            field = value
        }

    fun debug(flag: EnumSet<Flag> = EnumSet.none(), message: () -> String) {
        if (!context.flags.containsAll(flag)) return
        val ctx = LogContext(context, message())
        logMethod(ctx)
    }

    fun debug(vararg flags: Flag, message: () -> String) {
        debug(EnumSet.of(*flags), message)
    }
}

abstract class Contextual(
    val context: NerveContext
)

data class LogContext(
    val nerveContext: NerveContext,
    val msg: String
)