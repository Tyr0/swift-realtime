
/// A `Sendable` reference box that shares a non-copyable value across tasks.
///
/// Wrapping a `~Copyable` value in a class lets several tasks capture the same
/// instance and borrow the value in place, without it being copied.
internal final class ValueContainer<Value>: Sendable where Value: ~Copyable & Sendable {

    // MARK: - Properties

    /// The value held by the container.
    let wrappedValue: Value

    // MARK: - Lifecycle Functions

    /// Creates a container that takes ownership of the given value.
    ///
    /// - Parameter wrappedValue: The value to store. It is consumed and held
    ///   for the lifetime of the container.
    init(_ wrappedValue: consuming Value) {
        self.wrappedValue = wrappedValue
    }

    // MARK: - Functions

    /// Borrows the wrapped value for the duration of a closure.
    ///
    /// - Parameter body: A closure that receives the wrapped value as a borrow.
    /// - Returns: The value returned by `body`.
    @inlinable
    func withValue<Error, Result>(_ body: (_ value: borrowing Value) throws(Error) -> Result) throws(Error) -> Result {
        try body(self.wrappedValue)
    }
}
