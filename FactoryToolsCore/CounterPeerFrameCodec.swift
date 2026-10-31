import Foundation

/// Length-prefixes peer messages so TCP fragmentation and coalescing do not affect decoding.
public enum CounterPeerFrameCodec {
    public static let maximumFrameLength = 1_048_576

    public static func encode(_ message: CounterPeerMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard !payload.isEmpty, payload.count <= maximumFrameLength else {
            throw CounterPeerFrameError.frameTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }
}

public struct CounterPeerFrameDecoder {
    private var bufferedData = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [CounterPeerMessage] {
        var messages: [CounterPeerMessage] = []
        var offset = 0
        let maximumBufferedByteCount = CounterPeerFrameCodec.maximumFrameLength + 4
        while offset < data.count {
            let remainingCapacity = maximumBufferedByteCount - bufferedData.count
            guard remainingCapacity > 0 else { throw CounterPeerFrameError.frameTooLarge }
            let chunkLength = min(remainingCapacity, data.count - offset)
            let chunkEnd = offset + chunkLength
            bufferedData.append(data.subdata(in: offset..<chunkEnd))
            offset = chunkEnd
            messages.append(contentsOf: try drainCompleteMessages())
        }
        return messages
    }

    private mutating func drainCompleteMessages() throws -> [CounterPeerMessage] {
        var messages: [CounterPeerMessage] = []
        var consumedByteCount = 0
        while bufferedData.count - consumedByteCount >= 4 {
            let headerEnd = consumedByteCount + 4
            let length = bufferedData[consumedByteCount..<headerEnd]
                .reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0 else {
                discardBufferedPrefix(consumedByteCount)
                throw CounterPeerFrameError.invalidLength
            }
            guard Int(length) <= CounterPeerFrameCodec.maximumFrameLength else {
                discardBufferedPrefix(consumedByteCount)
                throw CounterPeerFrameError.frameTooLarge
            }
            let frameEnd = headerEnd + Int(length)
            guard bufferedData.count >= frameEnd else { break }
            let payload = bufferedData.subdata(in: headerEnd..<frameEnd)
            let message: CounterPeerMessage
            do {
                message = try JSONDecoder().decode(CounterPeerMessage.self, from: payload)
            } catch {
                discardBufferedPrefix(consumedByteCount)
                throw error
            }
            messages.append(message)
            consumedByteCount = frameEnd
        }
        discardBufferedPrefix(consumedByteCount)
        return messages
    }

    private mutating func discardBufferedPrefix(_ byteCount: Int) {
        guard byteCount > 0 else { return }
        bufferedData.removeSubrange(0..<byteCount)
    }

    public var bufferedByteCount: Int { bufferedData.count }
}

public enum CounterPeerFrameError: Error, Equatable {
    case invalidLength
    case frameTooLarge
}
