package dev.hunter.nerve

import kotlinx.coroutines.runBlocking
import java.nio.CharBuffer
import java.util.logging.Logger

/**
 * Since Nerve is not intended to be fully standalone, this is a common API access point
 */
object Nerve{
    internal var props = NerveProperties()
    fun setProperties(properties: NerveProperties){
        props = properties
    }

    private fun run0(line: String){
        val tokens = Tokenizer(CharBuffer.wrap(line)).tokenize()
        val nodes = Parser(tokens).parse()
        val execute = Interpreter()
        execute.interpret(nodes)
    }

    fun run(line: String){
        run0(line)
    }
}

data class NerveProperties(
    val infoLogger: Logger = Logger.getLogger("Nerve"),
    val debugLogger: Logger = Logger.getLogger("Nerve - Debug"),
)

internal val info = Nerve.props.infoLogger
internal val debug = Nerve.props.debugLogger

fun main(){
    runBlocking{
        Nerve.run("""
            fun testReturningExpression(arg){
                return arg + 10
            }
            
            print("return = {testReturningExpression(46)}")
        """.trimIndent())

        Nerve.run("""
            fun helloWorld(arg){
                print("Hello, {arg} world!")
            }
            
            fun someValue(arg){
                return 8
            }
            
            print(someValue(5))
            
            helloWorld(1214.22)
            
            twelve = 12
            
            hello = twelve + 10
            
            print("hello = {hello}")
            
            fun recurse(){
                print("i will recurse infinitely")
            }
            
            recurse()
        """)
    }
}