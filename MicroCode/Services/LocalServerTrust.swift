import Foundation

/// Who may use MicroCode's local HTTP servers (phone companion, subscription gateway, collaboration, LLM gateway)
/// without presenting a token.
///
/// "Came from 127.0.0.1" is not enough: (1) the online relay and SSH/Cloudflare tunnels forward remote phones'
/// requests to 127.0.0.1, (2) any web page open in the user's browser can send requests to 127.0.0.1, and
/// (3) DNS rebinding makes such a page same-origin. A request counts as "this Mac" only when it arrives on loopback,
/// carries no proxy/relay header, addresses a loopback Host, and — if a browser sent it — comes from a loopback
/// Origin. Everything else must authenticate.
enum LocalServerTrust {
    /// Headers added by the Dotmini relay, reverse proxies and tunnels (cloudflared, localhost.run, nginx…).
    static let forwardingHeaders: [String] = [
        "x-dotmini-relay", "x-forwarded-for", "x-forwarded-host", "x-forwarded-proto", "forwarded",
        "x-real-ip", "cf-connecting-ip", "cf-ray", "true-client-ip", "via"
    ]

    /// `headers` must have lower-cased keys.
    static func isTrustedLocalRequest(remoteIP: String, headers: [String: String]) -> Bool {
        guard isLoopbackAddress(remoteIP) else { return false }
        guard !forwardingHeaders.contains(where: { headers[$0] != nil }) else { return false }
        guard isLoopbackHost(headers["host"]) else { return false }
        if let origin = headers["origin"], !origin.isEmpty, origin != "null" {
            return isLoopbackOrigin(origin)
        }
        return headers["origin"] != "null"   // sandboxed iframes / file:// pages send "null"
    }

    static func isLoopbackAddress(_ ip: String) -> Bool {
        let trimmed = ip.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed == "127.0.0.1" || trimmed == "::1" || trimmed == "::ffff:127.0.0.1"
    }

    /// `localhost`, `127.0.0.1`, `[::1]`, with or without a port. A missing Host (HTTP/1.0 tools) is treated as loopback.
    static func isLoopbackHost(_ host: String?) -> Bool {
        guard let raw = host?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return true }
        let name: String
        if raw.hasPrefix("[") {
            name = raw.firstIndex(of: "]").map { String(raw[raw.startIndex...$0]) } ?? raw
        } else {
            name = raw.split(separator: ":", maxSplits: 1).first.map(String.init) ?? raw
        }
        return name == "localhost" || name == "127.0.0.1" || name == "[::1]"
    }

    static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard !x.isEmpty, x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
