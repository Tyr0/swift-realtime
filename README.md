# swift-realtime

A collection of lock-free, allocation-free data structures for performance and
latency sensitive code such as audio, sensor, and networking pipelines.

![License](https://img.shields.io/badge/License-MIT-green.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20visionOS%20%7C%20watchOS-blue.svg)
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)

## Overview

`Realtime` provides value-type data structures built for the hot path:

- **Inline storage** — capacities are fixed at compile time with value generics,
  so elements live inline rather than in a separately allocated buffer.
- **Lock-free** — concurrent types coordinate with atomics rather than locks, so
  operations never block.
- **Non-copyable** — types are `~Copyable`, modeling exclusive ownership of their
  storage, and are `Sendable` when their `Element` is.

The types currently provided are listed below.

## Requirements

- Swift 6.2+
- iOS 26+ / macOS 26+ / tvOS 26+ / visionOS 26+ / watchOS 26+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Tyr0/swift-realtime.git", from: "1.0.0"),
]
```

Then add `Realtime` to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Realtime", package: "swift-realtime"),
    ],
),
```

## InlineRingBuffer

A fixed-capacity, lock-free single-producer / single-consumer (SPSC) ring buffer
with inline storage. `enqueue` from the back and `dequeue` from the front never
block or allocate.

One slot is reserved to distinguish the full state from the empty state, so a
buffer declared with a `storageCapacity` of `N` holds up to `N - 1` elements.

### Usage

Create a buffer with its capacity fixed at compile time, then `enqueue` from the
back and `dequeue` from the front:

```swift
import Realtime

let buffer = InlineRingBuffer<16, Int>()   // holds up to 15 elements
print(buffer.capacity)                     // 15

buffer.enqueue(1)                          // true
buffer.enqueue(2)                          // true

buffer.dequeue()                           // 1
buffer.dequeue()                           // 2
buffer.dequeue()                           // nil
```

`enqueue` returns `false` when the buffer is full rather than blocking or
growing, leaving the caller in control of back-pressure:

```swift
let buffer = InlineRingBuffer<4, Int>()    // holds up to 3 elements

while buffer.enqueue(next()) {
    // keep producing until the consumer drains a slot
}
```

A single instance may be shared between exactly **one** producer thread, which
calls `enqueue(_:)`, and **one** consumer thread, which calls `dequeue()`. The
atomic indices provide all the synchronization required — no external locking is
needed.

> [!WARNING]
> The buffer is *not* safe for multiple concurrent producers or multiple
> concurrent consumers. Calling `enqueue(_:)` from more than one thread, or
> `dequeue()` from more than one thread, is a data race.

### API

```swift
public struct InlineRingBuffer<let storageCapacity: Int, Element>: ~Copyable where Element: BitwiseCopyable {

    /// The maximum number of elements the buffer can hold (`storageCapacity - 1`).
    public var capacity: Int { get }

    /// The number of elements currently available to dequeue.
    public var count: Int { get }

    /// Whether the buffer currently holds no elements.
    public var isEmpty: Bool { get }

    /// Creates an empty buffer.
    public init()

    /// Adds an element to the back; returns `false` if the buffer is full.
    public borrowing func enqueue(_ newElement: Element) -> Bool

    /// Removes and returns the front element, or `nil` if the buffer is empty.
    public borrowing func dequeue() -> Element?
}
```

## License

Released under the MIT License. See [LICENSE.md](LICENSE.md).
