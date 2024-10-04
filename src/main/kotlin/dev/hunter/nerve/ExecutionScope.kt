package dev.hunter.nerve

import java.util.concurrent.atomic.AtomicLong
import kotlin.math.pow

@Suppress("MemberVisibilityCanBePrivate")
abstract class ExecutionScope{
    /**
     * All variables within this scope
     */
    internal abstract val variables: HashMap<String, Any?>

    /**
     * All functions within this scope
     */
    internal abstract val functions: HashMap<String, Function>

    /**
     * A reference to the global scope
     */
    abstract val global: GlobalExecutionScope

    /**
     * Whether the scope should log debug information
     */
    abstract val debug: Boolean

    /**
     * Total execution time in ms
     */
    private val _tms = AtomicLong()

    /**
     * Interpret a [Node]
     */
    fun interpret(node: Node){
        when (node){
            is OfValue -> computeValuable(node)
            is VariableAssignment -> {
                setVar(node.variable, computeValuable(node.expression))
            }
            is FunctionDefinition -> {
                functions[node.function.value] = node
            }
        }
    }

    private fun computeFunctionArguments(function: FunctionInvoke): List<Any?> {
        val args = function.arguments.map {
            when (it) {
                is Token.Identifier -> {
                    getVar(it)
                }
                is FunctionInvoke -> invokeFunction(it.function, computeFunctionArguments(it))
                is BinaryExpression -> computeBinaryExpression(it)
                is OfValue -> computeValuable(it)
                else -> throw RuntimeException("Invoked with wrong parameters? Parse error? $function")
            }
        }
        return args
    }

    fun computeValuable(node: OfValue): Any? {
        return when (node) {
            is FunctionInvoke -> invokeFunction(node.function, computeFunctionArguments(node))
            is Constant -> node.value
            is Token.Identifier -> getVar(node)
            is BinaryExpression -> computeBinaryExpression(node)
            is TemplateString -> {
                val i = node.line.iterator()
                val temps = node.templates
                val chars = CharBuilder()
                while (i.hasNext()) {
                    val c = i.next()
                    if (c == TEMPLATE_START_CHAR){
                        val intC = CharBuilder()
                        while(i.hasNext()) {
                            val n = i.next()
                            if (n == TEMPLATE_END_CHAR) break
                            intC.append(n)
                        }
                        val int = intC.toString().toInt()
                        val temp = temps[int]
                        val replace = computeValuable(temp)
                        chars.append(replace.toString())
                    } else chars.append(c)
                }
                chars.toString()
            }
            else -> throw RuntimeException("Unhandled valuable expression $node")
        }
    }

    fun computeBinaryExpression(node: BinaryExpression): Any {
        val left = computeValuable(node.left)
        val right = computeValuable(node.right)
        if (left == null) throw RuntimeException("Left side is null -> $node")
        if (right == null) throw RuntimeException("Right side is null -> $node")
        when (val op = node.operator) {
            OperatorKind.ADD -> {
                return if (left is Number && right is Number) {
                    left.toDouble() + right.toDouble()
                } else if (left is String && right is String) {
                    left + right
                } else throw RuntimeException("Binary operands $left or $right is not a number or string")
            }
            OperatorKind.SUBTRACT -> {
                return if (left is Number && right is Number) {
                    left.toDouble() - right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            OperatorKind.MULTIPLY -> {
                return if (left is Number && right is Number) {
                    left.toDouble() * right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            OperatorKind.DIVIDE -> {
                return if (left is Number && right is Number) {
                    left.toDouble() / right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            OperatorKind.POWER -> {
                return if (left is Number && right is Number) {
                    left.toDouble().pow(right.toDouble())
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            else -> throw RuntimeException("Unhandled operator $op")
        }
    }

    fun invokeFunction(function: Token.Identifier, args: List<Any?>): Any? {
        val func = functions[function.value] ?: throw RuntimeException("Function '${function.value}' is undefined")
        return func.invoke(this, args)
    }

    fun setVar(id: Token.Identifier, value: Any?){
        variables[id.value] = value
    }

    fun getVar(id: Token.Identifier): Any? {
        if (!variables.containsKey(id.value)) throw RuntimeException("#${id.line} -> Variable '${id.value}' is not defined'")
        val ret = variables[id.value]
        return ret
    }
}

class GlobalExecutionScope(
    initialVars: Map<String, Any?>,
    override val debug: Boolean = false
) : ExecutionScope() {
    constructor(vararg initial: Pair<String, Any?>): this(initial.toMap())
    override val variables: HashMap<String, Any?> = HashMap()
    override val functions: HashMap<String, Function> = HashMap()
    override val global: GlobalExecutionScope = this
    init {
        functions.putAll(BuiltInFunctions.entries.associateBy { it.name.lowercase() })
        variables.putAll(initialVars)
    }
}

class LocalExecutionScope(
    parent: ExecutionScope,
): ExecutionScope() {
    override val variables: HashMap<String, Any?> = HashMap()
    override val functions: HashMap<String, Function> = HashMap()
    override val global: GlobalExecutionScope = parent.global
    override val debug: Boolean = parent.debug
    init {
        variables.putAll(parent.variables)
        functions.putAll(parent.functions)
    }
}