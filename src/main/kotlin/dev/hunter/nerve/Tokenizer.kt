package dev.hunter.nerve

import java.nio.CharBuffer

open class Tokenizer(
    private val buf: CharBuffer,
    val debug: Boolean = false
) {
    private val literalBuffer = StringBuilder()
    private val tokens = ArrayList<Token>()
    open var line = 1

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
     * Keyword[FUN] Identifier[helloWorld] LEFT_PAREN Identifier[arg] RIGHT_PAREN LEFT_BRACE
     * Identifier[print] LEFT_PAREN LiteralString["Hello, World!"] RIGHT_PAREN
     * Identifier[print] LEFT_PAREN LiteralString["I was passed arg {arg}!"] RIGHT_PAREN
     * Keyword[RETURN] LiteralInteger[15]
     * RIGHT_BRACE
     * ```
     *
     * This array can be understood by the [Parser] to create a list of [Nodes][Node] to be interpreted by the [Interpreter]
     */
    fun tokenize(): Array<Token> {
        while(buf.hasRemaining()) {
            val c = buf.get()
            if (c == '\n' || c == '\r') skipLineTermination()
            if (c.isWhitespace()) skipWhitespace()
            else if (c.isLetter()) lexIdentifierOrKeyword(c)
            else if (c == '\'' || c == '\"') lexString(c)
            else if (c.isDigit()) lexNumber(c)
            else lexSpecial(c)
        }
        return tokens.toTypedArray()
    }

    private fun lexSpecial(c: Char) {
        when (c){
            '(' -> tokens.add(Token.Separator(line, SeparatorKind.LEFT_PAREN))
            ')' -> tokens.add(Token.Separator(line, SeparatorKind.RIGHT_PAREN))
            '{' -> tokens.add(Token.Separator(line, SeparatorKind.LEFT_BRACE))
            '}' -> tokens.add(Token.Separator(line, SeparatorKind.RIGHT_BRACE))
            '[' -> tokens.add(Token.Separator(line, SeparatorKind.LEFT_BRACKET))
            ']' -> tokens.add(Token.Separator(line, SeparatorKind.RIGHT_BRACKET))
            '+' -> tokens.add(Token.Operator(line, OperatorKind.ADD))
            '-' -> tokens.add(Token.Operator(line, OperatorKind.SUBTRACT))
            '*' -> tokens.add(Token.Operator(line, OperatorKind.MULTIPLY))
            '^' -> tokens.add(Token.Operator(line, OperatorKind.POWER))
            '/' -> tokens.add(Token.Operator(line, OperatorKind.DIVIDE))
            '=' -> tokens.add(Token.Equals(line))
            else -> throwTokenException("Unhandled character $c")
        }
    }

    private fun lexNumber(first: Char) {
        literalBuffer.append(first)
        var isFloating = false
        while(buf.hasRemaining()) {
            val c = buf.get()
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
        val token = if (isFloating) Token.FloatingLiteral(line, literal.toDouble()) else Token.IntegerLiteral(
            line,
            literal.toLong()
        )
        tokens.add(token)
    }

    private fun lexString(first: Char) {
        var isTemplate = false
        val templateTokens = ArrayList<Array<Token>>()
        val templateString = ArrayList<String>()
        while(buf.hasRemaining()) {
            val c = buf.get()
            if (c == first) break
            else if (c == TEMPLATE_START_CHAR) {
                isTemplate = true
                val literal = literalBuffer.toString()
                literalBuffer.clear()
                templateString.add(literal)
                val chars = CharBuilder()
                do {
                    val t = buf.get()
                    if (t == TEMPLATE_END_CHAR) break
                    chars.append(t)
                } while (buf.hasRemaining())
                val charsInside = chars.toString() // everything inside the template
                val tokens = StringTemplateTokenizer(this, charsInside).tokenize()
                templateTokens.add(tokens)
            } else literalBuffer.append(c)
        }
        val literal = literalBuffer.toString()
        literalBuffer.clear()
        if (!isTemplate) {
            tokens.add(Token.StringLiteral(line, literal))
        } else {
            tokens.add(Token.TemplateStringLiteral(line, templateString.toTypedArray(), templateTokens.toTypedArray()))
        }
    }

    private fun skipLineTermination(){
        line++
        while(buf.hasRemaining()){
            val c = buf.get()
            if (c != '\n' && c != '\r') {
                buf.pull()
                break
            }
            line++
        }
    }

    private fun lexIdentifierOrKeyword(first: Char) {
        literalBuffer.append(first)
        // do keyword things
        while (buf.hasRemaining()) {
            val c = buf.get()
            if (c.isWhitespace() || !c.isValidIdentChar) {
                buf.pull()
                break
            }
            literalBuffer.append(c)
        }
        val ident = literalBuffer.toString()
        literalBuffer.clear()
        val keyword = KeywordKind.entries.firstOrNull { it.str == ident }
        val token =
            if (keyword != null) Token.Keyword(line, keyword)
            else Token.Identifier(line, ident)
        tokens.add(token)
    }

    private fun CharBuffer.pull(n: Int = 1){
        this.position(buf.position() - n)
    }

    private fun throwTokenException(msg: String): Nothing {
        throw TokenizerException("line #$line -> $msg")
    }

    private fun skipWhitespace() {
        while(buf.hasRemaining()){
            if (!buf.get().isWhitespace()) {
                buf.pull()
                break
            }
        }
    }
}

class StringTemplateTokenizer(
    private val parent: Tokenizer,
    templateSection: String
): Tokenizer(CharBuffer.wrap(templateSection), parent.debug) {
    override var line: Int
        get() = parent.line
        set(value) {
            parent.line = value
        }
}

val Char.isValidIdentChar: Boolean get() {
    return if (this.isLetterOrDigit()) true else if (this == '_' || this == '-') true else false
}

sealed class Token {
    abstract val line: Int
    data class Operator(
        override val line: Int,
        val kind: OperatorKind
    ): Token()
    data class Identifier(
        override val line: Int,
        val value: String
    ): Token(), OfValue { override fun toString(): String = "|$value|" }
    data class StringLiteral(
        override val line: Int,
        override val value: String
    ): Token(), Constant { override fun toString(): String = "'$value'" }
    class TemplateStringLiteral(
        override val line: Int,
        val value: Array<String>,
        val templates: Array<Array<Token>>
    ): Token(), OfValue { override fun toString(): String = "TemplateStringLiteral[${value.contentDeepToString()}, ${templates.contentDeepToString()}]" }
    data class Keyword(
        override val line: Int,
        val kind: KeywordKind
    ): Token(){ override fun toString(): String = "!$kind!" }
    data class IntegerLiteral(
        override val line: Int,
        override val value: Long
    ): Token(), Constant { override fun toString(): String = "$value" }
    data class FloatingLiteral(
        override val line: Int,
        override val value: Double
    ): Token(), Constant { override fun toString(): String = "$value" }
    data class Separator(
        override val line: Int,
        val kind: SeparatorKind
    ): Token() { override fun toString(): String = "$kind" }
    data class Equals(
        override val line: Int
    ): Token(){ override fun toString(): String = "!ASSIGN!" }
}

interface OfValue: Node

interface Constant: OfValue {
    val value: Any
}

enum class OperatorKind{
    ADD,
    SUBTRACT,
    DIVIDE,
    MULTIPLY,
    POWER,
    MOD,
    EQUALITY,
    INEQUALITY,
    GREATER_THAN,
    LESS_THAN,
}

enum class SeparatorKind{
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    LEFT_BRACKET,
    RIGHT_BRACKET,
}

enum class KeywordKind{
    IF,
    WHILE,
    DO,
    RETURN,
    FUN;

    val str: String = this.name.lowercase()
}

class TokenizerException(msg: String?) : Exception(msg)

class CharBuilder: Appendable {
    private val delegate = StringBuilder()
    override fun append(char: Char): CharBuilder {
        delegate.append(char)
        return this
    }
    override fun toString(): String = delegate.toString()
    override fun append(seq: CharSequence?): java.lang.Appendable {
        delegate.append(seq ?: "null")
        return this
    }
    override fun append(seq: CharSequence?, p1: Int, p2: Int): java.lang.Appendable {
        val new = (seq ?: "null").slice(p1..p2)
        delegate.append(new)
        return this
    }
}