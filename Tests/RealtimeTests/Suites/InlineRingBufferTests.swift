
import Testing

@testable import Realtime
@testable import Realtime_Streams

@Suite
struct InlineRingBufferTests {

    private enum TestConfiguration {

        static let iterationCounts: Array<Int> = [
            1, 2, 4, 10,
        ]
    }

    // MARK: - Test Case Functions

    @Test
    func testInitialization() async throws {
        let ringBuffer = InlineRingBuffer<16, Int>()
        #expect(ringBuffer.capacity == 15)
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.isEmpty == true)
    }

    @Test(arguments: TestConfiguration.iterationCounts)
    func testEnqueueSingle_DequeueSingle(iterations: Int) async throws {
        let ringBuffer = InlineRingBuffer<16, Int>()
        #expect(ringBuffer.capacity == 15)
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.isEmpty == true)

        for _ in 0..<iterations {
            for i in 0..<ringBuffer.capacity {
                #expect(ringBuffer.enqueue(i) == true)
                #expect(ringBuffer.count == 1)
                #expect(ringBuffer.isEmpty == false)

                let existingValue = ringBuffer.dequeue()
                #expect(existingValue == i)
                #expect(ringBuffer.count == 0)
                #expect(ringBuffer.isEmpty == true)
            }
        }
    }

    @Test(arguments: TestConfiguration.iterationCounts)
    func testEnqueueToFull_DequeueToEmpty(iterations: Int) async throws {
        let ringBuffer = InlineRingBuffer<16, Int>()
        #expect(ringBuffer.capacity == 15)
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.isEmpty == true)

        for _ in 0..<iterations {
            for i in 0..<ringBuffer.capacity {
                #expect(ringBuffer.enqueue(i) == true)
                #expect(ringBuffer.count == i + 1)
                #expect(ringBuffer.isEmpty == false)
            }

            #expect(ringBuffer.enqueue(1337) == false)
            #expect(ringBuffer.count == ringBuffer.capacity)
            #expect(ringBuffer.isEmpty == false)

            for i in 0..<ringBuffer.capacity {
                let existingValue = ringBuffer.dequeue()
                #expect(existingValue == i)
            }

            let existingValue = ringBuffer.dequeue()
            #expect(existingValue == nil)
            #expect(ringBuffer.count == 0)
            #expect(ringBuffer.isEmpty == true)
        }
    }

    @Test
    func testConcurrentEnqueueDequeue() async throws {
        let total = 1_000_000

        let ringBuffer = InlineRingBuffer<1024, Int>()

        await performConcurrently(with: ringBuffer, producer: { ringBuffer in
            for i in 0..<total {
                var enqueued: Bool = false
                repeat {
                    enqueued = ringBuffer.enqueue(i)
                } while enqueued == false
            }
        }, consumer: { ringBuffer in
            for i in 0..<total {
                var existingValue: Int?
                repeat {
                    existingValue = ringBuffer.dequeue()
                } while existingValue == nil

                #expect(existingValue == i)
            }
        })
    }

    @Suite
    struct StreamsTests {

        @Test
        func testWriteThenReadRoundTrips() async throws {
            let ringBuffer = InlineRingBuffer<16, Int>()

            let source = Array<Int>(0..<10)
            let written = source.withUnsafeBufferPointer { pointer in
                ringBuffer.write(pointer.span)
            }
            #expect(written == 10)
            #expect(ringBuffer.count == 10)

            var destination = Array<Int>(repeating: -1, count: 10)
            let read = destination.withUnsafeMutableBufferPointer { pointer in
                var span = pointer.mutableSpan
                return ringBuffer.read(into: &span)
            }
            #expect(read == 10)
            #expect(destination == source)
            #expect(ringBuffer.isEmpty == true)
        }

        @Test
        func testWriteAndReadAcrossWraparound() async throws {
            let ringBuffer = InlineRingBuffer<16, Int>()

            // Push both indices to 10 so a bulk operation must split across the
            // end-of-storage boundary.
            for i in 0..<10 {
                #expect(ringBuffer.enqueue(i) == true)
                #expect(ringBuffer.dequeue() == i)
            }
            #expect(ringBuffer.isEmpty == true)

            let source = Array<Int>(100..<112)
            let written = source.withUnsafeBufferPointer { pointer in
                ringBuffer.write(pointer.span)
            }
            #expect(written == 12)
            #expect(ringBuffer.count == 12)

            var destination = Array<Int>(repeating: -1, count: 12)
            let read = destination.withUnsafeMutableBufferPointer { pointer in
                var span = pointer.mutableSpan
                return ringBuffer.read(into: &span)
            }
            #expect(read == 12)
            #expect(destination == source)
            #expect(ringBuffer.isEmpty == true)
        }

        @Test
        func testWriteIsPartialWhenBufferCannotFitEverything() async throws {
            let ringBuffer = InlineRingBuffer<16, Int>()

            let source = Array<Int>(0..<100)
            let written = source.withUnsafeBufferPointer { pointer in
                ringBuffer.write(pointer.span)
            }
            #expect(written == ringBuffer.capacity)
            #expect(ringBuffer.count == ringBuffer.capacity)

            let none = source.withUnsafeBufferPointer { pointer in
                ringBuffer.write(pointer.span)
            }
            #expect(none == 0)
        }

        @Test
        func testReadIsLimitedToAvailableElements() async throws {
            let ringBuffer = InlineRingBuffer<16, Int>()

            let source = Array<Int>(0..<3)
            _ = source.withUnsafeBufferPointer { pointer in
                ringBuffer.write(pointer.span)
            }

            var destination = Array<Int>(repeating: -1, count: 10)
            let read = destination.withUnsafeMutableBufferPointer { pointer in
                var span = pointer.mutableSpan
                return ringBuffer.read(into: &span)
            }
            #expect(read == 3)
            #expect(Array(destination[0..<3]) == source)
            #expect(destination[3] == -1)

            let empty = destination.withUnsafeMutableBufferPointer { pointer in
                var span = pointer.mutableSpan
                return ringBuffer.read(into: &span)
            }
            #expect(empty == 0)
        }
    }

    // MARK: - Test Support Functions

    private func performConcurrently<Value>(with value: consuming Value, producer: @escaping @Sendable (borrowing Value) -> Void, consumer: @escaping @Sendable (borrowing Value) -> Void) async where Value: ~Copyable & Sendable {
        let container = ValueContainer(value)

        await withTaskGroup { taskGroup in
            taskGroup.addTask(name: "Producer") {
                container.withValue { value in
                    producer(value)
                }
            }

            taskGroup.addTask(name: "Consumer") {
                container.withValue { value in
                    consumer(value)
                }
            }
        }
    }
}
