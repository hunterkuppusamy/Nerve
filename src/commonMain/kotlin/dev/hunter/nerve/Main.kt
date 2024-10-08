package dev.hunter.nerve

import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer

fun main() {
    val tok = Tokenizer("""
        fun concat(string1, string2){
            print('{string1} + {string2}')
        }
        
        hello = "hello,"
        
        concat(hello, "world!")
        
        fun coolPrint(thing) {
            print('cool print: {thing}')
            return thing
        }
        
        fun helloWorld(arg){ 
            if (arg == 1) {
                print("arg = 1!")
                if (true) {
                    print("this should be logged")
                }
            } 
            print('argument = {coolPrint(arg + 1)} !!') 
        }
        
        helloWorld(1)
        
        x = 52
        
        y = 1 - 5 + x
        
        print( y )
        
    """.trimIndent().toCharArray()).tokenize()
    val nodes = Parser(tok).parse()
    println(nodes)
    val it = Interpreter()
    it.interpret(nodes)
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

internal val logger get() = platform.logger
internal val debugLog get() = platform.logger