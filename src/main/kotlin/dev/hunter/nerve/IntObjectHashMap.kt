package dev.hunter.nerve

import java.util.*
import kotlin.math.max
import kotlin.math.min

/**
 * Hash map holding (key,value) associations of type <tt>(int-->Object)</tt>;
 * Automatically grows and shrinks as needed; Implemented using open addressing
 * with double hashing. First see the [package
 * summary](package-summary.html) and javadoc [tree view](package-tree.html) to get
 * the broad picture.
 *
 * This class has been adapted from the corresponding class in the COLT
 * library for scientific computing.
 *
 * @author wolfgang.hoschek@cern.ch
 * @version 1.0, 09/24/99
 * @see java.util.HashMap
 */
class IntObjectHashMap<T: Any> constructor(
    initialCapacity: Int = DEFAULT_CAPACITY, minLoadFactor: Double = DEFAULT_MIN_LOAD,
    maxLoadFactor: Double = DEFAULT_MAX_LOAD
) : AbstractCernMap(), Cloneable {

    constructor(
        initialCapacity: Int,
        map: Map<Int, T>
    ): this(initialCapacity) {
        for (i in 0..<map.size) {
            set(i, map[i])
        }
    }

    constructor(
        initialCapacity: Int,
        map: IntObjectHashMap<T>
    ): this(initialCapacity) {
        for (i in 0..<map.size()) {
            set(i, map[i])
        }
    }

    /**
     * The hash table keys.
     */
    private var table: IntArray = IntArray(0) // this will be changed, during setUp()

    /**
     * The hash table values.
     */
    private var _values: Array<Any?> = arrayOfNulls(0) // this will be changed, during setUp()

    val values get() = _values.filterNotNull()

    /**
     * The state of each hash table entry (FREE, FULL, REMOVED).
     */
    private var state: ByteArray = ByteArray(0) // this will be changed, during setUp()

    /**
     * The number of table entries in state==FREE.
     */
    private var freeEntries: Int = 0

    /**
     * Constructs an empty map with the specified initial capacity and the
     * specified minimum and maximum load factor.
     *
     * @param initialCapacity
     * the initial capacity.
     * @param minLoadFactor
     * the minimum load factor.
     * @param maxLoadFactor
     * the maximum load factor.
     * @throws IllegalArgumentException
     * if
     * <tt>initialCapacity < 0 || (minLoadFactor < 0.0 || minLoadFactor >= 1.0) || (maxLoadFactor <= 0.0 || maxLoadFactor >= 1.0) || (minLoadFactor >= maxLoadFactor)</tt>.
     */
    /**
     * Constructs an empty map with the specified initial capacity and default
     * load factors.
     *
     * @param initialCapacity
     * the initial capacity of the map.
     * @throws IllegalArgumentException
     * if the initial capacity is less than zero.
     */
    /**
     * Constructs an empty map with default capacity and default load factors.
     */
    init {
        setUp(initialCapacity, minLoadFactor, maxLoadFactor)
    }

    /**
     * Removes all (key,value) associations from the receiver. Implicitly calls
     * <tt>trimToSize()</tt>.
     */
    override fun clear() {
        Arrays.fill(state, FREE)
        Arrays.fill(_values, null)

        this.distinct = 0
        this.freeEntries = table.size // delta
        trimToSize()
    }

    /**
     * Returns a deep copy of the receiver.
     * @return a deep copy of the receiver.
     */
    public override fun clone(): Any {
        try {
            val copy = super.clone() as IntObjectHashMap<T>
            copy.table = copy.table.clone()
            copy._values = copy._values.clone()
            copy.state = copy.state.clone()
            return copy
        } catch (e: CloneNotSupportedException) {
            // won't happen
            throw e
        }
    }

    /**
     * Returns <tt>true</tt> if the receiver contains the specified key.
     * @return <tt>true</tt> if the receiver contains the specified key.
     */
    fun containsKey(key: Int): Boolean {
        return indexOfKey(key) >= 0
    }

    /**
     * Returns <tt>true</tt> if the receiver contains the specified value.
     * @return <tt>true</tt> if the receiver contains the specified value.
     */
    fun containsValue(value: T): Boolean {
        return indexOfValue(value) >= 0
    }

    /**
     * Ensures that the receiver can hold at least the specified number of
     * associations without needing to allocate new internal memory. If
     * necessary, allocates new internal memory and increases the capacity of
     * the receiver.
     *
     *
     * This method never need be called; it is for performance tuning only.
     * Calling this method before <tt>put()</tt>ing a large number of
     * associations boosts performance, because the receiver will grow only once
     * instead of potentially many times and hash collisions get less probable.
     *
     * @param minCapacity
     * the desired minimum capacity.
     */
    override fun ensureCapacity(minCapacity: Int) {
        if (table.size < minCapacity) {
            val newCapacity = nextPrime(minCapacity)
            rehash(newCapacity)
        }
    }

    /**
     * Returns the value associated with the specified key. It is often a good
     * idea to first check with [.containsKey] whether the given key
     * has a value associated or not, i.e. whether there exists an association
     * for the given key or not.
     *
     * @param key
     * the key to be searched for.
     * @return the value associated with the specified key; <tt>null</tt> if
     * no such key is present.
     */
    operator fun get(key: Int): T? {
        val i = indexOfKey(key)
        if (i < 0) return null // not contained
        return _values[i] as T?
    }

    /**
     * @param key
     * the key to be added to the receiver.
     * @return the index where the key would need to be inserted, if it is not
     * already contained. Returns -index-1 if the key is already
     * contained at slot index. Therefore, if the returned index < 0,
     * then it is already contained at slot -index-1. If the returned
     * index >= 0, then it is NOT already contained and should be
     * inserted at slot index.
     */
    private fun indexOfInsertion(key: Int): Int {
        val tab = table
        val stat = state
        val length = tab.size

        val hash = key and 0x7FFFFFFF
        var i = hash % length
        // double hashing, see http://www.eece.unm.edu/faculty/heileman/hash/node4.html
        var decrement = hash % (length - 2)
        // int decrement = (hash / length) % length;
        if (decrement == 0) decrement = 1

        // stop if we find a removed or free slot, or if we find the key itself
        // do NOT skip over removed slots (yes, open addressing is like that...)
        while (stat[i] == FULL && tab[i] != key) {
            i -= decrement
            // hashCollisions++;
            if (i < 0) i += length
        }

        if (stat[i] == REMOVED) {
            // stop if we find a free slot, or if we find the key itself.
            // do skip over removed slots (yes, open addressing is like that...)
            // assertion: there is at least one FREE slot.
            val j = i
            while (stat[i] != FREE && (stat[i] == REMOVED || tab[i] != key)) {
                i -= decrement
                // hashCollisions++;
                if (i < 0) i += length
            }
            if (stat[i] == FREE) i = j
        }

        if (stat[i] == FULL) {
            // key already contained at slot i.
            // return a negative number identifying the slot.
            return -i - 1
        }
        // not already contained, should be inserted at slot i.
        // return a number >= 0 identifying the slot.
        return i
    }

    /**
     * @param key
     * the key to be searched in the receiver.
     * @return the index where the key is contained in the receiver, returns -1
     * if the key was not found.
     */
    private fun indexOfKey(key: Int): Int {
        val tab = table
        val stat = state
        val length = tab.size

        val hash = key and 0x7FFFFFFF
        var i = hash % length
        // double hashing, see http://www.eece.unm.edu/faculty/heileman/hash/node4.html
        var decrement = hash % (length - 2)
        // int decrement = (hash / length) % length;
        if (decrement == 0) decrement = 1

        // stop if we find a free slot, or if we find the key itself.
        // do skip over removed slots (yes, open addressing is like that...)
        while (stat[i] != FREE && (stat[i] == REMOVED || tab[i] != key)) {
            i -= decrement
            // hashCollisions++;
            if (i < 0) i += length
        }

        if (stat[i] == FREE) return -1 // not found

        return i // found, return index where key is contained
    }

    /**
     * @param value
     * the value to be searched in the receiver.
     * @return the index where the value is contained in the receiver, returns
     * -1 if the value was not found.
     */
    protected fun indexOfValue(value: T): Int {
        val `val` = _values
        val stat = state

        var i = stat.size
        while (--i >= 0) {
            if (stat[i] == FULL && `val`[i] === value) return i
        }

        return -1 // not found
    }

    /**
     * Returns the first key the given value is associated with. It is often a
     * good idea to first check with [.containsValue] whether
     * there exists an association from a key to this value.
     *
     * @param value the value to search for.
     * @return the first key for which holds <tt>get(key) == value</tt>;
     * returns <tt>Integer.MIN_VALUE</tt> if no such key exists.
     */
    fun keyOf(value: T): Int {
        // returns the first key found; there may be more matching keys,
        // however.
        val i = indexOfValue(value)
        if (i < 0) return Int.MIN_VALUE
        return table[i]
    }

    /**
     * Fills all keys contained in the receiver into the specified list. Fills
     * the list, starting at index 0. After this call returns the specified list
     * has a new size that equals <tt>this.size()</tt>.
     *
     *
     * This method can be used to iterate over the keys of the receiver.
     *
     * @param list
     * the list to be filled
     */
    fun keys(list: IntArray): Int {
        val tab = table
        val stat = state

        if (list.size < distinct) return -1

        var j = 0
        var i = tab.size
        while (i-- > 0) {
            if (stat[i] == FULL) list[j++] = tab[i]
        }
        return distinct
    }

    /**
     * Associates the given key with the given value. Replaces any old
     * <tt>(key,someOtherValue)</tt> association, if existing.
     *
     * @param key
     * the key the value shall be associated with.
     * @param value
     * the value to be associated.
     * @return <tt>true</tt> if the receiver did not already contain such a
     * key; <tt>false</tt> if the receiver did already contain such a
     * key - the new value has now replaced the formerly associated
     * value.
     */
    operator fun set(key: Int, value: T?): Boolean {
        var i = indexOfInsertion(key)
        if (i < 0) { // already contained
            i = -i - 1
            _values[i] = value
            return false
        }

        if (this.distinct > this.highWaterMark) {
            val newCapacity = chooseGrowCapacity(
                this.distinct + 1,
                this.minLoadFactor, this.maxLoadFactor
            )
            rehash(newCapacity)
            return set(key, value)
        }

        table[i] = key
        _values[i] = value
        if (state[i] == FREE) freeEntries--
        state[i] = FULL
        distinct++

        if (this.freeEntries < 1) { // delta
            val newCapacity = chooseGrowCapacity(
                this.distinct + 1,
                this.minLoadFactor, this.maxLoadFactor
            )
            rehash(newCapacity)
        }

        return true
    }

    /**
     * Rehashes the contents of the receiver into a new table with a smaller or
     * larger capacity. This method is called automatically when the number of
     * keys in the receiver exceeds the high water mark or falls below the low
     * water mark.
     */
    protected fun rehash(newCapacity: Int) {
        val oldCapacity = table.size

        // if (oldCapacity == newCapacity) return;
        val oldTable = table
        val oldValues = _values
        val oldState = state

        val newTable = IntArray(newCapacity)
        val newValues = arrayOfNulls<Any>(newCapacity)
        val newState = ByteArray(newCapacity)

        this.lowWaterMark = chooseLowWaterMark(newCapacity, this.minLoadFactor)
        this.highWaterMark = chooseHighWaterMark(
            newCapacity,
            this.maxLoadFactor
        )

        this.table = newTable
        this._values = newValues
        this.state = newState
        this.freeEntries = newCapacity - this.distinct // delta

        var i = oldCapacity
        while (i-- > 0) {
            if (oldState[i] == FULL) {
                val element = oldTable[i]
                val index = indexOfInsertion(element)
                newTable[index] = element
                newValues[index] = oldValues[i]
                newState[index] = FULL
            }
        }
    }

    /**
     * Removes the given key with its associated element from the receiver, if
     * present.
     *
     * @param key
     * the key to be removed from the receiver.
     * @return <tt>true</tt> if the receiver contained the specified key,
     * <tt>false</tt> otherwise.
     */
    fun removeKey(key: Int): Boolean {
        val i = indexOfKey(key)
        if (i < 0) return false // key not contained


        state[i] = REMOVED
        _values[i] = null // delta
        distinct--

        if (this.distinct < this.lowWaterMark) {
            val newCapacity = chooseShrinkCapacity(
                this.distinct,
                this.minLoadFactor, this.maxLoadFactor
            )
            rehash(newCapacity)
        }

        return true
    }

    /**
     * Initializes the receiver.
     *
     * @param initialCapacity
     * the initial capacity of the receiver.
     * @param minLoadFactor
     * the minLoadFactor of the receiver.
     * @param maxLoadFactor
     * the maxLoadFactor of the receiver.
     * @throws IllegalArgumentException
     * if
     * <tt>initialCapacity < 0 || (minLoadFactor < 0.0 || minLoadFactor >= 1.0) || (maxLoadFactor <= 0.0 || maxLoadFactor >= 1.0) || (minLoadFactor >= maxLoadFactor)</tt>.
     */
    override fun setUp(
        initialCapacity: Int, minLoadFactor: Double,
        maxLoadFactor: Double
    ) {
        var capacity = initialCapacity
        super.setUp(capacity, minLoadFactor, maxLoadFactor)
        capacity = nextPrime(capacity)
        if (capacity == 0) capacity = 1 // open addressing needs at least one FREE slot at any time.


        this.table = IntArray(capacity)
        this._values = arrayOfNulls(capacity)
        this.state = ByteArray(capacity)

        // memory will be exhausted long before this pathological case happens, anyway.
        this.minLoadFactor = minLoadFactor
        if (capacity == PrimeFinder.LARGEST_PRIME) this.maxLoadFactor = 1.0
        else this.maxLoadFactor = maxLoadFactor

        this.distinct = 0
        this.freeEntries = capacity // delta

        // lowWaterMark will be established upon first expansion.
        // establishing it now (upon instance construction) would immediately make the table shrink upon first put(...).
        // After all the idea of an "initialCapacity" implies violating lowWaterMarks when an object is young.
        // See ensureCapacity(...)
        this.lowWaterMark = 0
        this.highWaterMark = chooseHighWaterMark(capacity, this.maxLoadFactor)
    }

    /**
     * Trims the capacity of the receiver to be the receiver's current
     * size. Releases any superfluous internal memory. An application can use this operation to minimize the
     * storage of the receiver.
     */
    override fun trimToSize() {
        // * 1.2 because open addressing's performance exponentially degrades beyond that point
        // so that even rehashing the table can take very long
        val newCapacity = nextPrime((1 + 1.2 * size()).toInt())
        if (table.size > newCapacity) {
            rehash(newCapacity)
        }
    }

    companion object {
        protected const val FREE: Byte = 0
        protected const val FULL: Byte = 1
        protected const val REMOVED: Byte = 2
    }
} // end of class IntObjectHashMap


