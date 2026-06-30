
@_exported import Realtime
@_exported import Streams

extension InlineRingBuffer: OutputStream {

    public borrowing func write(_ span: borrowing Span<Element>) throws(Never) -> Int {
        guard _fastPath(span.isEmpty == false) else { return 0 }

        let readIndex = self.readIndex.load(ordering: .acquiring)
        let writeIndex = self.writeIndex.load(ordering: .relaxed)

        let writeAvailable = Self.writeAvailable(readIndex: readIndex, writeIndex: writeIndex)
        if writeAvailable == 0 { return 0 }

        let spanCount = span.count
        let writeCount = min(spanCount, writeAvailable)
        assert(0 < writeCount)

        let nextWriteIndex = Self.index(writeIndex, advancedBy: writeCount)

        self.storage.withUnsafeMutablePointer { unsafeMutablePointer in
            span.withUnsafeBufferPointer { unsafeBufferPointer in
                guard let unsafePointer = unsafeBufferPointer.baseAddress else {
                    fatalError("unexpectedly received nil buffer address.")
                }

                if nextWriteIndex < writeIndex {
                    let slice0Count = Self.storageCapacity - writeIndex
                    unsafeMutablePointer.advanced(by: writeIndex).update(from: unsafePointer, count: slice0Count)

                    let slice1Count = writeCount - slice0Count
                    unsafeMutablePointer.update(from: unsafePointer.advanced(by: slice0Count), count: slice1Count)
                } else {
                    unsafeMutablePointer.advanced(by: writeIndex).update(from: unsafePointer, count: writeCount)
                }
            }
        }

        self.writeIndex.store(nextWriteIndex, ordering: .releasing)

        return writeCount
    }
}
