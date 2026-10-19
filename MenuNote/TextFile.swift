import Foundation

/// Plain-text file helpers, kept free of UI so they can be tested on their own.
enum TextFile {
    /// Big5 (with Hong Kong extensions), common for older Traditional Chinese .txt files.
    static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))

    /// GB18030, the superset of GB2312 and GBK used for Simplified Chinese .txt files.
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    /// Reads a text file, trying UTF-8 first, then any BOM-marked encoding, then Big5 or GB18030.
    /// Returns the encoding it was read with, so saving can keep it.
    static func read(_ url: URL) throws -> (text: String, encoding: String.Encoding) {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) {
            // A few Chinese characters can happen to form valid UTF-8 (GB 谢谢 reads as Cyrillic лл);
            // prefer the Chinese reading when the UTF-8 one has no Chinese or Latin letters at all.
            if !hasHanOrLatin(s), let chinese = readChinese(data), isAllCommonHan(chinese.text) {
                return chinese
            }
            return (s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s, .utf8)
        }
        var detected = String.Encoding.utf8
        if let s = try? String(contentsOf: url, usedEncoding: &detected) {
            return (s, detected)
        }
        if let chinese = readChinese(data) {
            return chinese
        }
        throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [NSURLErrorKey: url])
    }

    /// Most Chinese text decodes without error as both Big5 and GB, so pick the likelier reading:
    /// first by byte layout, then, when that can't tell (often short text), by which reading has
    /// more common characters. Ties go to Big5, the long-standing default here.
    static func readChinese(_ data: Data) -> (text: String, encoding: String.Encoding)? {
        switch (String(data: data, encoding: big5), String(data: data, encoding: gb18030)) {
        case (nil, nil): return nil
        case (let b?, nil): return (b, big5)
        case (nil, let g?): return (g, gb18030)
        case (let b?, let g?):
            let votes = byteVotes(data)
            if votes.gb != votes.big5 { return votes.gb > votes.big5 ? (g, gb18030) : (b, big5) }
            return CommonHan.count(in: g) > CommonHan.count(in: b) ? (g, gb18030) : (b, big5)
        }
    }

    /// Counts byte pairs that only make sense as GB or as Big5:
    /// - Big5's common characters use leads A4–C6, often with trail bytes 40–7E, which GB2312 never uses;
    ///   leads A4–AF are kana, Greek and the like in GB, rare in Chinese prose.
    /// - GB2312 spreads its common characters over leads B0–F7 in pinyin order, so about half land
    ///   on C7–F7, where Big5 has only its less common characters. GB18030's four-byte forms put
    ///   30–39 in the second byte, which Big5 never does.
    static func byteVotes(_ data: Data) -> (gb: Int, big5: Int) {
        var gb = 0, big5 = 0
        var i = data.startIndex
        while i < data.endIndex {
            let lead = data[i]
            guard lead >= 0x81, data.index(after: i) < data.endIndex else {
                i = data.index(after: i)
                continue
            }
            let trail = data[data.index(after: i)]
            switch (lead, trail) {
            case (_, 0x30...0x39): gb += 1
            case (_, 0x40...0x7E): big5 += 1
            case (0xA4...0xAF, 0xA1...0xFE): big5 += 1
            case (0xC7...0xF7, 0xA1...0xFE): gb += 1
            default: break
            }
            // A four-byte GB18030 form is two of these pairs; skipping two bytes keeps us aligned either way.
            i = data.index(i, offsetBy: 2)
        }
        return (gb, big5)
    }

    private static func isAllCommonHan(_ text: String) -> Bool {
        let chars = text.filter { !$0.isASCII }
        return !chars.isEmpty && chars.allSatisfy(CommonHan.contains)
    }

    private static func hasHanOrLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            $0.isASCII ? $0.properties.isAlphabetic
                       : (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
        }
    }

    /// Saves in the given encoding, UTF-8 unless the caller chose to keep a file's original one.
    /// Fails rather than silently dropping characters the encoding can't hold.
    static func write(_ text: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard let data = text.data(using: encoding, allowLossyConversion: false) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding,
                             userInfo: [NSURLErrorKey: url, NSStringEncodingErrorKey: encoding.rawValue])
        }
        try data.write(to: url, options: .atomic)
    }

    /// Short name for the status line and alerts, e.g. "UTF-8", "Big5", "UTF-16".
    static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case big5: return "Big5"
        case gb18030: return "GB18030"
        default:
            let cf = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            if let iana = CFStringConvertEncodingToIANACharSetName(cf) as String? {
                return iana.uppercased()
            }
            return String.localizedName(of: encoding)
        }
    }

    /// Status-line counts: characters as people see them, and lines.
    static func stats(_ text: String) -> (characters: Int, lines: Int) {
        guard !text.isEmpty else { return (0, 0) }
        var lines = 1
        for ch in text where ch.isNewline { lines += 1 }
        return (text.count, lines)
    }
}
