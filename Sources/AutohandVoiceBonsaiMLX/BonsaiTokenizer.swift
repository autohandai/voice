import Foundation

/// The Qwen3.5 tokenizer, read from the model's Hugging Face
/// `tokenizer.json`: NFC normalization, the Qwen regex pre-tokenizer,
/// byte-level mapping and BPE merges, with added tokens (`<|im_start|>`,
/// `<|im_end|>`, `<think>`, ...) matched literally before anything else so
/// they are never split. Pure Swift; no MLX, so it runs on every Mac.
public final class BonsaiTokenizer: @unchecked Sendable {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidFormat(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidFormat(reason): "Invalid tokenizer.json: \(reason)"
            }
        }
    }

    /// Token id -> raw bytes (byte-level symbols decoded; added tokens as
    /// their UTF-8 text).
    private let tokenBytes: [[UInt8]]
    /// Byte -> id of its single-byte symbol.
    private let byteTokens: [Int]
    /// (left id << 32 | right id) -> (rank, merged id).
    private let merges: [UInt64: (rank: Int32, id: Int32)]
    private let addedTokens: [(bytes: [UInt8], id: Int)]
    private let addedFirstBytes: Set<UInt8>
    private let specialIDs: [String: Int]
    private let splitter: NSRegularExpression?
    private let normalizesNFC: Bool

    private let cacheLock = NSLock()
    private var cache: [String: [Int]] = [:]
    private static let cacheLimit = 8_192

    public var vocabularySize: Int { tokenBytes.count }

    public convenience init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.invalidFormat("not a JSON object") }
        guard let model = root["model"] as? [String: Any],
              model["type"] as? String == "BPE",
              let vocab = model["vocab"] as? [String: Int]
        else { throw Failure.invalidFormat("expected a BPE model with a vocab") }
        if model["byte_fallback"] as? Bool == true {
            throw Failure.invalidFormat("byte_fallback BPE is not supported")
        }

        // Pre-tokenizer: an optional regex Split followed by ByteLevel.
        var pattern: String?
        var hasByteLevel = false
        let preTokenizer = root["pre_tokenizer"] as? [String: Any]
        let steps = (preTokenizer?["pretokenizers"] as? [[String: Any]])
            ?? preTokenizer.map { [$0] } ?? []
        for step in steps {
            switch step["type"] as? String {
            case "Split":
                guard let regex = (step["pattern"] as? [String: Any])?["Regex"] as? String,
                      step["behavior"] as? String == "Isolated",
                      step["invert"] as? Bool != true
                else { throw Failure.invalidFormat("unsupported Split pre-tokenizer") }
                pattern = regex
            case "ByteLevel":
                if step["add_prefix_space"] as? Bool == true {
                    throw Failure.invalidFormat("add_prefix_space is not supported")
                }
                hasByteLevel = true
            default:
                throw Failure.invalidFormat("unsupported pre-tokenizer \(step["type"] ?? "nil")")
            }
        }
        guard hasByteLevel else {
            throw Failure.invalidFormat("expected a byte-level pre-tokenizer")
        }
        if let pattern {
            do {
                splitter = try NSRegularExpression(pattern: Self.icuPattern(pattern))
            } catch {
                throw Failure.invalidFormat("pre-tokenizer regex: \(error.localizedDescription)")
            }
        } else {
            splitter = nil
        }
        switch (root["normalizer"] as? [String: Any])?["type"] as? String {
        case nil: normalizesNFC = false
        case "NFC": normalizesNFC = true
        case let other?: throw Failure.invalidFormat("unsupported normalizer \(other)")
        }

        // Ids and their bytes.
        let unicodeToByte = Self.unicodeToByte
        let added = (root["added_tokens"] as? [[String: Any]]) ?? []
        var maxID = vocab.values.max() ?? -1
        for token in added {
            if let id = token["id"] as? Int { maxID = max(maxID, id) }
        }
        guard maxID >= 0 else { throw Failure.invalidFormat("empty vocab") }
        var bytes = [[UInt8]](repeating: [], count: maxID + 1)
        for (token, id) in vocab where id >= 0 {
            var tokenBytes: [UInt8] = []
            tokenBytes.reserveCapacity(token.unicodeScalars.count)
            for scalar in token.unicodeScalars {
                guard let byte = unicodeToByte[scalar.value] else {
                    throw Failure.invalidFormat("token \(id) is not byte-level")
                }
                tokenBytes.append(byte)
            }
            bytes[id] = tokenBytes
        }
        var addedTokens: [(bytes: [UInt8], id: Int)] = []
        var specialIDs: [String: Int] = [:]
        for token in added {
            guard let id = token["id"] as? Int, let content = token["content"] as? String,
                  !content.isEmpty
            else { throw Failure.invalidFormat("invalid added token") }
            bytes[id] = Array(content.utf8)
            addedTokens.append((Array(content.utf8), id))
            specialIDs[content] = id
        }
        // Longest first, so a token that prefixes another never wins.
        addedTokens.sort { $0.bytes.count > $1.bytes.count }
        self.addedTokens = addedTokens
        self.addedFirstBytes = Set(addedTokens.compactMap(\.bytes.first))
        self.specialIDs = specialIDs
        self.tokenBytes = bytes

        // A byte with no symbol in the vocab (never the case for Qwen3.5)
        // is dropped rather than mapped to a wrong id.
        var byteTokens = [Int](repeating: -1, count: 256)
        for byte in 0..<256 {
            let scalar = Self.byteToUnicode[byte]
            byteTokens[byte] = vocab[String(Character(Unicode.Scalar(scalar)!))] ?? -1
        }
        self.byteTokens = byteTokens

        let lines: [String]
        if let strings = model["merges"] as? [String] {
            lines = strings
        } else if let pairs = model["merges"] as? [[String]] {
            lines = pairs.map { $0.count == 2 ? $0[0] + " " + $0[1] : "" }
        } else {
            throw Failure.invalidFormat("missing merges")
        }
        self.merges = Self.mergeTable(lines, vocab: vocab)
    }

    /// Ranks each `"left right"` merge by its position. The ~250k vocab
    /// lookups dominate tokenizer loading, so chunks resolve in parallel
    /// (the vocab is only read) and are combined in rank order.
    private static func mergeTable(
        _ lines: [String],
        vocab: [String: Int]
    ) -> [UInt64: (rank: Int32, id: Int32)] {
        typealias Entry = (key: UInt64, rank: Int32, id: Int32)
        let chunkCount = max(1, min(16, ProcessInfo.processInfo.activeProcessorCount))
        let chunkSize = (lines.count + chunkCount - 1) / max(chunkCount, 1)
        var chunks = [[Entry]](repeating: [], count: chunkCount)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let start = chunk * chunkSize
            let end = min(lines.count, start + chunkSize)
            guard start < end else { return }
            var entries: [Entry] = []
            entries.reserveCapacity(end - start)
            for rank in start..<end {
                let line = lines[rank]
                guard let space = line.firstIndex(of: " ") else { continue }
                let leftText = String(line[..<space])
                let rightText = String(line[line.index(after: space)...])
                guard let left = vocab[leftText], let right = vocab[rightText],
                      let merged = vocab[leftText + rightText]
                else { continue }
                entries.append((
                    UInt64(UInt32(left)) << 32 | UInt64(UInt32(right)),
                    Int32(rank),
                    Int32(merged)
                ))
            }
            lock.lock()
            chunks[chunk] = entries
            lock.unlock()
        }
        var table: [UInt64: (rank: Int32, id: Int32)] = [:]
        table.reserveCapacity(lines.count)
        for entries in chunks {
            for entry in entries where table[entry.key] == nil {
                table[entry.key] = (entry.rank, entry.id)
            }
        }
        return table
    }

    /// Id of an added token such as `<|im_end|>`.
    public func specialTokenID(_ content: String) -> Int? {
        specialIDs[content]
    }

    /// Raw bytes of one token (for streaming detokenization).
    public func bytes(for id: Int) -> [UInt8] {
        guard id >= 0, id < tokenBytes.count else { return [] }
        return tokenBytes[id]
    }

    public func decode(_ ids: [Int]) -> String {
        var bytes: [UInt8] = []
        for id in ids { bytes += self.bytes(for: id) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func encode(_ text: String) -> [Int] {
        var ids: [Int] = []
        let utf8 = Array(text.utf8)
        var segmentStart = 0
        var index = 0
        while index < utf8.count {
            if addedFirstBytes.contains(utf8[index]),
               let token = addedToken(in: utf8, at: index) {
                if segmentStart < index {
                    encodeOrdinary(Array(utf8[segmentStart..<index]), into: &ids)
                }
                ids.append(token.id)
                index += token.bytes.count
                segmentStart = index
            } else {
                index += 1
            }
        }
        if segmentStart < utf8.count {
            encodeOrdinary(Array(utf8[segmentStart...]), into: &ids)
        }
        return ids
    }

    // MARK: - Encoding

    private func addedToken(in utf8: [UInt8], at index: Int) -> (bytes: [UInt8], id: Int)? {
        for token in addedTokens where index + token.bytes.count <= utf8.count {
            if utf8[index..<(index + token.bytes.count)].elementsEqual(token.bytes) {
                return token
            }
        }
        return nil
    }

    private func encodeOrdinary(_ utf8: [UInt8], into ids: inout [Int]) {
        var text = String(decoding: utf8, as: UTF8.self)
        if normalizesNFC { text = text.precomposedStringWithCanonicalMapping }
        for piece in pieces(of: text) {
            ids += encodePiece(piece)
        }
    }

    /// Splits like the `Isolated` Split pre-tokenizer: every match and
    /// every gap between matches is its own piece.
    private func pieces(of text: String) -> [String] {
        guard let splitter else { return [text] }
        let string = text as NSString
        var result: [String] = []
        var cursor = 0
        for match in splitter.matches(
            in: text,
            range: NSRange(location: 0, length: string.length)
        ) where match.range.length > 0 {
            if match.range.location > cursor {
                result.append(string.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)
                ))
            }
            result.append(string.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        if cursor < string.length {
            result.append(string.substring(from: cursor))
        }
        return result
    }

    private func encodePiece(_ piece: String) -> [Int] {
        cacheLock.lock()
        if let cached = cache[piece] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var symbols = piece.utf8.compactMap { byte -> Int32? in
            let id = byteTokens[Int(byte)]
            return id >= 0 ? Int32(id) : nil
        }
        while symbols.count > 1 {
            var bestRank = Int32.max
            var bestID: Int32 = -1
            var bestLeft: Int32 = -1
            var bestRight: Int32 = -1
            for i in 0..<(symbols.count - 1) {
                let key = UInt64(UInt32(bitPattern: symbols[i])) << 32
                    | UInt64(UInt32(bitPattern: symbols[i + 1]))
                if let merge = merges[key], merge.rank < bestRank {
                    bestRank = merge.rank
                    bestID = merge.id
                    bestLeft = symbols[i]
                    bestRight = symbols[i + 1]
                }
            }
            guard bestID >= 0 else { break }
            var merged: [Int32] = []
            merged.reserveCapacity(symbols.count)
            var i = 0
            while i < symbols.count {
                if i + 1 < symbols.count, symbols[i] == bestLeft, symbols[i + 1] == bestRight {
                    merged.append(bestID)
                    i += 2
                } else {
                    merged.append(symbols[i])
                    i += 1
                }
            }
            symbols = merged
        }
        let result = symbols.map(Int.init)

        cacheLock.lock()
        if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[piece] = result
        cacheLock.unlock()
        return result
    }

    // MARK: - Byte-level tables and regex

    /// GPT-2's reversible byte -> printable code point table.
    static let byteToUnicode: [UInt32] = {
        var printable: [Int] = Array(0x21...0x7E) + Array(0xA1...0xAC) + Array(0xAE...0xFF)
        var codepoints = printable
        var next = 0
        for byte in 0..<256 where !printable.contains(byte) {
            printable.append(byte)
            codepoints.append(256 + next)
            next += 1
        }
        var table = [UInt32](repeating: 0, count: 256)
        for (byte, codepoint) in zip(printable, codepoints) {
            table[byte] = UInt32(codepoint)
        }
        return table
    }()

    static let unicodeToByte: [UInt32: UInt8] = {
        var table: [UInt32: UInt8] = [:]
        for (byte, scalar) in byteToUnicode.enumerated() {
            table[scalar] = UInt8(byte)
        }
        return table
    }()

    /// Hugging Face's regexes follow Unicode `White_Space` for `\s`; ICU's
    /// `\s` omits U+000B and U+0085, so spell the property out.
    static func icuPattern(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: #"\s"#, with: #"\p{White_Space}"#)
            .replacingOccurrences(of: #"\S"#, with: #"\P{White_Space}"#)
    }
}

/// Turns streamed token bytes into text, holding back the leading bytes of
/// a character split across tokens until the rest arrives.
public struct StreamingDetokenizer: Sendable {
    private var pending: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        // A UTF-8 character is at most 4 bytes: try cutting off up to 3
        // trailing bytes of an unfinished one.
        for cut in stride(from: pending.count, through: max(0, pending.count - 3), by: -1) {
            if let text = String(bytes: pending[0..<cut], encoding: .utf8) {
                pending.removeFirst(cut)
                return text
            }
        }
        // Invalid bytes that will never complete: emit them replaced.
        let text = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return text
    }

    public mutating func finish() -> String {
        defer { pending.removeAll() }
        return pending.isEmpty ? "" : String(decoding: pending, as: UTF8.self)
    }
}
