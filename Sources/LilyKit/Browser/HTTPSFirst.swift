import Foundation

/// HTTPS-First: top-level `http://` navigations to public hosts are tried over HTTPS first (as in
/// Safari and Chrome). A host that can't do HTTPS is loaded over HTTP only after the user agrees,
/// and only for the rest of this session.
@MainActor
public enum HTTPSFirst {
    /// Hosts the user allowed over HTTP, or whose HTTPS endpoint redirects back to HTTP.
    public static var allowedHTTPHosts: Set<String> = []

    public static func upgrade(_ url: URL) -> URL? {
        Preferences.httpsFirstEnabled ? upgrade(url, allowed: allowedHTTPHosts) : nil
    }

    public nonisolated static func upgrade(_ url: URL, allowed: Set<String>) -> URL? {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased(), !isPrivate(host), !allowed.contains(host),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"
        if parts.port == 80 { parts.port = nil }
        return parts.url
    }

    /// Hosts that commonly have no certificate: loopback, LAN names, IP literals, single-label names.
    public nonisolated static func isPrivate(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if isLoopback(host) || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.hasSuffix(".internal") { return true }
        if host.contains(":") { return true } // IPv6 literal
        if !host.contains(".") { return true }
        return host.split(separator: ".").count == 4 && host.split(separator: ".").allSatisfy { UInt8($0) != nil }
    }

    public nonisolated static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        // Only a four-octet IPv4 literal in 127.0.0.0/8; "127.evil.example" is a DNS name.
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) && UInt8($0) != nil }) else { return false }
        return octets[0] == "127"
    }
}
