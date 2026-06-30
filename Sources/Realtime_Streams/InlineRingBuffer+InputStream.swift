
@_exported import Realtime
@_exported import Streams

extension InlineRingBuffer: InputStream {

    public borrowing func read(into mutableSpan: inout MutableSpan<Element>) throws(Never) -> Int {
        guard _fastPath(mutableSpan.isEmpty == false) else { return 0 }

        let readIndex = self.readIndex.load(ordering: .relaxed)
        let writeIndex = self.writeIndex.load(ordering: .acquiring)

        let readAvailable = Self.readAvailable(readIndex: readIndex, writeIndex: writeIndex)
        if readAvailable == 0 { return 0 }

        let mutableSpanCount = mutableSpan.count
        let readCount = min(mutableSpanCount, readAvailable)
        assert(0 < readCount)

        let nextReadIndex = Self.index(readIndex, advancedBy: readCount)

        self.storage.withUnsafePointer { unsafePointer in
            mutableSpan.withUnsafeMutableBufferPointer { unsafeMutableBufferPointer in
                guard let unsafeMutablePointer = unsafeMutableBufferPointer.baseAddress else {
                    fatalError("unexpectedly received nil buffer address.")
                }

                if nextReadIndex < readIndex {
                    let slice0Count = Self.storageCapacity - readIndex
                    unsafeMutablePointer.update(from: unsafePointer.advanced(by: readIndex), count: slice0Count)

                    let slice1Count = readCount - slice0Count
                    unsafeMutablePointer.advanced(by: slice0Count).update(from: unsafePointer, count: slice1Count)
                } else {
                    unsafeMutablePointer.update(from: unsafePointer.advanced(by: readIndex), count: readCount)
                }
            }
        }

        self.readIndex.store(nextReadIndex, ordering: .releasing)

        return readCount
    }
}
