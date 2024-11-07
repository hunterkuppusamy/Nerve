package dev.hunter.nerve

import dev.hunter.nerve.core.DebugFlag
import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer
import kotlin.time.measureTime

fun main() {
    val tok = Tokenizer("""
        fun test(arg) {
            print(arg)
        }
        
        test("yo")
        
        var* three = 3
        var two = 1
        three = 4
        
        fun fortest() {
            for l in (2 ... 5){
                print("Iter {l}")
                if (l == 4) { 
                    print('returned')
                    return l 
                }
            }
        }
        
        fortest()
        
        var msInYear = 1000 * 60 * 60 * 60 * 24 * 7 * 52
        print("There are {msInYear}ms in a year")
        print("")
        
        //V = zeros(4)
        //
        //for i = 1:4
        //  V(i) = (i - 1) / 2
        //end
        
    """.trimIndent().toCharArray()
    ).tokenize()
    println(tok)
    val nodes = Parser(tok, debug = EnumSet(DebugFlag.STATE)).parse()
    val it = Interpreter(debug = EnumSet.all())
    val elapsed = measureTime{ it.interpret(nodes)?.printStackTrace() }
    println("Interpreted in ${it.time}")
    println("TOTAL (with coroutine overhead): $elapsed")
    // platform.entry()
}

@Suppress("unused")
/**
 * API
 */
object Nerve {
    fun run(data: CharArray, log: (String) -> Unit = { println("Script: $it") }, vararg debug: DebugFlag): Throwable? {
        try{
            val tokens = Tokenizer(data).tokenize()
            val nodes = Parser(tokens).parse()
            val it = Interpreter(debug = EnumSet(*debug), logMethod = log)
            return it.interpret(nodes)
        }catch(t: Throwable){
            return t
        }
    }
}

interface Platform {
    val name: String
    val logger: Logger
    val entry: () -> Unit
}

expect val platform: Platform

interface Logger {
    fun info(message: String)
    fun warning(message: String)
    fun error(message: String)
}

internal interface CanDebug {
    fun debug(flag: DebugFlag? = null, message: () -> String)
}