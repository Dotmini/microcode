//
//  ClaudeWebSessionBridge.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  First-party WebKit session bridge for users who sign into claude.ai via
//  WebSubscriptionLoginSheet (`sessionKey=sk-ant-sid01-...`) without having
//  Claude Code CLI (`claude`) installed. Never solves or bypasses anti-bot challenges;
//  if claude.ai requires interactive login or verification, surfaces a clear error.
//

import Foundation
import WebKit

@MainActor
public final class ClaudeWebSessionBridge: NSObject, WKNavigationDelegate {
    public static let shared = ClaudeWebSessionBridge()

    private var webView: WKWebView?
    private var isLoaded: Bool = false
    private var navContinuation: CheckedContinuation<Void, Error>?

    private override init() {
        super.init()
    }

    public func syncSessionKeyCookie(_ rawToken: String) async {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let value: String = {
            if let range = trimmed.range(of: "sessionKey=") {
                let sub = trimmed[range.upperBound...]
                return String(sub.prefix(while: { $0 != ";" && !$0.isWhitespace }))
            }
            return trimmed
        }()
        guard value.hasPrefix("sk-ant-sid") else { return }
        let props: [HTTPCookiePropertyKey: Any] = [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: value,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86400 * 30)
        ]
        if let cookie = HTTPCookie(properties: props) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                    cont.resume()
                }
            }
        }
    }

    private func ensureReadyWebView(sessionToken: String) async throws -> WKWebView {
        await syncSessionKeyCookie(sessionToken)
        if let existing = webView, isLoaded, existing.url?.host?.contains("claude.ai") == true {
            return existing
        }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: cfg)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        wv.navigationDelegate = self
        self.webView = wv
        self.isLoaded = false

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.navContinuation = cont
            wv.load(URLRequest(url: URL(string: "https://claude.ai/new")!, timeoutInterval: 20))
        }
        self.isLoaded = true
        return wv
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let cont = navContinuation {
            navContinuation = nil
            cont.resume()
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let cont = navContinuation {
            navContinuation = nil
            cont.resume(throwing: error)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let cont = navContinuation {
            navContinuation = nil
            cont.resume(throwing: error)
        }
    }

    public func streamPrompt(
        prompt: String,
        systemPrompt: String?,
        conversationHistory: [(role: String, content: String)],
        model: String,
        sessionToken: String,
        toolsPrompt: String?,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let wv = try await ensureReadyWebView(sessionToken: sessionToken)

        var blocks: [String] = []
        if let sys = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !sys.isEmpty {
            blocks.append("<system_instructions>\n\(sys)\n</system_instructions>")
        }
        if let toolsPrompt, !toolsPrompt.isEmpty {
            blocks.append(toolsPrompt)
        }
        if !conversationHistory.isEmpty {
            let recent = conversationHistory.suffix(12)
            let formatted = recent.map { "[\($0.role.uppercased())]: \($0.content)" }.joined(separator: "\n\n")
            blocks.append("<conversation_history>\n\(formatted)\n</conversation_history>")
        }
        blocks.append(prompt)
        let combinedPrompt = blocks.joined(separator: "\n\n")

        let lowerModel = model.lowercased()
        let claudeWebModel: String? = {
            if lowerModel.contains("opus") { return "claude-opus-4-6" }
            if lowerModel.contains("haiku") { return "claude-haiku-4-5" }
            return nil // Let claude.ai use the subscriber's default flagship Sonnet model
        }()

        let jsBody = """
        const title = String(document.title || '');
        if (location.pathname.startsWith('/login')) {
            return JSON.stringify({ ok: false, status: 401, error: 'claude.ai web session expired. Reconnect in Settings → AI Provider → Subscription or run `claude login` in Terminal.' });
        }
        if (title.includes('Just a moment') || document.querySelector('#challenge-running, .cf-turnstile')) {
            return JSON.stringify({ ok: false, status: 403, error: 'claude.ai web session is gated by browser verification. Open Settings → AI Provider → Subscription → Claude to sign in interactively, or run `claude login` in Terminal.' });
        }
        const orgRes = await fetch('/api/organizations', { credentials: 'include', headers: { 'Accept': 'application/json' } });
        if (!orgRes.ok) {
            return JSON.stringify({ ok: false, status: orgRes.status, error: 'claude.ai /api/organizations returned HTTP ' + orgRes.status });
        }
        const orgs = await orgRes.json();
        const org = Array.isArray(orgs) ? (orgs.find(o => Array.isArray(o.capabilities) && o.capabilities.includes('chat')) || orgs[0]) : null;
        if (!org || !org.uuid) {
            return JSON.stringify({ ok: false, status: 401, error: 'No active Claude organization found on claude.ai account.' });
        }
        const convUuid = crypto.randomUUID();
        const createBody = { uuid: convUuid, name: '' };
        if (requestedModel) { createBody.model = requestedModel; }
        const createRes = await fetch(`/api/organizations/${org.uuid}/chat_conversations`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
            body: JSON.stringify(createBody)
        });
        if (!createRes.ok) {
            // Retry without explicit model slug in case subscriber tier uses default model
            const retryRes = await fetch(`/api/organizations/${org.uuid}/chat_conversations`, {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
                body: JSON.stringify({ uuid: convUuid, name: '' })
            });
            if (!retryRes.ok) {
                return JSON.stringify({ ok: false, status: retryRes.status, error: 'Failed to create claude.ai conversation (HTTP ' + retryRes.status + ').' });
            }
        }
        const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Bangkok';
        const compRes = await fetch(`/api/organizations/${org.uuid}/chat_conversations/${convUuid}/completion`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
            body: JSON.stringify({
                prompt: promptText,
                timezone: tz,
                attachments: [],
                files: []
            })
        });
        if (!compRes.ok) {
            const errTxt = await compRes.text().catch(() => '');
            return JSON.stringify({ ok: false, status: compRes.status, error: ('claude.ai completion HTTP ' + compRes.status + ': ' + errTxt.slice(0, 200)) });
        }
        const rawSSE = await compRes.text();
        fetch(`/api/organizations/${org.uuid}/chat_conversations/${convUuid}`, {
            method: 'DELETE',
            credentials: 'include'
        }).catch(() => {});
        let assembled = '';
        for (const line of rawSSE.split('\\n')) {
            if (!line.startsWith('data:')) continue;
            const payload = line.slice(5).trim();
            if (!payload || payload === '[DONE]') continue;
            try {
                const ev = JSON.parse(payload);
                if (typeof ev.completion === 'string') {
                    assembled += ev.completion;
                } else if (ev.type === 'content_block_delta' && ev.delta && typeof ev.delta.text === 'string') {
                    assembled += ev.delta.text;
                }
            } catch (_) {}
        }
        return JSON.stringify({ ok: true, status: 200, text: assembled });
        """

        var args: [String: Any] = ["promptText": combinedPrompt]
        args["requestedModel"] = claudeWebModel ?? NSNull()

        let rawResult = try await wv.callAsyncJavaScript(jsBody, arguments: args, in: nil, contentWorld: .page)
        guard let jsonStr = rawResult as? String,
              let data = jsonStr.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ClaudeWebBridge", code: 502, userInfo: [NSLocalizedDescriptionKey: "Invalid response from claude.ai web session."])
        }
        let ok = (parsed["ok"] as? Bool) ?? false
        if !ok {
            let status = (parsed["status"] as? Int) ?? 401
            let errMsg = (parsed["error"] as? String) ?? "claude.ai web session failed."
            if status == 401 || status == 403 {
                self.isLoaded = false
            }
            throw NSError(domain: "ClaudeWebBridge", code: status, userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        let text = (parsed["text"] as? String) ?? ""
        if !text.isEmpty {
            onToken(text)
        }
        return text
    }
}
