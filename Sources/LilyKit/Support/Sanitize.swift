import Foundation

/// Escaping and validation for data that crosses into another language or the file system.
public enum Sanitize {
    public static let maxErrorLength = 300

    /// Error text that is safe to show in the UI or hand to page scripts: our own IPC messages as
    /// they are; system errors by their localized description with file paths and file URLs
    /// replaced; and nothing from Swift errors whose description is a type dump. Details belong in
    /// the private log, never on screen.
    /// Untrusted text shown in a dialog on one line: control, bidi and invisible format characters
    /// removed, whitespace collapsed, cut to `max` characters.
    public static func displayText(_ raw: String, max: Int = 120) -> String {
        let kept = raw.unicodeScalars.map { $0.properties.isWhitespace ? " " : $0 }.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate: return false
            default: return true
            }
        }
        let line = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > max ? String(line.prefix(max)) + "…" : line
    }

    public static func errorMessage(_ error: Error) -> String {
        if let ipc = error as? IPCError { return String(ipc.message.prefix(maxErrorLength)) }
        var text = error.localizedDescription
        // Errors with no description of their own read "The operation couldn’t be completed.
        // (Module.TypeName error 1.)": internal type names and nothing useful for the user.
        if text.range(of: #"\([^()]+ error -?\d+\.\)$"#, options: .regularExpression) != nil { return "Something went wrong." }
        text = text.replacingOccurrences(of: #"file://\S+"#, with: "a file", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<![\w:])(/(Users|private|var|tmp|Volumes|Applications|Library|System)(/[^\s“”"'’,;)]*)?)"#,
                                         with: "a location on this Mac", options: .regularExpression)
        return String(text.prefix(maxErrorLength))
    }

    /// HTML text and attribute content (both quote styles).
    public static func html(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(char)
            }
        }
        return out
    }

    /// Bidi overrides/isolates and other invisible format characters, used to disguise text,
    /// e.g. "invoice\u{202E}fdp.app" displaying as "invoiceppa.pdf".
    public static func isInvisibleControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F: return true
        case 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF: return true
        default: return false
        }
    }

    /// A download name that can't escape the folder, hide itself, or lie about its extension.
    public static func filename(_ suggested: String, fallback: String = "download") -> String {
        var view = String.UnicodeScalarView()
        for scalar in suggested.unicodeScalars where !isInvisibleControl(scalar) && scalar != "\n" && scalar != "\r" && scalar != "\t" {
            view.append(scalar == "/" || scalar == ":" || scalar == "\\" ? "_" : scalar)
        }
        var name = String(view).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() } // no hidden files, no "..", no "."
        if name.utf8.count > 200 {
            let ext = (name as NSString).pathExtension
            let base = (name as NSString).deletingPathExtension
            let keep = String(base.prefix(180))
            name = ext.isEmpty || ext.count > 15 ? keep : "\(keep).\(ext)"
        }
        return name.isEmpty ? fallback : name
    }

    /// Favicons are fetched by the app itself, outside WebKit's protections, so only HTTPS to public
    /// hosts: never loopback/LAN devices (request forgery), never embedded credentials.
    public static func isFetchableFavicon(_ url: URL) -> Bool {
        guard url.scheme == "https", var host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        while host.hasSuffix(".") { host.removeLast() } // "localhost." is still localhost
        // A last label that starts with a digit is an IPv4 form (2130706433, 0x7f.1, 127.1), never a real TLD.
        guard let last = host.split(separator: ".").last, last.first?.isNumber == false else { return false }
        return !HTTPSFirst.isPrivate(host)
    }

    /// True for loopback, link-local, private, unique-local, CGNAT, multicast and unspecified addresses.
    public static func isNonPublicAddress(_ address: String) -> Bool {
        let address = address.lowercased()
        if address.contains(":") {
            if address.hasPrefix("::ffff:"), address.contains(".") { return isNonPublicAddress(String(address.dropFirst(7))) }
            let first = address.split(separator: ":", omittingEmptySubsequences: false).first.flatMap { UInt16($0, radix: 16) } ?? 0
            return address == "::" || address == "::1" || first & 0xfe00 == 0xfc00 || first & 0xffc0 == 0xfe80 || first & 0xff00 == 0xff00
        }
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return true }
        let (a, b) = (octets[0], octets[1])
        return a == 0 || a == 10 || a == 127 || a >= 224 || (a == 169 && b == 254) || (a == 172 && b & 0xf0 == 16)
            || (a == 192 && b == 168) || (a == 100 && b & 0xc0 == 64)
    }

    #if os(macOS)
    /// The addresses a name resolves to; empty when it doesn't resolve. `Host` is macOS-only: the
    /// iOS app resolves through its own transport.
    public static func resolvedAddresses(of host: String) async -> [String] {
        await Task.detached { Host(name: host).addresses }.value
    }
    #endif
}
