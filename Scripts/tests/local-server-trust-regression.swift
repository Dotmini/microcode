import Foundation

// LocalServerTrust (Services/LocalServerTrust.swift): only real local processes skip auth on MicroCode's local servers.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}
func trusted(_ ip: String, _ headers: [String: String]) -> Bool { LocalServerTrust.isTrustedLocalRequest(remoteIP: ip, headers: headers) }

// Real local clients: curl, CLI agents (claude/codex via OPENAI_BASE_URL), the Mac's own browser on localhost.
check(trusted("127.0.0.1", ["host": "127.0.0.1:20128"]), "CLI agent on loopback")
check(trusted("::1", ["host": "localhost:8470"]), "IPv6 loopback")
check(trusted("127.0.0.1", [:]), "HTTP/1.0 tool without Host")
check(trusted("127.0.0.1", ["host": "localhost:8470", "origin": "http://localhost:8470"]), "companion page opened on the Mac itself")
check(trusted("127.0.0.1", ["host": "[::1]:8470", "origin": "http://[::1]:8470"]), "IPv6 loopback origin")

// Remote phones arriving through the relay or a tunnel (forwarded to 127.0.0.1).
check(!trusted("127.0.0.1", ["host": "127.0.0.1:8470", "x-dotmini-relay": "1"]), "Dotmini relay frame is not the Mac")
check(!trusted("127.0.0.1", ["host": "abc.trycloudflare.com", "cf-connecting-ip": "1.2.3.4"]), "cloudflared tunnel")
check(!trusted("127.0.0.1", ["host": "127.0.0.1:8470", "x-forwarded-for": "5.6.7.8"]), "reverse proxy")
check(!trusted("127.0.0.1", ["host": "127.0.0.1:8470", "forwarded": "for=5.6.7.8"]), "RFC 7239 Forwarded")

// Web pages in the user's browser.
check(!trusted("127.0.0.1", ["host": "127.0.0.1:8470", "origin": "https://evil.example"]), "cross-site fetch to localhost")
check(!trusted("127.0.0.1", ["host": "evil.example:8470"]), "DNS rebinding (Host is the attacker's name)")
check(!trusted("127.0.0.1", ["host": "127.0.0.1:20128", "origin": "null"]), "sandboxed iframe / file:// origin")
check(!trusted("127.0.0.1", ["host": "localhost.evil.example:8470"]), "lookalike host")

// LAN peers never count as local.
check(!trusted("192.168.1.20", ["host": "192.168.1.5:8470"]), "LAN phone")
check(!trusted("100.101.102.103", ["host": "mac.tailnet.ts.net:8470"]), "Tailscale peer")

check(LocalServerTrust.constantTimeEquals("abc123", "abc123") && !LocalServerTrust.constantTimeEquals("abc123", "abc124")
      && !LocalServerTrust.constantTimeEquals("", "") && !LocalServerTrust.constantTimeEquals("abc", "abcd"), "constant-time compare")

if failures == 0 { print("LOCAL SERVER TRUST REGRESSION: PASS") } else { print("LOCAL SERVER TRUST REGRESSION: \(failures) FAILURE(S)"); exit(1) }
