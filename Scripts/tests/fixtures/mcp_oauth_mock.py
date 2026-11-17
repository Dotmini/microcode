#!/usr/bin/env python3
"""Local OAuth 2.1 + MCP resource server mock for the Phase 2b auth regression.

Implements just enough of RFC 9728 / RFC 8414 / RFC 7591 / PKCE / RFC 8707 / RFC 9207 to exercise
MicroCode's MCPOAuthClient end to end. Behaviour switches: POST /control {"mode": "..."}.
"""
import base64, hashlib, json, secrets, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlencode

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18999
BASE = f"http://127.0.0.1:{PORT}"
ISSUER = f"{BASE}/as"
RESOURCE = f"{BASE}/mcp"

state = {"mode": "normal", "registrations": 0, "codes": {}, "access": {}, "refresh": {}, "token_requests": []}
lock = threading.Lock()


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, code, obj, headers=None):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        return self.rfile.read(length) if length else b""

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/.well-known/oauth-protected-resource/mcp":
            return self.send_json(200, {"resource": RESOURCE, "authorization_servers": [ISSUER], "scopes_supported": ["mcp.read"]})
        if url.path == "/.well-known/oauth-authorization-server/as":
            return self.send_json(200, {
                "issuer": ISSUER,
                "authorization_endpoint": f"{ISSUER}/authorize",
                "token_endpoint": f"{ISSUER}/token",
                "registration_endpoint": f"{ISSUER}/register",
                "code_challenge_methods_supported": ["S256"],
                "authorization_response_iss_parameter_supported": True,
            })
        if url.path == "/as/authorize":
            q = {k: v[0] for k, v in parse_qs(url.query).items()}
            if q.get("code_challenge_method") != "S256" or q.get("resource") != RESOURCE:
                return self.send_json(400, {"error": "invalid_request", "detail": q})
            code = secrets.token_urlsafe(16)
            with lock:
                state["codes"][code] = q
            params = {"code": code, "state": q["state"]}
            mode = state["mode"]
            if mode == "bad_iss":
                params["iss"] = "http://evil.example/as"
            elif mode != "no_iss":
                params["iss"] = ISSUER
            if mode == "bad_state":
                params["state"] = "forged"
            self.send_response(302)
            self.send_header("Location", q["redirect_uri"] + "?" + urlencode(params))
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if url.path == "/stats":
            with lock:
                return self.send_json(200, {"registrations": state["registrations"], "token_requests": state["token_requests"]})
        self.send_json(404, {"error": "not_found"})

    def do_POST(self):
        url = urlparse(self.path)
        raw = self.body()
        if url.path == "/control":
            with lock:
                state["mode"] = json.loads(raw or b"{}").get("mode", "normal")
            return self.send_json(200, {"ok": True})
        if url.path == "/as/register":
            meta = json.loads(raw)
            if meta.get("application_type") != "native" or meta.get("token_endpoint_auth_method") != "none":
                return self.send_json(400, {"error": "invalid_client_metadata"})
            with lock:
                state["registrations"] += 1
            return self.send_json(201, {"client_id": "mc-" + secrets.token_hex(4), **meta})
        if url.path == "/as/token":
            form = {k: v[0] for k, v in parse_qs(raw.decode()).items()}
            with lock:
                state["token_requests"].append(form.get("grant_type"))
            if form.get("resource") != RESOURCE:
                return self.send_json(400, {"error": "invalid_target"})
            if form.get("grant_type") == "authorization_code":
                with lock:
                    auth = state["codes"].pop(form.get("code"), None)
                if not auth or b64url(hashlib.sha256(form.get("code_verifier", "").encode()).digest()) != auth["code_challenge"]:
                    return self.send_json(400, {"error": "invalid_grant", "error_description": "PKCE verification failed"})
                if form.get("redirect_uri") != auth["redirect_uri"] or form.get("client_id") != auth["client_id"]:
                    return self.send_json(400, {"error": "invalid_grant"})
            elif form.get("grant_type") == "refresh_token":
                with lock:
                    if form.get("refresh_token") not in state["refresh"]:
                        return self.send_json(400, {"error": "invalid_grant"})
            else:
                return self.send_json(400, {"error": "unsupported_grant_type"})
            access, refresh = secrets.token_urlsafe(16), secrets.token_urlsafe(16)
            with lock:
                state["access"][access] = time.time() + 3600
                state["refresh"][refresh] = True
            return self.send_json(200, {"access_token": access, "token_type": "Bearer", "expires_in": 3600, "refresh_token": refresh})
        if url.path == "/mcp":
            auth = self.headers.get("Authorization", "")
            token = auth[7:] if auth.startswith("Bearer ") else ""
            with lock:
                valid = token in state["access"]
            if not valid:
                challenge = f'Bearer resource_metadata="{BASE}/.well-known/oauth-protected-resource/mcp", scope="mcp.read"'
                return self.send_json(401, {"error": "unauthorized"}, {"WWW-Authenticate": challenge})
            req = json.loads(raw or b"{}")
            return self.send_json(200, {"jsonrpc": "2.0", "id": req.get("id"), "result": {"tools": []}})
        self.send_json(404, {"error": "not_found"})


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"READY {BASE}", flush=True)
    server.serve_forever()
