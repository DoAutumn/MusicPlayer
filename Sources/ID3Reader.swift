import CoreFoundation
import Foundation

enum ID3Reader {
    struct Tag: Sendable {
        var title: String?
        var artist: String?
        var album: String?
    }

    static func read(url: URL) -> Tag? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = read(handle, count: 10), header.count == 10,
              header.starts(with: [0x49, 0x44, 0x33]) else {
            return readV1(handle)
        }

        let version = header[3]
        let flags = header[5]
        if flags & 0x80 != 0 { return readV1(handle) }
        let tagSize = synchsafe(header.subdata(in: 6..<10))
        guard tagSize > 0, tagSize < 20_000_000 else { return readV1(handle) }

        var offset = 10
        if flags & 0x40 != 0, let extended = extendedHeaderSize(handle, version: version) {
            offset += extended
            try? handle.seek(toOffset: UInt64(offset))
        }

        let tagEnd = 10 + tagSize
        var tag = Tag()
        while offset + (version == 2 ? 6 : 10) <= tagEnd {
            if version == 2 {
                guard let frame = read(handle, count: 6), frame.count == 6 else { break }
                let id = String(bytes: frame.prefix(3), encoding: .ascii) ?? ""
                if id.isEmpty || frame[0] == 0 { break }
                let size = (Int(frame[3]) << 16) | (Int(frame[4]) << 8) | Int(frame[5])
                offset += 6
                guard size >= 0, offset + size <= tagEnd else { break }
                consume(handle, id: id, size: size, into: &tag)
                offset += size
            } else {
                guard let frame = read(handle, count: 10), frame.count == 10 else { break }
                let id = String(bytes: frame.prefix(4), encoding: .ascii) ?? ""
                if id.isEmpty || frame[0] == 0 { break }
                let size = version >= 4
                    ? synchsafe(frame.subdata(in: 4..<8))
                    : int32(frame.subdata(in: 4..<8))
                let frameFlags = frame[9]
                offset += 10
                guard size >= 0, offset + size <= tagEnd else { break }
                let compressed = frameFlags & 0x80 != 0
                let encrypted = frameFlags & 0x40 != 0
                if compressed || encrypted {
                    try? handle.seek(toOffset: UInt64(offset + size))
                } else {
                    consume(handle, id: id, size: size, into: &tag)
                }
                offset += size
            }
            if tag.title != nil, tag.artist != nil, tag.album != nil { break }
        }

        if tag.title == nil, tag.artist == nil {
            return readV1(handle) ?? tag
        }
        if tag.artist == nil || tag.title == nil, let v1 = readV1(handle) {
            if tag.title == nil { tag.title = v1.title }
            if tag.artist == nil { tag.artist = v1.artist }
            if tag.album == nil { tag.album = v1.album }
        }
        return tag
    }

    private static func consume(_ handle: FileHandle, id: String, size: Int, into tag: inout Tag) {
        let wanted = ["TIT2", "TT2", "TPE1", "TP1", "TALB", "TAL"]
        guard wanted.contains(id), size > 1, size < 8_192 else {
            skip(handle, size)
            return
        }
        guard let body = read(handle, count: size) else { return }
        guard let text = decode(body) else { return }
        switch id {
        case "TIT2", "TT2": tag.title = text
        case "TPE1", "TP1": tag.artist = text
        case "TALB", "TAL": tag.album = text
        default: break
        }
    }

    private static func extendedHeaderSize(_ handle: FileHandle, version: UInt8) -> Int? {
        guard let sizeBytes = read(handle, count: 4), sizeBytes.count == 4 else { return nil }
        if version >= 4 {
            return synchsafe(sizeBytes)
        }
        return 4 + int32(sizeBytes)
    }

    private static func readV1(_ handle: FileHandle) -> Tag? {
        guard let end = try? handle.seekToEnd(), end >= 128 else { return nil }
        try? handle.seek(toOffset: end - 128)
        guard let data = read(handle, count: 128), data.count == 128,
              data.starts(with: [0x54, 0x41, 0x47]) else { return nil }
        let title = decodeLegacy(data.subdata(in: 3..<33))
        let artist = decodeLegacy(data.subdata(in: 33..<63))
        let album = decodeLegacy(data.subdata(in: 63..<93))
        if title == nil, artist == nil, album == nil { return nil }
        return Tag(title: title, artist: artist, album: album)
    }

    private static func decode(_ data: Data) -> String? {
        guard let encoding = data.first else { return nil }
        let raw = data.dropFirst()
        let text: String?
        switch encoding {
        case 0:
            text = decodeLegacy(Data(raw.prefix { $0 != 0 }))
        case 1:
            text = String(data: raw, encoding: .utf16)
        case 2:
            var bom = Data([0xFE, 0xFF])
            bom.append(contentsOf: raw)
            text = String(data: bom, encoding: .utf16)
        case 3:
            text = String(data: raw.prefix { $0 != 0 }, encoding: .utf8)
        default:
            text = nil
        }
        return clean(text)
    }

    private static func decodeLegacy(_ data: Data) -> String? {
        let bytes = Data(data.prefix { $0 != 0 })
        guard !bytes.isEmpty else { return nil }
        if let gb = String(data: bytes, encoding: gb18030), !gb.isEmpty { return clean(gb) }
        return clean(String(data: bytes, encoding: .utf8))
    }

    private static func clean(_ text: String?) -> String? {
        guard var text else { return nil }
        text = text.replacingOccurrences(of: "\0", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static func skip(_ handle: FileHandle, _ size: Int) {
        guard size > 0, let current = try? handle.offset() else { return }
        try? handle.seek(toOffset: current + UInt64(size))
    }

    private static func read(_ handle: FileHandle, count: Int) -> Data? {
        guard count > 0 else { return Data() }
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let chunk = try? handle.read(upToCount: count - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data.count == count ? data : nil
    }

    private static func synchsafe(_ data: Data) -> Int {
        data.reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
    }

    private static func int32(_ data: Data) -> Int {
        data.reduce(0) { ($0 << 8) | Int($1) }
    }
}
