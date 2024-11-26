package dev.hunter.nerve.core.components

object Nodes {
    /**
     * Denotes the initialization of a variable and its type
     */
    object VariableInitialization

    /**
     * Denotes the reassignment of a previously defined variable
     */
    object VariableReassignment

    /**
     * Denotes the deletion and freeing of the memory attributed to a variable,
     * rendering it undefined
     */
    object FreeVariable

    /**
     * Denotes the invocation of a defined function, which may return some value
     */
    object FunctionInvocation

    /**
     * Denotes the definition of a function with a name, return type,
     * typed parameters, and body.
     */
    object FunctionDefinition

    /**
     * Denotes the definition of a type with a name, properties, and functions
     */
    object TypeDefinition

    /**
     * Any expression that has two sides, with some operator in the middle
     */
    object BinaryExpression

    /**
     * Denotes the evaluation of a string template during runtime
     */
    object EvaluateTemplate

    /**
     * Denotes the tree structure of an if statement with its possible branches, elseif and else
     */
    object IfTree

    /**
     * Denotes the use of a for loop with a typed index variable and expression as bounds.
     */
    object ForLoop
}