package dev.hunter.nerve

import dev.hunter.nerve.core.Interpreter
import dev.hunter.nerve.core.Parser
import dev.hunter.nerve.core.Tokenizer
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.lang.ref.WeakReference

fun main() {
    Nerve.globalContext.debug { "Hello, just loading the class" }
    loadClassesFromPackage("dev.hunter.nerve.core")
    loadClassesFromPackage("dev.hunter.nerve.core.components")
    val tok = Tokenizer(data = File(Nerve.javaClass.classLoader.getResource("test.nrv")!!.toURI())).tokenize()
    println(tok)
    val nodes = Parser(tokens = tok).parse()
    val puter = Interpreter(script = nodes)
    puter.interpret()?.printStackTrace()
    println("Interpreted in ${puter.time}")
    // platform.entry()
}

fun loadClassesFromPackage(pkgname: String) {
    val classLoader = Nerve.javaClass.classLoader
    val stream = classLoader.getResourceAsStream(pkgname.replace(".", "/"))!!
    val reader = BufferedReader(InputStreamReader(stream))
    reader.lines()
        .map { "${pkgname}.$it" }
        .filter { it.endsWith(".class") }
        .map { it.removeSuffix(".class") }
        .map { Class.forName(it) }
        .forEach { println("Loaded ${it.simpleName}!") }
}