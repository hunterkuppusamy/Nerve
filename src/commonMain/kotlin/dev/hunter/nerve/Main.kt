package dev.hunter.nerve

import dev.hunter.nerve.core.DebugFlag
import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer

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
        
        print("Started time track...")
        start = system_nanoTime()
        
        error = nerve_run("
            print('
                Running a script from within a script! 
                I can even use variables from the calling scope ({
                    system_nanoTime() - start / 1000 / 1000
                }ms since start) in the form of a string template!
                ')
        ")
        
        if (error != null) { 
            print("Encountered an error running script within script: {error}") 
        }
        
        print(system_currentMillis() / 1000 / 60 / 60 / 24 / 7 / 52) // years since Jan 1, 1970
        
        elapsed = system_nanoTime() - start
        
        print("Elapsed {elapsed / 1000 / 1000 } ms") // nano -> micro -> milli
        
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
    println("Interpreted in ${it.time}")
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