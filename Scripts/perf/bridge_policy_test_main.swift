// Policy test for the loopback MCP bridge (functions are extracted verbatim from MicroCode/Services/MCPServer.swift by run_perf_gate.sh).
import Foundation
var failures = 0
func check(_ name: String, _ got: Bool, _ want: Bool) { if got != want { failures += 1; print("FAIL \(name): got \(got) want \(want)") } }
for o in ["https://dotmini.net", "https://microcode.dotmini.net", "https://a.b.dotmini.net", "http://localhost:3000", "https://localhost", "http://127.0.0.1:8080", "http://[::1]:3000"] {
    check("origin allowed \(o)", MCPServer.isAllowedBridgeOrigin(o), true)
}
for o in ["https://evil.example", "https://dotmini.net.evil.com", "http://dotmini.net", "https://evildotmini.net", "null", "", "file://", "https://x.dotmini.net/path", "https://dotmini.net:8443@evil.com", "http://192.168.1.47:3000", "ftp://localhost"] {
    check("origin denied \(o)", MCPServer.isAllowedBridgeOrigin(o), false)
}
for h in ["127.0.0.1:18888", "localhost:18888", "[::1]:18888", "localhost", "LOCALHOST:1", "127.0.0.1"] {
    check("host allowed \(h)", MCPServer.isLoopbackHostHeader(h), true)
}
check("host allowed nil (HTTP/1.0 native client)", MCPServer.isLoopbackHostHeader(nil), true)
for h in ["evil.example:18888", "192.168.1.47:18888", "127.0.0.1.evil.com", "localhost.evil.com:80", "[::2]:1", "0.0.0.0:18888"] {
    check("host denied \(h)", MCPServer.isLoopbackHostHeader(h), false)
}
print("bridge-policy: failures=\(failures)")
exit(failures == 0 ? 0 : 1)
