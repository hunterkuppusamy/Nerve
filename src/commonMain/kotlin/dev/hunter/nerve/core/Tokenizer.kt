package dev.hunter.nerve.core

import dev.hunter.nerve.CanDebug
import dev.hunter.nerve.EnumSet
import dev.hunter.nerve.core.components.*
import dev.hunter.nerve.platform
import org.jetbrains.annotations.ApiStatus.NonExtendable
import kotlin.collections.ArrayList

@NonExtendable
open class Tokenizer(
    arr: CharArray,
    val debug: EnumSet<DebugFlag> = EnumSet<DebugFlag>()
): CanDebug {
    private val literalBuffer = StringBuilder()
    private val tokens = ArrayList<Token>()
    open var line = 1

    private val buf = CharBuffer(arr)

    /**
     * Tokenizes the [buf]. Something like:
     * ```kotlin
     * fun helloWorld(arg){
     *   print("Hello, World!")
     *   print("I was passed arg {arg}!")
     *   return 15
     * }
     * ```
     * Would get tokenized to an array like this:
     * ```text
     * Strings
     * Strings
     * Strings
     * Strings
     * Strings
     * ```
     *
     * This array can be understood by the [Parser] to create a list of [Nodes][Node] to be interpreted by the [Interpreter]
     */
    fun tokenize(): List<Token> {
        while(buf.hasRemaining()) {
            val c = buf.peek()
            if (c.isNewLineChar) dropToNextLine()
            else if (c.isWhitespace()) dropWhitespace()
            else if (c.isLetter()) lexIdentifierOrKeyword()
            else if (c.isDigit()) lexNumber()
            else if (c == '\'' || c == '\"') lexString()
            else lexSpecial()
        }
        return tokens
    }

    private fun lexSpecial() {
        when (buf.consume()){
            '(' -> tokens.add(Separator.LeftParen(line))
            ')' -> tokens.add(Separator.RightParen(line))
            ',' -> tokens.add(Separator.Comma(line))
            '{' -> tokens.add(Separator.LeftBrace(line))
            '}' -> tokens.add(Separator.RightBrace(line))
            '[' -> tokens.add(Separator.LeftBracket(line))
            ']' -> tokens.add(Separator.RightBracket(line))
            '+' -> tokens.add(Operator.Add(line))
            '-' -> tokens.add(Operator.Subtract(line))
            '*' -> tokens.add(Operator.Multiply(line))
            '^' -> tokens.add(Operator.Exponentiate(line))
            '/' -> {
                val next = buf.peek()
                if (next == '/') {
                    buf.consume()
                    dropToEndOfLine()
                } else tokens.add(Operator.Divide(line))
            }
            '!' -> {
                val next = buf.peek()
                if (next == '=') {
                    buf.consume()
                    tokens.add(Operator.IsNotEqual(line))
                } else throwTokenException("Unexpected exclamation point")
            }
            '=' -> {
                val next = buf.peek()
                if (next == '=') {
                    buf.consume()
                    tokens.add(Operator.IsEqual(line))
                } else tokens.add(Operator.Assign(line))
            }
            '.' -> {
                val one = buf.peek()
                val two = buf.peek(1)
                if (one == '.' && two == '.'){
                    buf.consume(); buf.consume()
                    tokens.add(Operator.Range(line))
                }
            }
            else -> throwTokenException("Unhandled special character")
        }
    }

    private fun lexNumber() {
        literalBuffer.append(buf.consume())
        var isFloating = false
        while(buf.hasRemaining()) {
            val c = buf.consume()
            if (c == '.' && isFloating) throwTokenException("Two decimals in number")
            else if (c == '.') isFloating = true
            else if (!c.isDigit()) {
                buf.pull()
                break
            }
            literalBuffer.append(c)
        }
        val literal = literalBuffer.toString()
        literalBuffer.clear()
        val token = if (isFloating) Constant.FloatingLiteral(line, literal.toDouble()) else Constant.NaturalLiteral(
            line,
            literal.toLong()
        )
        tokens.add(token)
    }


    private val templateBuffer = ArrayList<Any>(5)

    private fun lexString() {
        var isTemplate = false
        var escaped = false
        // TODO fix string escaping and control characters
        val first = buf.consume()
        while(buf.hasRemaining()) {
            val c = buf.consume()
            if (c == '\\') escaped = true
            if (!escaped && c == first) break
            else if (!escaped && c == TEMPLATE_START_CHAR) {
                isTemplate = true
                val literal = literalBuffer.toString()
                literalBuffer.clear()
                if (literal.isNotBlank()) templateBuffer.add(Constant.StringLiteral(line, literal))
                val chars = CharBuilder()
                do {
                    val t = buf.consume()
                    if (t == TEMPLATE_END_CHAR) break
                    chars.append(t)
                } while (buf.hasRemaining())
                val charsInside = chars.toString() // everything inside the template
                val tokens = StringTemplateTokenizer(this, charsInside).tokenize()
                templateBuffer.add(tokens)
            } else literalBuffer.append(c)
            escaped = false
        }
        val literal = literalBuffer.toString()
        literalBuffer.clear()
        if (!isTemplate) {
            tokens.add(Constant.StringLiteral(line, literal))
        } else {
            if (literal.isNotBlank())
                templateBuffer.add(Constant.StringLiteral(line, literal))
            tokens.add(Token.StringTemplate(line, ArrayList(templateBuffer)))
            templateBuffer.clear()
        }
    }

    private fun dropToEndOfLine(){
        while(buf.hasRemaining()){
            val c = buf.consume()
            if (c == '\n' || c == '\r') break
        }
    }

    private fun dropToNextLine(){
        buf.consume()
        line++
    }

    private fun lexIdentifierOrKeyword() {
        literalBuffer.append(buf.consume())
        while (buf.hasRemaining()) {
            val c = buf.consume()
            if (c.isWhitespace() || !c.isValidIdentChar) {
                buf.pull()
                break
            }
            literalBuffer.append(c)
        }
        val ident = literalBuffer.toString()
        literalBuffer.clear()
        if (ident == "false") {
            tokens.add(Constant.BooleanLiteral(line, false))
            return
        } else if (ident == "true") {
            tokens.add(Constant.BooleanLiteral(line, true))
            return
        }
        var token = Keyword.byName(ident, line) ?: Token.Identifier(line, ident)
        if (token is Keyword.Var && buf.peek() == '*'){
            buf.consume()
            token = Keyword.MutVar(line)
        }
        tokens.add(token)
    }

    private fun throwTokenException(msg: String): Nothing {
        throw TokenizerException("line #$line at char ${buf.peek(-1)} -> $msg")
    }

    private fun dropWhitespace() {
        while(buf.hasRemaining()){
            if (!buf.consume().isWhitespace()) {
                buf.pull()
                break
            }
        }
    }

    override fun debug(flag: DebugFlag?, message: () -> String) {
        if (if (flag != null) debug.contains(flag) else debug.size > 0) platform.logger.info("[${flag ?: "ANY"}] DEBUG: ${message()}") // lazily invoke the message, only if debugging
    }
}

