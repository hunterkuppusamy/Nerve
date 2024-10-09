package dev.hunter.nerve.core

import dev.hunter.nerve.debugLog
import kotlin.math.pow
import kotlin.math.sign
import kotlin.time.measureTime

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

    open val interpreter: Interpreter get() = global.interpreter

    /**
     * Total execution time in ms
     */
    open var time: Double get() = global.time
        set(value) { global.time = value }

    /**
     * Interpret a [Node]
     */
    fun interpret(node: Node){
        val start = measureTime {
            when (node){
                is OfValue -> computeValuable(node)
                is VariableAssignment -> {
                    setVar(node.variable, computeValuable(node.expression))
                }
                is FunctionDefinition -> {
                    functions[node.function.value] = node
                }
                is IfStatement -> {
                    val run = computeValuable(node.operand)
                    val bool = run as? Boolean
                    if (bool == true) {
                        for (line in node.body) {
                            if (line is BreakStatement) break
                            interpret(line)
                        }
                    }
                }
            }
        }
        val elapsed = start.inWholeMicroseconds / 1000.0
        time += elapsed
    }

    fun computeValuable(node: OfValue): Any? {
        return when (node) {
            is FunctionInvoke -> computeInvocation(node)
            is Constant -> node.value
            is Token.Identifier -> getVar(node)
            is BinaryExpression -> computeBinaryExpression(node)
            is TemplateString -> {
                val i = node.line.iterator()
                var str = ""
                while (i.hasNext()) {
                    val value = i.next()
                    str += computeValuable(value)
                }
                str
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
            OperatorKind.EQUALITY -> {
                return left == right
            }
            OperatorKind.MOD -> {
                return if (left is Number && right is Number) {
                    left.toDouble().mod(right.toDouble())
                }else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            OperatorKind.LESS_THAN -> {
                return if (left is Comparable<*> && right is Comparable<*>) {
                    (left as Comparable<Any>).compareTo(right).sign == -1
                }else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            OperatorKind.INEQUALITY -> {
                return left != right
            }
            else -> throw RuntimeException("Unhandled operator $op")
        }
    }

    fun computeInvocation(invoke: FunctionInvoke): Any? {
        val args = invoke.arguments.map {
            if (it is OfValue) computeValuable(it)
            else throw RuntimeException("Invoked with wrong parameters? Parse error? $invoke")
        }
        val func = functions[invoke.function.value] ?: throw RuntimeException("Function '${invoke.function.value}' is undefined")
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
    override val interpreter: Interpreter
) : ExecutionScope() {
    override val variables: HashMap<String, Any?> = HashMap()
    override val functions: HashMap<String, Function> = HashMap()
    override val global: GlobalExecutionScope = this
    override var time: Double = 0.0
    override val debug: Boolean get() = interpreter.debug
    init {
        functions.putAll(FunctionRegistry.entries)
        if (debug) {
            debugLog.info("Starting with initial vars: ${interpreter.initialVars}")
        }
        variables.putAll(interpreter.initialVars)
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