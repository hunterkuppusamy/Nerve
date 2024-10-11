package dev.hunter.nerve

import dev.hunter.nerve.core.DebugFlag
import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer
import java.util.*

fun main() {
    val tok = Tokenizer(
        """
        fun concat(string1, string2){
            print(
                '{
                    string1
                } + {
                    string2
                }'
            )
        }
        
        hello = "hello,"
        
        concat(hello, "world!")
        
        fun helloWorld(arg){ 
            // this is a comment ;)
            if (arg == 1) {
                print("arg = 1!")
                if (true) {
                    print("this should be logged")
                }
            } 
            one = 1
            print('argument = {arg - one} !!') 
        }
        
        helloWorld(1)
        
        x = 52
        
        y = 1 - 5 + x
        
        print( y )
        
    """.trimIndent().toCharArray()
    ).tokenize()
    val nodes = Parser(tok).parse()
    println(nodes)
    val it = Interpreter(debug = EnumSet(DebugFlag.STATE))
    it.interpret(nodes)?.printStackTrace()
    // platform.entry()
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