class StringTemplateTokenizer(
    private val parent: Tokenizer,
    templateSection: String
): Tokenizer(templateSection.toCharArray(), parent.debug) {
    override var line: Int
        get() = parent.line
        set(value) {
            parent.line = value
        }
}

val Char.isValidIdentChar: Boolean get() {
    return if (this.isLetterOrDigit()) true else if (this == '_' || this == '-') true else false
}

val Char.isNewLineChar: Boolean get() = if (
        this == '\u000A' || this == '\u000D' || this == '\u0085' || this == '\u2424'
    ) true else false

class TokenizerException(msg: String?) : Exception(msg)

class CharBuilder: Appendable {
    private val delegate = StringBuilder()
    override fun append(value: Char): CharBuilder {
        delegate.append(value)
        return this
    }
    override fun toString(): String = delegate.toString()
    override fun append(value: CharSequence?): Appendable {
        delegate.append(value ?: "null")
        return this
    }
    override fun append(value: CharSequence?, startIndex: Int, endIndex: Int): Appendable {
        val new = (value ?: "null").slice(startIndex..endIndex)
        delegate.append(new)
        return this
    }
}

class CharBuffer(
    private val arr: CharArray,
) {
    private var pos = 0
    fun consume(): Char {
        return arr[pos++]
    }
    fun pull(n: Int = 1) {
        pos -= n
    }
    fun peek(n: Int = 0): Char {
        return arr[pos + n]
    }
    fun hasRemaining(): Boolean {
        return pos < arr.size
    }
}