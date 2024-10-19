package dev.hunter.nerve.core

import dev.hunter.nerve.EnumSet
import kotlin.math.pow
import kotlin.math.sign
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.measureTime

@Suppress("MemberVisibilityCanBePrivate")
abstract class ExecutionScope{
    /**
     * All variables within this scope
     * @see LocalExecutionScope.variables
     * @see GlobalExecutionScope.variables
     */
    internal abstract val variables: HashMap<String, Any?>

    /**
     * All functions within this scope
     * @see LocalExecutionScope.functions
     * @see GlobalExecutionScope.functions
     */
    internal abstract val functions: HashMap<String, Function>

    /**
     * A reference to the global scope
     */
    abstract val global: GlobalExecutionScope

    /**
     * Whether the scope should log debug information
     */
    abstract val debug: EnumSet<DebugFlag>

    open val interpreter: Interpreter get() = global.interpreter

    /**
     * Total execution time in ms
     */
    var time: Duration = 0.nanoseconds

    /**
     * Interpret a [Node]
     */
    fun interpret(node: Node){
        val elapsed = measureTime {
            when (node){
                is OfValue -> computeValuable(node)
                is VariableAssignment -> {
                    setVar(node.variable, computeValuable(node.expression))
                }
                is FunctionDefinition -> {
                    functions[node.function.name] = node
                }
                is IfStatement -> {
                    val op =
                        // optimised evaluation of literals
                        if ((node.condition as? Constant.NaturalLiteral)?.value == 1L || (node.condition as? Constant.BooleanLiteral)?.value == true) true
                        else {
                            val value = computeValuable(node.condition)
                            value as? Boolean ?: (value as? Number == 1)
                        }
                    if (op) {
                        for (line in node.body) {
                            if (line is BreakStatement) break
                            interpret(line)
                        }
                    }
                }
            }
        }
        interpreter.debug(DebugFlag.TIMINGS) { "Node '$node' interpreted in $elapsed" }
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
            is Keyword.Null -> null
            else -> throw RuntimeException("Unhandled valuable expression $node")
        }
    }

    fun computeBinaryExpression(node: BinaryExpression): Any {
        val left = computeValuable(node.left)
        val right = computeValuable(node.right)
        when (val op = node.operator) {
            is Operator.Add -> {
                return if (left is Number && right is Number) {
                    left.toDouble() + right.toDouble()
                } else if (left is String && right is String) {
                    left + right
                } else throw RuntimeException("Binary operands $left or $right is not a number or string")
            }
            is Operator.Subtract -> {
                return if (left is Number && right is Number) {
                    left.toDouble() - right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.Multiply -> {
                return if (left is Number && right is Number) {
                    left.toDouble() * right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.Divide -> {
                return if (left is Number && right is Number) {
                    left.toDouble() / right.toDouble()
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.Exponentiate -> {
                return if (left is Number && right is Number) {
                    left.toDouble().pow(right.toDouble())
                } else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.IsEqual -> {
                return left == right
            }
            is Operator.Modulate -> {
                return if (left is Number && right is Number) {
                    left.toDouble().mod(right.toDouble())
                }else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.IsLessThan -> {
                return if (left is Comparable<*> && right is Comparable<*>) {
                    (left as Comparable<Any>).compareTo(right).sign == -1
                }else throw RuntimeException("Binary operands $left or $right is not a number")
            }
            is Operator.IsNotEqual -> {
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
        val func = functions[invoke.function.name] ?: throw RuntimeException("Function '${invoke.function.name}' is undefined")
        return func.invoke(this, args)
    }

    fun setVar(id: Token.Identifier, value: Any?){
        variables[id.name] = value
    }

    fun getVar(id: Token.Identifier): Any? {
        if (!variables.containsKey(id.name)) throw RuntimeException("#${id.line} -> Variable '${id.name}' is not defined'")
        val ret = variables[id.name]
        return ret
    }

    fun getVarOrNull(id: Token.Identifier): Any? {
        return variables[id.name]
    }
}

class GlobalExecutionScope(
    override val interpreter: Interpreter,
    initVariables: Map<String, Any?>
) : ExecutionScope() {
    override val variables: HashMap<String, Any?> = HashMap(initVariables)
    override val functions: HashMap<String, Function> = HashMap(FunctionRegistry.entries)
    override val global: GlobalExecutionScope = this
    override val debug: EnumSet<DebugFlag> get() = interpreter.debug
}

class LocalExecutionScope(
    private val parent: ExecutionScope,
): ExecutionScope() {
    override val variables: HashMap<String, Any?> = HashMap(parent.variables)

    /**
     * Functions are not changed within anything but the global scope
     * @see [ExecutionScope.functions]
     */
    override val functions: HashMap<String, Function> get() = parent.functions
    override val global: GlobalExecutionScope = parent.global
    override val debug = parent.debug
}