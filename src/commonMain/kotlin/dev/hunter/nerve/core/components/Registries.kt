package dev.hunter.nerve.core.components

import dev.hunter.nerve.core.ExecutionScope
import kotlin.reflect.KClass

abstract class Registry<T> {
    private val _entries = HashMap<String, T>()
    val entries get() = _entries.toMap() // creates new read only map
    fun register(t: T) {
        val d = disambiguate(t)
        val prev = _entries[d]
        if (prev != null ) allow(prev)
        _entries[d] = t
    }

    fun register(id: String, t: T) {
        val prev = _entries[id]
        if (prev != null ) allow(prev)
        _entries[id] = t
    }

    fun getFromId(id: String): T? = _entries[id]

    protected abstract fun allow(t: T): Nothing?
    protected abstract fun disambiguate(value: T): String
}

object FunctionRegistry: Registry<DelegateFunction>() {
    /**
     * Optional arguments are passed in as null.
     * [params] requires all possible expected parameters.
     *
     * If the passed in parameters ever exceeds the number of elements in the [params] array, the function call fails
     */
    fun register(name: String, params: Array<KClass<out Any>>, f: (ExecutionScope, List<Any?>) -> Any?) {
        val function = object: DelegateFunction(name, params) {
            override suspend fun handle(scope: ExecutionScope, args: List<Any?>): Any? = f(scope, args)
        }
        register(function)
    }

    init {
        register(StandardFunction.Print)
        register(StandardFunction.SystemNanoTime)
        register(StandardFunction.SystemCurrentMillis)
        register(StandardFunction.RunNerve)
    }

    override fun allow(t: DelegateFunction): Nothing? {
        return if (t is StandardFunction) throw IllegalArgumentException("Cannot overwrite a standard function")
        else null
    }

    override fun disambiguate(value: DelegateFunction): String = value.name
}