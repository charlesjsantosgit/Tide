import Foundation
import Compression

enum ZipError: Error { case invalid, unsupported }

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// Raw DEFLATE (what ZIP method 8 wants) via Apple's Compression framework.
enum Deflate {
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let cap = data.count + data.count / 50 + 4096
        var dst = [UInt8](repeating: 0, count: cap)
        let n = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&dst, cap, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(dst[0..<n]) : nil
    }
    static func decompress(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        guard !data.isEmpty else { return nil }
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let n = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&dst, expectedSize, base, data.count, nil, COMPRESSION_ZLIB)
        }
        return n == expectedSize ? Data(dst) : nil
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    mutating func le32(_ v: UInt32) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    func u16(_ i: Int) -> UInt16 {
        let b = startIndex + i
        return UInt16(self[b]) | (UInt16(self[b + 1]) << 8)
    }
    func u32(_ i: Int) -> UInt32 {
        let b = startIndex + i
        return UInt32(self[b]) | (UInt32(self[b + 1]) << 8) | (UInt32(self[b + 2]) << 16) | (UInt32(self[b + 3]) << 24)
    }
}

struct ZipWriter {
    private struct Entry { let name: [UInt8]; let crc: UInt32; let method: UInt16; let compressedSize: UInt32; let size: UInt32; let offset: UInt32 }
    private var entries: [Entry] = []
    private var body = Data()

    init() {}

    mutating func add(_ name: String, _ data: Data) {
        let crc = CRC32.checksum(data)
        var method: UInt16 = 0
        var payload = data
        if let d = Deflate.compress(data), d.count < data.count { method = 8; payload = d }
        let nameBytes = Array(name.utf8)
        let offset = UInt32(body.count)
        var h = Data()
        h.le32(0x04034b50); h.le16(20); h.le16(0x0800); h.le16(method); h.le16(0); h.le16(0x21)
        h.le32(crc); h.le32(UInt32(payload.count)); h.le32(UInt32(data.count)); h.le16(UInt16(nameBytes.count)); h.le16(0)
        h.append(contentsOf: nameBytes)
        h.append(payload)
        body.append(h)
        entries.append(Entry(name: nameBytes, crc: crc, method: method, compressedSize: UInt32(payload.count), size: UInt32(data.count), offset: offset))
    }

    func finish() -> Data {
        var cd = Data()
        for e in entries {
            cd.le32(0x02014b50); cd.le16(20); cd.le16(20); cd.le16(0x0800); cd.le16(e.method); cd.le16(0); cd.le16(0x21)
            cd.le32(e.crc); cd.le32(e.compressedSize); cd.le32(e.size); cd.le16(UInt16(e.name.count))
            cd.le16(0); cd.le16(0); cd.le16(0); cd.le16(0); cd.le32(0); cd.le32(e.offset)
            cd.append(contentsOf: e.name)
        }
        var out = body
        out.append(cd)
        out.le32(0x06054b50); out.le16(0); out.le16(0); out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(cd.count)); out.le32(UInt32(body.count)); out.le16(0)
        return out
    }
}

struct ZipReader {
    struct Entry { let name: String; let method: UInt16; let compressedSize: Int; let size: Int; let localHeaderOffset: Int }
    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init(data input: Data) throws {
        let data = Data(input)   // rebased so startIndex == 0
        self.data = data
        guard data.count >= 22 else { throw ZipError.invalid }
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 70_000)
        while i >= floor {
            if data.u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalid }
        let count = Int(data.u16(eocd + 10))
        let cdOffset = Int(data.u32(eocd + 16))
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x02014b50 else { throw ZipError.invalid }
            let method = data.u16(p + 10)
            let csize = Int(data.u32(p + 20)), usize = Int(data.u32(p + 24))
            let nlen = Int(data.u16(p + 28)), elen = Int(data.u16(p + 30)), clen = Int(data.u16(p + 32))
            let lho = Int(data.u32(p + 42))
            guard p + 46 + nlen <= data.count else { throw ZipError.invalid }
            let name = String(decoding: data[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: csize, size: usize, localHeaderOffset: lho)
            p += 46 + nlen + elen + clen
        }
    }

    func contents(of name: String) -> Data? {
        guard let e = entries[name] else { return nil }
        let p = e.localHeaderOffset
        guard p + 30 <= data.count, data.u32(p) == 0x04034b50 else { return nil }
        let nlen = Int(data.u16(p + 26)), elen = Int(data.u16(p + 28))
        let start = p + 30 + nlen + elen
        guard start + e.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return Deflate.decompress(raw, expectedSize: e.size)
        default: return nil
        }
    }
}
