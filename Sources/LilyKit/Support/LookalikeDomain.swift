import Foundation

/// Spots addresses that imitate another site with look-alike characters (`аpple.com` with a Cyrillic "а"),
/// the trick behind most IDN homograph phishing. Pure logic: the apps decide how to warn.
public enum LookalikeDomain {
    public enum Reason: String, Sendable, Equatable {
        /// One label mixes scripts that real names rarely mix (Latin with Cyrillic or Greek).
        case mixedScript
        /// A label written entirely in Cyrillic or Greek letters that all have a Latin twin (`аррӏе`).
        case allConfusable
        /// A label that is invalid punycode, or hides a character that shouldn't be in a name.
        case malformed
    }

    public struct Verdict: Sendable, Equatable {
        public let reason: Reason
        /// The host as a person would read it (punycode decoded), for the warning.
        public let displayHost: String
        public let asciiHost: String

        public init(reason: Reason, displayHost: String, asciiHost: String) {
            self.reason = reason
            self.displayHost = displayHost
            self.asciiHost = asciiHost
        }
    }

    /// Nil for an ordinary address (including honest single-script IDNs such as `münchen.de` or `яндекс.рф`).
    public nonisolated static func assess(_ url: URL?) -> Verdict? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty, !host.contains(":") else { return nil }
        return assess(host: host)
    }

    public nonisolated static func assess(host: String) -> Verdict? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        var decoded: [String] = []
        var found: Reason?
        for label in labels {
            var text = label
            if label.hasPrefix("xn--") {
                guard let value = Punycode.decode(String(label.dropFirst(4))), !value.isEmpty else {
                    decoded.append(label)
                    found = found ?? .malformed
                    continue
                }
                text = value
            }
            decoded.append(text)
            if text.unicodeScalars.contains(where: invisibleOrControl) { found = found ?? .malformed }
            if let reason = classify(text) { found = found ?? reason }
        }
        guard let reason = found else { return nil }
        let display = decoded.joined(separator: ".")
        let ascii = labels.map { label in label.unicodeScalars.allSatisfy(\.isASCII) ? label : "xn--" + (Punycode.encode(label) ?? "") }.joined(separator: ".")
        return Verdict(reason: reason, displayHost: display, asciiHost: ascii)
    }

    private enum Script { case latin, cyrillic, greek, other }

    private nonisolated static func script(of scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x30...0x39, 0x2D: return nil // digits and hyphen are neutral
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: return .latin
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return .cyrillic
        case 0x370...0x3FF, 0x1F00...0x1FFF: return .greek
        default: return .other
        }
    }

    private nonisolated static func classify(_ label: String) -> Reason? {
        let scalars = Array(label.unicodeScalars)
        let scripts = Set(scalars.compactMap(script(of:)))
        // Mixing Latin with Cyrillic or Greek: the classic spoof. (Other scripts together, such as Japanese
        // kana with Han, are normal and left alone.)
        if scripts.contains(.latin), scripts.contains(.cyrillic) || scripts.contains(.greek) { return .mixedScript }
        if scripts.contains(.cyrillic), scripts.contains(.greek) { return .mixedScript }
        // Entirely Cyrillic or Greek, but every letter could be typed on a Latin keyboard.
        if scripts.count == 1, scripts.first == .cyrillic || scripts.first == .greek {
            let letters = scalars.filter { script(of: $0) != nil }
            if letters.count >= 2, letters.allSatisfy({ latinTwins.contains($0.value) }) { return .allConfusable }
        }
        return nil
    }

    /// Zero-width, bidi-control and similar characters that make two different names look the same.
    private nonisolated static func invisibleOrControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0xAD, 0x34F, 0x61C, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180B...0x180E,
             0x200B...0x200F, 0x202A...0x202E, 0x2060...0x206F, 0x3164, 0xFE00...0xFE0F, 0xFEFF, 0xFFA0, 0xFFF9...0xFFFB:
            return true
        default: return false
        }
    }

    /// Cyrillic and Greek letters that look like a Latin letter in common fonts.
    private nonisolated static let latinTwins: Set<UInt32> = [
        0x430, 0x435, 0x43E, 0x440, 0x441, 0x443, 0x445, 0x455, 0x456, 0x458, 0x4CF, 0x44C, // а е о р с у х ѕ і ј ӏ ь
        0x3BF, 0x3B1, 0x3BD, 0x3C1, 0x3C5, 0x3B9, 0x3BA, // ο α ν ρ υ ι κ
    ]
}

/// RFC 3492 punycode, enough to read and write IDN labels.
enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    private static func adapt(_ delta: Int, _ points: Int, first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / points
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 { delta /= base - tMin; k += base }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }

    nonisolated static func decode(_ input: String) -> String? {
        guard input.unicodeScalars.allSatisfy(\.isASCII), input.utf8.count <= 63 else { return nil }
        var output: [Unicode.Scalar] = []
        var rest = Substring(input)
        if let dash = input.lastIndex(of: "-") {
            output = input[..<dash].unicodeScalars.map { $0 }
            rest = input[input.index(after: dash)...]
        }
        var n = initialN, i = 0, bias = initialBias
        var iterator = rest.utf8.makeIterator()
        while let first = iterator.next() {
            let oldI = i
            var w = 1, k = base
            var byte: UInt8? = first
            while true {
                guard let b = byte else { return nil }
                let digit: Int
                switch b {
                case 0x30...0x39: digit = Int(b) - 0x30 + 26
                case 0x41...0x5A: digit = Int(b) - 0x41
                case 0x61...0x7A: digit = Int(b) - 0x61
                default: return nil
                }
                let (product, overflow1) = digit.multipliedReportingOverflow(by: w)
                let (sum, overflow2) = i.addingReportingOverflow(product)
                if overflow1 || overflow2 { return nil }
                i = sum
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                let (nextW, overflow3) = w.multipliedReportingOverflow(by: base - t)
                if overflow3 { return nil }
                w = nextW
                k += base
                byte = iterator.next()
            }
            bias = adapt(i - oldI, output.count + 1, first: oldI == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            guard n <= 0x10FFFF, let scalar = Unicode.Scalar(UInt32(n)) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: output)
        return String(text)
    }

    nonisolated static func encode(_ input: String) -> String? {
        let scalars = Array(input.unicodeScalars)
        var output = String(String.UnicodeScalarView(scalars.filter(\.isASCII)))
        let basic = output.count
        var handled = basic
        if basic > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        func digit(_ d: Int) -> Character { Character(Unicode.Scalar(UInt8(d < 26 ? d + 0x61 : d - 26 + 0x30))) }
        while handled < scalars.count {
            guard let m = scalars.map({ Int($0.value) }).filter({ $0 >= n }).min() else { return nil }
            let (add, overflow) = (m - n).multipliedReportingOverflow(by: handled + 1)
            if overflow { return nil }
            delta += add
            n = m
            for scalar in scalars {
                let c = Int(scalar.value)
                if c < n { delta += 1 }
                if c == n {
                    var q = delta, k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, first: handled == basic)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return output
    }
}
