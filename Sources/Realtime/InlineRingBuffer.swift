
package import Synchronization

/// A fixed-capacity, lock-free FIFO queue for a single producer and a single
/// consumer (SPSC).
///
/// The buffer stores its elements inline — there is no heap allocation and no
/// reference counting — which makes it well suited to real-time and
/// latency-sensitive code. Its capacity is fixed at compile time through the
/// `storageCapacity` value generic parameter, and `Element` must be
/// `BitwiseCopyable` so values can be stored and retrieved without any lifetime
/// bookkeeping.
///
/// One slot is reserved to distinguish the full state from the empty state, so
/// a buffer with a `storageCapacity` of `N` holds at most `N - 1` elements. See
/// ``capacity``.
///
/// ## Concurrency
///
/// A single instance may be shared between one producer, which calls
/// ``enqueue(_:)``, and one consumer, which calls ``dequeue()``. Reads and
/// writes are coordinated internally with atomic indices, so no external
/// locking is required.
///
/// - Warning: This type supports exactly one producer and one consumer.
///   Calling ``enqueue(_:)`` from more than one thread concurrently, or
///   ``dequeue()`` from more than one thread concurrently, is a data race.
public struct InlineRingBuffer<let storageCapacity: Int, Element>: ~Copyable where Element: BitwiseCopyable {

    package typealias Index = Storage.Index

    package struct Storage: ~Copyable, Sendable {

        package typealias Elements = InlineArray<storageCapacity, Element>

        package typealias Index = Elements.Index

        // MARK: - Properties

        nonisolated(unsafe) private var elements: Elements

        // MARK: - Lifecycle Functions

        init(repeating repeatedElement: Element) {
            self.elements = Elements(repeating: repeatedElement)
        }

        deinit {
            // *DO NOT REMOVE*
            //
            // intentionally blank: this is a compile-time regression check to ensure this type remains
            // `~Copyable`.
            //
            // the mutate-through-borrow in `withUnsafePointer(to: self)` below is sound only because
            // `~Copyable` prevents `withUnsafePointer(to: self)` from substituting a temporary copy.
        }

        // MARK: - Accessor Functions

        @inlinable
        package borrowing func withUnsafePointer<Error, Result>(_ body: (UnsafePointer<Element>) throws(Error) -> Result) throws(Error) -> Result {
            return try Swift.withUnsafePointer(to: self) { unsafePointer throws(Error) -> Result in
                let unsafeRawPointer = UnsafeRawPointer(unsafePointer)
                return try body(unsafeRawPointer.assumingMemoryBound(to: Element.self))
            }
        }

        @inlinable
        package borrowing func withUnsafeMutablePointer<Error, Result>(_ body: (UnsafeMutablePointer<Element>) throws(Error) -> Result) throws(Error) -> Result {
            return try Swift.withUnsafePointer(to: self) { unsafePointer throws(Error) -> Result in
                let unsafeMutableRawPointer = UnsafeMutableRawPointer(mutating: unsafePointer)
                return try body(unsafeMutableRawPointer.assumingMemoryBound(to: Element.self))
            }
        }
    }

    // MARK: - Properties

    package static var capacity: Int {
        return Self.storageCapacity - 1
    }

    /// The actual number of elements that can be stored in this ring buffer.
    ///
    /// - Note: This is one less than the `storageCapacity` type parameter, because
    /// a single slot is reserved to tell the full and empty states apart.
    public var capacity: Int {
        return Self.capacity
    }

    /// The number of elements in the ring buffer available to dequeue.
    ///
    /// - Complexity: O(1).
    /// - Note: When read concurrently with ``enqueue(_:)`` or ``dequeue()``,
    ///   the result is a momentary snapshot that may be stale by the time it is
    ///   observed.
    public var count: Int {
        let readIndex = self.readIndex.load(ordering: .relaxed)
        let writeIndex = self.writeIndex.load(ordering: .relaxed)
        return Self.readAvailable(readIndex: readIndex, writeIndex: writeIndex)
    }

    /// A Boolean value indicating whether the ring buffer is empty.
    ///
    /// - Complexity: O(1).
    /// - Note: When read concurrently with ``enqueue(_:)`` or ``dequeue()``,
    ///   the result is a momentary snapshot.
    public var isEmpty: Bool {
        let readIndex = self.readIndex.load(ordering: .relaxed)
        let writeIndex = self.writeIndex.load(ordering: .relaxed)
        return Self.isEmpty(readIndex: readIndex, writeIndex: writeIndex)
    }

