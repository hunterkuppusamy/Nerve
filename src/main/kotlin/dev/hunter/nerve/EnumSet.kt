package dev.hunter.nerve

import kotlin.reflect.KClass

inline fun <reified T: Enum<T>> EnumSet(vararg es: T): EnumSet<T> = EnumSet(T::class, es.asList())
inline fun <reified T: Enum<T>> EnumSet(): EnumSet<T> = EnumSet(T::class, emptyList())
/**
 * Cannot be iterated (We can't know which ordinal corresponds to an enum value without reflection)
 *
 * @throws UnsupportedOperationException when invoking [iterator]
 */
class EnumSet<T: Enum<T>>(clas: KClass<T>, elements: Collection<T>): AbstractMutableSet<T>() {
    companion object{
        inline fun <reified T: Enum<T>> all(): EnumSet<T> = EnumSet(T::class, T::class.java.enumConstants.asList())
        inline fun <reified T: Enum<T>> none(): EnumSet<T> = EnumSet(T::class, emptyList())
        inline fun <reified T: Enum<T>> of(vararg elements: T): EnumSet<T> = EnumSet(T::class, elements.asList())
    }

    internal val type = clas
    private var flags: Long = 0

    init {
        for (e in elements) {
            add(e)
        }
    }

    override val size: Int get() {
        var i = flags
        // HD, Figure 5-2
        // copied from java.lang.Long
        i -= ((i ushr 1) and 0x5555555555555555L)
        i = (i and 0x3333333333333333L) + ((i ushr 2) and 0x3333333333333333L)
        i = (i + (i ushr 4)) and 0x0f0f0f0f0f0f0f0fL
        i += (i ushr 8)
        i += (i ushr 16)
        i += (i ushr 32)
        return i.toInt() and 0x7f
    }

    /**
     * Returns `true` if this set contains no elements.
     *
     * @return `true` if this set contains no elements
     */
    override fun isEmpty(): Boolean {
        return flags == 0L
    }

    /**
     * Cannot invoke, as an iterator would require knowledge of which ordinal belongs to which element
     *
     * Such knowledge is not available without reflection
     * @throws UnsupportedOperationException
     */
    override fun iterator(): MutableIterator<T> {
        throw UnsupportedOperationException("Cannot iterate an EnumSet without reflection")
    }

    /**
     * Returns `true` if this set contains the specified element.
     *
     * @param element element to be checked for containment in this collection
     * @return `true` if this set contains the specified element
     */
    override fun contains(element: T): Boolean {
        return (flags and (1L shl (element as Enum<*>).ordinal)) != 0L
    }


    // Modification Operations
    /**
     * Adds the specified element to this set if it is not already present.
     *
     * @param element element to be added to this set
     * @return `true` if the set changed as a result of the call
     *
     * @throws NullPointerException if `e` is null
     */
    override fun add(element: T): Boolean {
        val oldElements: Long = flags
        flags = flags or (1L shl (element as Enum<*>).ordinal)
        return flags != oldElements
    }

    /**
     * Removes the specified element from this set if it is present.
     *
     * @param element element to be removed from this set, if present
     * @return `true` if the set contained the specified element
     */
    override fun remove(element: T): Boolean {
        val oldElements: Long = flags
        flags = flags and (1L shl (element as Enum<*>).ordinal).inv()
        return flags != oldElements
    }


    // Bulk Operations
    /**
     * Returns `true` if this set contains all of the elements
     * in the specified collection.
     *
     * @param elements collection to be checked for containment in this set
     * @return `true` if this set contains all of the elements
     * in the specified collection
     * @throws NullPointerException if the specified collection is null
     */
    // Bulk Operations
    override fun containsAll(elements: Collection<T>): Boolean {
        if (elements !is EnumSet) return super.containsAll(elements)

        if (elements.type != type) return elements.isEmpty()

        return (elements.flags and elements.flags.inv()) == 0L
    }

    /**
     * Adds all of the elements in the specified collection to this set.
     *
     * @param elements collection whose elements are to be added to this set
     * @return `true` if this set changed as a result of the call
     * @throws NullPointerException if the specified collection or any
     * of its elements are null
     */
    override fun addAll(elements: Collection<T>): Boolean {
        if (elements !is EnumSet) return super.addAll(elements)

        if (elements.type != type) {
            if (elements.isEmpty()) return false
            else throw ClassCastException(
                elements.type.toString() + " != " + type
            )
        }

        val oldElements: Long = this.flags
        this.flags = this.flags or elements.flags
        return this.flags != oldElements
    }

    /**
     * Retains only the elements in this set that are contained in the
     * specified collection.
     *
     * @param elements elements to be retained in this set
     * @return `true` if this set changed as a result of the call
     * @throws NullPointerException if the specified collection is null
     */
    override fun retainAll(elements: Collection<T>): Boolean {
        if (elements !is EnumSet) return super.retainAll(elements.toSet())

        if (elements.type != type) {
            val changed = (flags != 0L)
            flags = 0
            return changed
        }

        val oldElements: Long = flags
        flags = flags and elements.flags
        return flags != oldElements
    }

    /**
     * Removes all of the elements from this set.
     */
    override fun clear() {
        flags = 0
    }
}