/*
Copyright  1999 CERN - European Organization for Nuclear Research.
Permission to use, copy, modify, distribute and sell this software and its documentation for any purpose
is hereby granted without fee, provided that the above copyright notice appear in all copies and
that both that copyright notice and this permission notice appear in supporting documentation.
CERN makes no representations about the suitability of this software for any purpose.
It is provided "as is" without expressed or implied warranty.
*/
/**
 * Abstract base class for hash maps holding objects or primitive data types
 * such as `int`, `float`, etc. as keys and/or
 * values. First see the [package summary](package-summary.html) and
 * javadoc [tree view](package-tree.html) to get the broad picture.
 *
 *
 * Note that implementations are not synchronized.
 *
 * @author wolfgang.hoschek@cern.ch
 * @version 1.0, 09/24/99
 * @see java.util.HashMap
 */
abstract class AbstractCernMap
/**
 * Makes this class non instantiable, but still let's others inherit from
 * it.
 */
protected constructor() {
    /**
     * The number of distinct associations in the map; its "size()".
     */
    protected var distinct: Int = 0

    /**
     * The table capacity c=table.length always satisfies the invariant
     * <tt>c * minLoadFactor <= s <= c * maxLoadFactor</tt>, where s=size()
     * is the number of associations currently contained. The term "c *
     * minLoadFactor" is called the "lowWaterMark", "c * maxLoadFactor" is
     * called the "highWaterMark". In other words, the table capacity (and
     * proportionally the memory used by this class) oscillates within these
     * constraints. The terms are precomputed and cached to avoid recalculating
     * them each time put(..) or removeKey(...) is called.
     */
    protected var lowWaterMark: Int = 0

    protected var highWaterMark: Int = 0

    /**
     * The minimum load factor for the hashtable.
     */
    protected var minLoadFactor: Double = 0.0

    /**
     * The maximum load factor for the hashtable.
     */
    protected var maxLoadFactor: Double = 0.0

    /**
     * Chooses a new prime table capacity optimized for growing that
     * (approximately) satisfies the invariant
     * <tt>c * minLoadFactor <= size <= c * maxLoadFactor</tt> and has at
     * least one FREE slot for the given size.
     */
    protected fun chooseGrowCapacity(size: Int, minLoad: Double, maxLoad: Double): Int {
        return nextPrime(
            max(
                (size + 1).toDouble(),
                (4 * size / (3 * minLoad + maxLoad)).toInt().toDouble()
            ).toInt()
        )
    }

    /**
     * Returns new high water mark threshold based on current capacity and
     * maxLoadFactor.
     *
     * @return int the new threshold.
     */
    protected fun chooseHighWaterMark(capacity: Int, maxLoad: Double): Int {
        return min((capacity - 2).toDouble(), (capacity * maxLoad).toInt().toDouble()).toInt() // makes
        // sure
        // there is
        // always at
        // least one
        // FREE slot
    }

    /**
     * Returns new low water mark threshold based on current capacity and
     * minLoadFactor.
     *
     * @return int the new threshold.
     */
    protected fun chooseLowWaterMark(capacity: Int, minLoad: Double): Int {
        return (capacity * minLoad).toInt()
    }

    /**
     * Chooses a new prime table capacity neither favoring shrinking nor
     * growing, that (approximately) satisfies the invariant
     * <tt>c * minLoadFactor <= size <= c * maxLoadFactor</tt> and has at
     * least one FREE slot for the given size.
     */
    protected fun chooseMeanCapacity(size: Int, minLoad: Double, maxLoad: Double): Int {
        return nextPrime(
            max(
                (size + 1).toDouble(),
                (2 * size / (minLoad + maxLoad)).toInt().toDouble()
            ).toInt()
        )
    }

    /**
     * Chooses a new prime table capacity optimized for shrinking that
     * (approximately) satisfies the invariant
     * <tt>c * minLoadFactor <= size <= c * maxLoadFactor</tt> and has at
     * least one FREE slot for the given size.
     */
    protected fun chooseShrinkCapacity(size: Int, minLoad: Double, maxLoad: Double): Int {
        return nextPrime(
            max(
                (size + 1).toDouble(),
                (4 * size / (minLoad + 3 * maxLoad)).toInt().toDouble()
            ).toInt()
        )
    }

    /**
     * Removes all (key,value) associations from the receiver.
     */
    abstract fun clear()

    /**
     * Ensures that the receiver can hold at least the specified number of
     * elements without needing to allocate new internal memory. If necessary,
     * allocates new internal memory and increases the capacity of the receiver.
     *
     *
     * This method never need be called; it is for performance tuning only.
     * Calling this method before <tt>put()</tt>ing a large number of
     * associations boosts performance, because the receiver will grow only once
     * instead of potentially many times.
     *
     *
     * **This default implementation does nothing.** Override this method if
     * necessary.
     *
     * @param minCapacity
     * the desired minimum capacity.
     */
    open fun ensureCapacity(minCapacity: Int) {
    }

    val isEmpty: Boolean
        /**
         * Returns <tt>true</tt> if the receiver contains no (key,value)
         * associations.
         *
         * @return <tt>true</tt> if the receiver contains no (key,value)
         * associations.
         */
        get() = distinct == 0

    /**
     * Returns a prime number which is `>= desiredCapacity` and
     * very close to `desiredCapacity` (within 11% if
     * `desiredCapacity >= 1000`).
     *
     * @param desiredCapacity
     * the capacity desired by the user.
     * @return the capacity which should be used for a hashtable.
     */
    protected fun nextPrime(desiredCapacity: Int): Int {
        return PrimeFinder.nextPrime(desiredCapacity)
    }

    /**
     * Initializes the receiver. You will almost certainly need to override this
     * method in subclasses to initialize the hash table.
     *
     * @param initialCapacity
     * the initial capacity of the receiver.
     * @param minLoadFactor
     * the minLoadFactor of the receiver.
     * @param maxLoadFactor
     * the maxLoadFactor of the receiver.
     * @throws IllegalArgumentException
     * if
     * <tt>initialCapacity < 0 || (minLoadFactor < 0.0 || minLoadFactor >= 1.0) || (maxLoadFactor <= 0.0 || maxLoadFactor >= 1.0) || (minLoadFactor >= maxLoadFactor)</tt>.
     */
    protected open fun setUp(
        initialCapacity: Int, minLoadFactor: Double,
        maxLoadFactor: Double
    ) {
        if (initialCapacity < 0) throw IllegalArgumentException(
            "Initial Capacity must not be less than zero: "
                    + initialCapacity
        )
        if (minLoadFactor < 0.0 || minLoadFactor >= 1.0) throw IllegalArgumentException(
            ("Illegal minLoadFactor: "
                    + minLoadFactor)
        )
        if (maxLoadFactor <= 0.0 || maxLoadFactor >= 1.0) throw IllegalArgumentException(
            ("Illegal maxLoadFactor: "
                    + maxLoadFactor)
        )
        if (minLoadFactor >= maxLoadFactor) throw IllegalArgumentException(
            (("Illegal minLoadFactor: "
                    + minLoadFactor + " and maxLoadFactor: " + maxLoadFactor))
        )
    }

    /**
     * Returns the number of (key,value) associations currently contained.
     *
     * @return the number of (key,value) associations currently contained.
     */
    fun size(): Int = distinct

    /**
     * Trims the capacity of the receiver to be the receiver's current
     * size. Releases any superfluous internal memory. An application can use this operation to minimize the
     * storage of the receiver.
     *
     *
     * This default implementation does nothing. Override this method if necessary.
     */
    open fun trimToSize() {}

    companion object {
        const val DEFAULT_CAPACITY: Int = 277

        const val DEFAULT_MIN_LOAD: Double = 0.2

        const val DEFAULT_MAX_LOAD: Double = 0.5
    }
} // end of class AbstractHashMap


