import Compression
import Foundation

/// Gzip decompression for downloaded reports.
///
/// Amazon returns reports as `GZIP_JSON`. If `URLSession` already decompressed
/// the body (S3 served `Content-Encoding: gzip`) the bytes are plain JSON and we
/// pass them through; otherwise we strip the gzip frame (RFC 1952) and inflate
/// the raw DEFLATE body with `COMPRESSION_ZLIB` (which is raw DEFLATE on Apple
/// platforms, RFC 1951).
enum ReportGunzip {
    /// Returns decompressed bytes, or the input unchanged if it isn't gzip.
    static func decompress(_ data: Data) -> Data? {
        guard isGzip(data) else { return data } // already plain JSON
        guard let deflate = strippingGzipFrame(data) else { return nil }
        return inflate(deflate)
    }

    private static func isGzip(_ data: Data) -> Bool {
        data.count >= 18 && data[data.startIndex] == 0x1F
            && data[data.startIndex + 1] == 0x8B && data[data.startIndex + 2] == 0x08
    }

    /// Removes the 10-byte gzip header (+ optional fields) and the 8-byte trailer.
    private static func strippingGzipFrame(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        let flags = bytes[3]
        var offset = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { offset = skipZeroTerminated(bytes, from: offset) } // FNAME
        if flags & 0x10 != 0 { offset = skipZeroTerminated(bytes, from: offset) } // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        guard offset < bytes.count - 8 else { return nil }
        return data.subdata(in: (data.startIndex + offset) ..< (data.endIndex - 8))
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) -> Int {
        var offset = start
        while offset < bytes.count, bytes[offset] != 0 {
            offset += 1
        }
        return offset + 1
    }

    private static func inflate(_ data: Data) -> Data? {
        let bufferSize = 1 << 16
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }

            var stream = compression_stream(
                dst_ptr: destination, dst_size: bufferSize,
                src_ptr: base, src_size: data.count,
                state: nil
            )
            guard compression_stream_init(
                &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB
            ) == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(&stream) }

            // `compression_stream_init` resets the buffers — set the source after it.
            stream.src_ptr = base
            stream.src_size = data.count

            var output = Data()
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            while true {
                stream.dst_ptr = destination
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, flags)
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(destination, count: produced) }
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}