    package var storage: Storage

    package let readIndex: Atomic<Index>

    package let writeIndex: Atomic<Index>

    // MARK: - Lifecycle Functions

    private init(storage: consuming Storage) {
        precondition(1 < storageCapacity, "invalid storage capacity results in zero-sized buffer.")
        self.storage = storage
        self.readIndex = Atomic(0)
        self.writeIndex = Atomic(0)
    }

    /// Creates an empty buffer.
    @_disfavoredOverload
    public init() {
        let storage = withUnsafeTemporaryAllocation(of: Element.self, capacity: 1) { unsafeMutableBufferPointer in
            guard let unsafeMutablePointer = unsafeMutableBufferPointer.baseAddress else {
                fatalError("unexpectedly received nil buffer address.")
            }

            unsafeMutablePointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Element>.stride) { unsafeMutablePointerUInt8 in
                unsafeMutablePointerUInt8.initialize(repeating: .zero, count: MemoryLayout<Element>.stride)
            }

            return Storage(repeating: unsafeMutablePointer.pointee)
        }

        self.init(storage: storage)
    }

    // MARK: - Public Functions

    /// Adds an element to the end of the ring buffer.
    ///
    /// Call this method only from the producer.
    ///
    /// - Parameter newElement: The element to append to the ring buffer.
    /// - Returns: `true` if the element was stored, or `false` if the ring buffer
    ///   was full and the element was discarded.
    /// - Complexity: O(1).
    public borrowing func enqueue(_ newElement: Element) -> Bool {
        let readIndex = self.readIndex.load(ordering: .acquiring)
        let writeIndex = self.writeIndex.load(ordering: .relaxed)

        let nextWriteIndex = Self.index(after: writeIndex)
        if nextWriteIndex == readIndex {
            return false
        }

        self.storage.withUnsafeMutablePointer { unsafeMutablePointer in
            unsafeMutablePointer[writeIndex] = newElement
        }

        self.writeIndex.store(nextWriteIndex, ordering: .releasing)

        return true
    }

    /// Removes and returns the element at the front of the buffer.
    ///
    /// Call this method only from the consumer.
    ///
    /// - Returns: The oldest enqueued element, or `nil` if the buffer is empty.
    /// - Complexity: O(1).
    public borrowing func dequeue() -> Element? {
        let readIndex = self.readIndex.load(ordering: .relaxed)
        let writeIndex = self.writeIndex.load(ordering: .acquiring)

        if Self.isEmpty(readIndex: readIndex, writeIndex: writeIndex) {
            return nil
        }

        let nextReadIndex = Self.index(after: readIndex)

        defer {
            self.readIndex.store(nextReadIndex, ordering: .releasing)
        }

        return self.storage.withUnsafeMutablePointer { unsafeMutablePointer in
            return unsafeMutablePointer[readIndex]
        }
    }

    // MARK: - Package Static Functions

    private static func isEmpty(readIndex: Index, writeIndex: Index) -> Bool {
        return readIndex == writeIndex
    }

    package static func readAvailable(readIndex: Index, writeIndex: Index) -> Index.Stride {
        if readIndex <= writeIndex {
            return writeIndex - readIndex
        } else {
            return Self.storageCapacity + writeIndex - readIndex
        }
    }

    package static func writeAvailable(readIndex: Index, writeIndex: Index) -> Index.Stride {
        if readIndex <= writeIndex {
            return Self.storageCapacity + readIndex - writeIndex - 1
        } else {
            return readIndex - writeIndex - 1
        }
    }

    package static func index(after index: Index) -> Index {
        let nextIndex = index.advanced(by: 1)

        if _slowPath(nextIndex == Self.storageCapacity) {
            return 0
        } else {
            return nextIndex
        }
    }

    package static func index(_ index: Index, advancedBy distance: Index.Stride) -> Index {
        precondition(distance < Self.storageCapacity)

        let nextIndex = index.advanced(by: distance)

        if _slowPath(Self.storageCapacity <= nextIndex) {
            return nextIndex - Self.storageCapacity
        } else {
            return nextIndex
        }
    }
}

extension InlineRingBuffer where Element: AdditiveArithmetic {

    /// Creates an empty buffer.
    public init() {
        self.init(storage: Storage(repeating: .zero))
    }
}

extension InlineRingBuffer: Sendable where Element: Sendable {
    
}