/**
 * Not of interest for users; only for implementors of hashtables. Used to keep
 * hash table capacities prime numbers.
 *
 *
 *
 * Choosing prime numbers as hash table capacities is a good idea to keep them
 * working fast, particularly under hash table expansions.
 *
 *
 *
 *
 * However, JDK 1.2, JGL 3.1 and many other toolkits do nothing to keep
 * capacities prime. This class provides efficient means to choose prime
 * capacities.
 *
 *
 *
 *
 * Choosing a prime is <tt>O(log 300)</tt> (binary search in a list of 300
 * int's). Memory requirements: 1 KB static memory.
 *
 *
 * This class has been adapted from the corresponding class in the COLT
 * library for scientfic computing.
 *
 * @author wolfgang.hoschek@cern.ch
 * @version 1.0, 09/24/99
 */
internal object PrimeFinder {
    /**
     * The largest prime this class can generate; currently equal to
     * <tt>Integer.MAX_VALUE</tt>.
     */
    const val LARGEST_PRIME: Int = Int.MAX_VALUE // yes, it is

    // prime.
    /**
     * The prime number list consists of 11 chunks. Each chunk contains prime
     * numbers. A chunk starts with a prime P1. The next element is a prime P2.
     * P2 is the smallest prime for which holds: P2 >= 2*P1. The next element is
     * P3, for which the same holds with respect to P2, and so on.
     *
     * Chunks are chosen such that for any desired capacity >= 1000 the list
     * includes a prime number <= desired capacity * 1.11 (11%). For any desired
     * capacity >= 200 the list includes a prime number <= desired capacity *
     * 1.16 (16%). For any desired capacity >= 16 the list includes a prime
     * number <= desired capacity * 1.21 (21%).
     *
     * Therefore, primes can be retrieved which are quite close to any desired
     * capacity, which in turn avoids wasting memory. For example, the list
     * includes 1039,1117,1201,1277,1361,1439,1523,1597,1759,1907,2081. So if
     * you need a prime >= 1040, you will find a prime <= 1040*1.11=1154.
     *
     * Chunks are chosen such that they are optimized for a hashtable
     * growthfactor of 2.0; If your hashtable has such a growthfactor then,
     * after initially "rounding to a prime" upon hashtable construction, it
     * will later expand to prime capacities such that there exist no better
     * primes.
     *
     * In total these are about 32*10=320 numbers -> 1 KB of static memory
     * needed. If you are stingy, then delete every second or fourth chunk.
     */
    private val primeCapacities = intArrayOf( // chunk #0
        LARGEST_PRIME,  // chunk #1

        5, 11, 23, 47, 97, 197, 397, 797, 1597, 3203, 6421, 12853, 25717,
        51437, 102877, 205759, 411527, 823117, 1646237, 3292489, 6584983,
        13169977, 26339969, 52679969, 105359939, 210719881, 421439783,
        842879579, 1685759167,  // chunk #2

        433, 877, 1759, 3527, 7057, 14143, 28289, 56591, 113189, 226379,
        452759, 905551, 1811107, 3622219, 7244441, 14488931, 28977863,
        57955739, 115911563, 231823147, 463646329, 927292699, 1854585413,  // chunk #3

        953, 1907, 3821, 7643, 15287, 30577, 61169, 122347, 244703, 489407,
        978821, 1957651, 3915341, 7830701, 15661423, 31322867, 62645741,
        125291483, 250582987, 501165979, 1002331963, 2004663929,  // chunk #4

        1039, 2081, 4177, 8363, 16729, 33461, 66923, 133853, 267713,
        535481, 1070981, 2141977, 4283963, 8567929, 17135863, 34271747,
        68543509, 137087021, 274174111, 548348231, 1096696463,  // chunk #5

        31, 67, 137, 277, 557, 1117, 2237, 4481, 8963, 17929, 35863, 71741,
        143483, 286973, 573953, 1147921, 2295859, 4591721, 9183457,
        18366923, 36733847, 73467739, 146935499, 293871013, 587742049,
        1175484103,  // chunk #6

        599, 1201, 2411, 4831, 9677, 19373, 38747, 77509, 155027, 310081,
        620171, 1240361, 2480729, 4961459, 9922933, 19845871, 39691759,
        79383533, 158767069, 317534141, 635068283, 1270136683,  // chunk #7

        311, 631, 1277, 2557, 5119, 10243, 20507, 41017, 82037, 164089,
        328213, 656429, 1312867, 2625761, 5251529, 10503061, 21006137,
        42012281, 84024581, 168049163, 336098327, 672196673, 1344393353,  // chunk #8

        3, 7, 17, 37, 79, 163, 331, 673, 1361, 2729, 5471, 10949, 21911,
        43853, 87719, 175447, 350899, 701819, 1403641, 2807303, 5614657,
        11229331, 22458671, 44917381, 89834777, 179669557, 359339171,
        718678369, 1437356741,  // chunk #9

        43, 89, 179, 359, 719, 1439, 2879, 5779, 11579, 23159, 46327,
        92657, 185323, 370661, 741337, 1482707, 2965421, 5930887, 11861791,
        23723597, 47447201, 94894427, 189788857, 379577741, 759155483,
        1518310967,  // chunk #10

        379, 761, 1523, 3049, 6101, 12203, 24407, 48817, 97649, 195311,
        390647, 781301, 1562611, 3125257, 6250537, 12501169, 25002389,
        50004791, 100009607, 200019221, 400038451, 800076929, 1600153859 /*
         * // some more chunks for the low range [3..1000] //chunk #11
         * 13,29,59,127,257,521,1049,2099,4201,8419,16843,33703,67409,134837,269683,
         * 539389,1078787,2157587,4315183,8630387,17260781,34521589,69043189,138086407,
         * 276172823,552345671,1104691373,
         *
         * //chunk #12 19,41,83,167,337,677,
         * //1361,2729,5471,10949,21911,43853,87719,175447,350899,
         * //701819,1403641,2807303,5614657,11229331,22458671,44917381,89834777,179669557,
         * //359339171,718678369,1437356741,
         *
         * //chunk #13 53,107,223,449,907,1823,3659,7321,14653,29311,58631,117269,
         * 234539,469099,938207,1876417,3752839,7505681,15011389,30022781,
         * 60045577,120091177,240182359,480364727,960729461,1921458943
         */

    )

    init { // initializer
        // The above prime numbers are formatted for human readability.
        // To find numbers fast, we sort them once and for all.
        Arrays.sort(primeCapacities)
    }

    /**
     * Returns a prime number which is `>= desiredCapacity` and
     * very close to `desiredCapacity` (within 11% if
     * `desiredCapacity >= 1000`).
     *
     * @param desiredCapacity
     * the capacity desired by the user.
     * @return the capacity which should be used for a hashtable.
     */
    fun nextPrime(desiredCapacity: Int): Int {
        var i = Arrays.binarySearch(primeCapacities, desiredCapacity)
        if (i < 0) {
            // desired capacity not found, choose next prime greater than
            // desired capacity
            i = -i - 1 // remember the semantics of binarySearch...
        }
        return primeCapacities[i]
    }
} // end of class PrimeFinder