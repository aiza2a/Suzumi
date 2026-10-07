import Foundation

/// URLProtocol may expose URLSession request bodies as a stream; materialize them
/// so assertions can inspect `httpBody` consistently.
enum URLRequestTestSupport {
    static func materializedBody(_ request: URLRequest) -> URLRequest {
        var materialized = request
        guard materialized.httpBody == nil,
              let stream = materialized.httpBodyStream
        else { return materialized }

        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var body = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            body.append(buffer, count: read)
        }

        materialized.httpBody = body
        materialized.httpBodyStream = nil
        return materialized
    }
}