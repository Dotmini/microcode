//
//  VertexAISearchWebBridge.swift
//  MicroCode
//
//  Created and Designed by Dotmini Software
//  Founder & CEO: Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//
//  Description:
//  Native WebKit & Network Stream Bridge for Thai AI Gemini Enterprise (AiPASS.TH)
//  hosted on Google Cloud Vertex AI Search / Google Agentspace:
//  https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b
//

import Foundation
import WebKit
import AppKit

@MainActor
public final class VertexAISearchWebBridge: NSObject, WKNavigationDelegate, WKUIDelegate {
    public static let shared = VertexAISearchWebBridge()

    /// Official Thai AI Gemini Enterprise (AiPASS.TH) Vertex AI Search Config ID
    nonisolated public static let defaultConfigID = "1b5ab175-0783-4463-8a33-b61845396a2b"
    nonisolated public static let defaultRegion = "us"
    nonisolated public static let defaultHomeURLString = "https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b"
    nonisolated public static let defaultSessionURLString = "https://vertexaisearch.cloud.google/us/home/cid/1b5ab175-0783-4463-8a33-b61845396a2b/r/session/2836962715286832461?csesidx=306441087"

    private var webView: WKWebView?
    private var isPageLoaded: Bool = false
    private var currentLoadedCID: String = ""
    private var isExecutingRequest: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - URL & Session Configuration Parsing

    public struct EnterpriseSessionConfig {
        public var region: String
        public var cid: String
        public var csesidx: String?
        public var sessionID: String?
        public var fullURLString: String
        public var cookieHeader: String?

        public var homeURL: URL {
            var base = "https://vertexaisearch.cloud.google/\(region)/home/cid/\(cid)"
            if let idx = csesidx, !idx.isEmpty {
                base += "?csesidx=\(idx)"
            }
            return URL(string: base) ?? URL(string: VertexAISearchWebBridge.defaultHomeURLString)!
        }

        public var activeURL: URL {
            if let u = URL(string: fullURLString), u.host?.contains("vertexaisearch.cloud.google") == true {
                return u
            }
            return homeURL
        }
    }

    nonisolated public static func parseConfig(from rawInput: String?) -> EnterpriseSessionConfig {
        let savedURL = UserDefaults.standard.string(forKey: "thai_gemini_enterprise_url") ?? ""
        let savedCID = UserDefaults.standard.string(forKey: "thai_gemini_enterprise_cid") ?? defaultConfigID
        let savedRegion = UserDefaults.standard.string(forKey: "thai_gemini_enterprise_region") ?? defaultRegion
        let savedCsesidx = UserDefaults.standard.string(forKey: "thai_gemini_enterprise_csesidx")

        let source = (rawInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty ? savedURL : rawInput!.trimmingCharacters(in: .whitespacesAndNewlines)

        var region = savedRegion.isEmpty ? defaultRegion : savedRegion
        var cid = savedCID.isEmpty ? defaultConfigID : savedCID
        var csesidx: String? = (savedCsesidx?.isEmpty == false) ? savedCsesidx : nil
        var sessionID: String? = nil
        var extractedURL: String? = nil
        var extractedCookie: String? = nil

        if !source.isEmpty {
            // 1. Extract URL if present in raw input or cURL command
            if let urlRegex = try? NSRegularExpression(pattern: #"https://vertexaisearch\.cloud\.google/[^\s'"]+"#),
               let match = urlRegex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let range = Range(match.range, in: source) {
                extractedURL = String(source[range])
            }

            let urlCandidate = extractedURL ?? source
            if let regionRegex = try? NSRegularExpression(pattern: #"vertexaisearch\.cloud\.google/([a-z0-9-]+)/home/cid/([a-fA-F0-9-]{20,64})"#),
               let match = regionRegex.firstMatch(in: urlCandidate, range: NSRange(urlCandidate.startIndex..., in: urlCandidate)) {
                if match.numberOfRanges > 1, let r1 = Range(match.range(at: 1), in: urlCandidate) {
                    region = String(urlCandidate[r1])
                }
                if match.numberOfRanges > 2, let r2 = Range(match.range(at: 2), in: urlCandidate) {
                    cid = String(urlCandidate[r2])
                }
            }
            if let sessRegex = try? NSRegularExpression(pattern: #"/r/session/([0-9A-Za-z_-]+)"#),
               let match = sessRegex.firstMatch(in: urlCandidate, range: NSRange(urlCandidate.startIndex..., in: urlCandidate)),
               match.numberOfRanges > 1,
               let r1 = Range(match.range(at: 1), in: urlCandidate) {
                sessionID = String(urlCandidate[r1])
            }
            if let idxRegex = try? NSRegularExpression(pattern: #"[?&]csesidx=([0-9A-Za-z_-]+)"#),
               let match = idxRegex.firstMatch(in: urlCandidate, range: NSRange(urlCandidate.startIndex..., in: urlCandidate)),
               match.numberOfRanges > 1,
               let r1 = Range(match.range(at: 1), in: urlCandidate) {
                csesidx = String(urlCandidate[r1])
            }

            // 2. Extract Cookie header if input is a cURL command or Cookie string
            if source.contains("curl ") || source.contains("-H ") || source.contains("-b ") {
                let patterns = [
                    #"(?i)-H\s+['"]cookie:\s*([^'"]+)['"]"#,
                    #"-b\s+['"]([^'"]+)['"]"#
                ]
                for pat in patterns {
                    if let regex = try? NSRegularExpression(pattern: pat),
                       let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                       match.numberOfRanges > 1,
                       let r = Range(match.range(at: 1), in: source) {
                        extractedCookie = String(source[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            } else if source.contains("SID=") || source.contains("__Secure-1PSID=") || source.contains("SAPISID=") || source.contains("OSID=") {
                var cleanCookie = source
                if let pipeIdx = cleanCookie.range(of: "||COOKIE:") {
                    cleanCookie = String(cleanCookie[pipeIdx.upperBound...])
                }
                if cleanCookie.lowercased().hasPrefix("cookie:") {
                    cleanCookie = String(cleanCookie.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                extractedCookie = cleanCookie
            }
        }

        let resolvedFullURL: String = {
            if let ext = extractedURL, !ext.isEmpty {
                return ext
            }
            if !savedURL.isEmpty && savedURL.contains("vertexaisearch.cloud.google") {
                return savedURL
            }
            var built = "https://vertexaisearch.cloud.google/\(region)/home/cid/\(cid)"
            if let s = sessionID, !s.isEmpty {
                built += "/r/session/\(s)"
            }
            if let idx = csesidx, !idx.isEmpty {
                built += "?csesidx=\(idx)"
            }
            return built
        }()

        return EnterpriseSessionConfig(
            region: region,
            cid: cid,
            csesidx: csesidx,
            sessionID: sessionID,
            fullURLString: resolvedFullURL,
            cookieHeader: extractedCookie
        )
    }

    nonisolated public static func saveConfig(_ config: EnterpriseSessionConfig) {
        UserDefaults.standard.set(config.region, forKey: "thai_gemini_enterprise_region")
        UserDefaults.standard.set(config.cid, forKey: "thai_gemini_enterprise_cid")
        if let idx = config.csesidx, !idx.isEmpty {
            UserDefaults.standard.set(idx, forKey: "thai_gemini_enterprise_csesidx")
        }
        UserDefaults.standard.set(config.fullURLString, forKey: "thai_gemini_enterprise_url")
    }

    // MARK: - WebKit Initialization & Bridge Script

    private static let bridgeUserScript: String = """
    (() => {
        if (window.__mcVertexBridgeInstalled) return;
        window.__mcVertexBridgeInstalled = true;

        // 1. Force all Shadow DOM roots to open mode so we can inspect/drive ucs-* / md-* web components
        try {
            const origAttachShadow = Element.prototype.attachShadow;
            Element.prototype.attachShadow = function(init) {
                const root = origAttachShadow.call(this, Object.assign({}, init || {}, { mode: 'open' }));
                this.__mcShadowRoot = root;
                return root;
            };
        } catch (e) {}

        // 2. Network stream state for Vertex AI Search / StreamAssist / batchexecute
        window.__mcNetActiveRequests = 0;
        window.__mcLastNetActivityAt = 0;
        window.__mcNetStreamBuffer = '';
        window.__mcSubmitTimestamp = 0;

        function extractStringsFromStreamPayload(rawChunk) {
            if (!rawChunk || typeof rawChunk !== 'string') return;
            window.__mcLastNetActivityAt = Date.now();
        }

        try {
            const origFetch = window.fetch;
            window.fetch = async function(...args) {
                const urlStr = String((args[0] && args[0].url) ? args[0].url : args[0] || '');
                const isAssistCall = urlStr.includes('StreamAssist') ||
                                     urlStr.includes('streamAssist') ||
                                     urlStr.includes('batchexecute') ||
                                     urlStr.includes('Assist') ||
                                     urlStr.includes('conversation') ||
                                     urlStr.includes('session');
                if (isAssistCall && window.__mcSubmitTimestamp > 0) {
                    window.__mcNetActiveRequests += 1;
                    window.__mcLastNetActivityAt = Date.now();
                }
                try {
                    const response = await origFetch.apply(this, args);
                    if (isAssistCall && window.__mcSubmitTimestamp > 0) {
                        window.__mcLastNetActivityAt = Date.now();
                        try {
                            const cloned = response.clone();
                            if (cloned.body && cloned.body.getReader) {
                                (async () => {
                                    const reader = cloned.body.getReader();
                                    const decoder = new TextDecoder();
                                    try {
                                        while (true) {
                                            const { done, value } = await reader.read();
                                            if (done) break;
                                            window.__mcLastNetActivityAt = Date.now();
                                            if (value) {
                                                extractStringsFromStreamPayload(decoder.decode(value, { stream: true }));
                                            }
                                        }
                                    } catch (e) {} finally {
                                        window.__mcNetActiveRequests = Math.max(0, window.__mcNetActiveRequests - 1);
                                        window.__mcLastNetActivityAt = Date.now();
                                    }
                                })();
                            } else {
                                window.__mcNetActiveRequests = Math.max(0, window.__mcNetActiveRequests - 1);
                            }
                        } catch (e) {
                            window.__mcNetActiveRequests = Math.max(0, window.__mcNetActiveRequests - 1);
                        }
                    }
                    return response;
                } catch (err) {
                    if (isAssistCall && window.__mcSubmitTimestamp > 0) {
                        window.__mcNetActiveRequests = Math.max(0, window.__mcNetActiveRequests - 1);
                    }
                    throw err;
                }
            };
        } catch (e) {}

        try {
            const origOpen = XMLHttpRequest.prototype.open;
            const origSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url, ...rest) {
                this.__mcUrl = String(url || '');
                return origOpen.call(this, method, url, ...rest);
            };
            XMLHttpRequest.prototype.send = function(body) {
                const urlStr = this.__mcUrl || '';
                const isAssistCall = urlStr.includes('StreamAssist') ||
                                     urlStr.includes('streamAssist') ||
                                     urlStr.includes('batchexecute') ||
                                     urlStr.includes('Assist') ||
                                     urlStr.includes('session');
                if (isAssistCall && window.__mcSubmitTimestamp > 0) {
                    window.__mcNetActiveRequests += 1;
                    window.__mcLastNetActivityAt = Date.now();
                    this.addEventListener('progress', () => {
                        window.__mcLastNetActivityAt = Date.now();
                    });
                    const onDone = () => {
                        window.__mcNetActiveRequests = Math.max(0, window.__mcNetActiveRequests - 1);
                        window.__mcLastNetActivityAt = Date.now();
                    };
                    this.addEventListener('loadend', onDone, { once: true });
                    this.addEventListener('error', onDone, { once: true });
                    this.addEventListener('abort', onDone, { once: true });
                }
                return origSend.call(this, body);
            };
        } catch (e) {}

        // 3. Deep Shadow-DOM Query Helpers
        window.__mcQueryAllDeep = function(selector, rootNode) {
            const root = rootNode || document.documentElement;
            const results = [];
            if (!root) return results;
            const visited = new Set();
            function walk(node) {
                if (!node || visited.has(node)) return;
                visited.add(node);
                if (node.querySelectorAll) {
                    try {
                        const matched = node.querySelectorAll(selector);
                        for (let i = 0; i < matched.length; i++) {
                            results.push(matched[i]);
                        }
                    } catch (e) {}
                }
                const children = node.children || node.childNodes || [];
                for (let i = 0; i < children.length; i++) {
                    const child = children[i];
                    if (!child) continue;
                    const sr = child.shadowRoot || child.__mcShadowRoot;
                    if (sr) walk(sr);
                    walk(child);
                }
            }
            const rootSr = root.shadowRoot || root.__mcShadowRoot;
            if (rootSr) walk(rootSr);
            walk(root);
            return results;
        };

        window.__mcFindComposer = function() {
            const candidates = window.__mcQueryAllDeep('textarea, [contenteditable="true"], [contenteditable="plaintext-only"], [role="textbox"]');
            let best = null;
            let bestScore = -1;
            for (const el of candidates) {
                if (el.disabled || el.readOnly) continue;
                const rect = el.getBoundingClientRect();
                if (!rect || rect.width < 120 || rect.height < 14) continue;
                if (rect.left < 200 && rect.width < 260) continue; // Ignore left sidebar search inputs
                const style = window.getComputedStyle(el);
                if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity || '1') < 0.1) continue;
                // Prefer the main chat composer in the center/bottom of the viewport
                const score = rect.width + (rect.bottom > window.innerHeight * 0.35 ? 500 : 0);
                if (score > bestScore) {
                    bestScore = score;
                    best = el;
                }
            }
            return best;
        };

        // 4. Clean Markdown Extractor for Assistant Message Containers
        window.__mcNodeToMarkdown = function(node) {
            if (!node) return '';
            if (node.nodeType === Node.TEXT_NODE) {
                return node.nodeValue || '';
            }
            if (node.nodeType !== Node.ELEMENT_NODE) {
                return '';
            }
            const tag = (node.tagName || '').toLowerCase();
            if (tag === 'script' || tag === 'style' || tag === 'svg' || tag === 'mat-icon' || tag === 'md-icon' || tag === 'button') {
                return '';
            }
            const role = (node.getAttribute && node.getAttribute('role')) || '';
            if (role === 'button' || role === 'toolbar' || role === 'navigation') {
                return '';
            }
            const cls = String(node.className || '').toLowerCase();
            if (cls.includes('suggestion') || cls.includes('followup') || cls.includes('follow-up') ||
                cls.includes('feedback') || cls.includes('action-bar') || cls.includes('toolbar') ||
                cls.includes('citation') || cls.includes('disclaimer') || cls.includes('material-icons') ||
                cls.includes('google-symbols')) {
                return '';
            }

            // Handle <pre> / code block containers
            if (tag === 'pre') {
                const codeEl = node.querySelector ? (node.querySelector('code') || node) : node;
                const codeText = (codeEl.innerText || codeEl.textContent || '').replace(/\\n+$/, '');
                let lang = '';
                const prev = node.previousElementSibling;
                if (prev) {
                    const headerTxt = (prev.innerText || prev.textContent || '').trim().split(/\\s+/)[0] || '';
                    if (/^[A-Za-z0-9+#_-]{1,18}$/.test(headerTxt) && headerTxt.toLowerCase() !== 'copy') {
                        lang = headerTxt.toLowerCase();
                    }
                }
                return '\\n```' + lang + '\\n' + codeText + '\\n```\\n';
            }

            const sr = node.shadowRoot || node.__mcShadowRoot;
            const childNodes = sr ? sr.childNodes : node.childNodes;
            let acc = '';
            for (let i = 0; i < childNodes.length; i++) {
                acc += window.__mcNodeToMarkdown(childNodes[i]);
            }

            if (tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article' || tag.includes('-markdown') || tag.includes('-message')) {
                return acc + '\\n';
            }
            if (tag === 'li') {
                return '- ' + acc.trim() + '\\n';
            }
            if (tag === 'br') {
                return '\\n';
            }
            if (tag === 'code' && (!node.parentElement || node.parentElement.tagName.toLowerCase() !== 'pre')) {
                return '`' + acc + '`';
            }
            return acc;
        };

        window.__mcGetMessageBlocks = function() {
            const specificSelectors = [
                'ucs-markdown',
                'markdown-renderer',
                'message-content',
                '[data-message-author-role="model"]',
                '[data-message-author-role="assistant"]',
                '.model-response-text',
                '.response-content',
                '.assistant-message',
                '.markdown-content',
                '.markdown'
            ].join(', ');

            let blocks = window.__mcQueryAllDeep(specificSelectors).filter(el => {
                const r = el.getBoundingClientRect();
                return r && r.width > 180 && r.height > 10 && r.left >= 200;
            });

            // Filter out nested duplicates (keep outermost matched markdown container)
            blocks = blocks.filter(el => !blocks.some(other => other !== el && other.contains && other.contains(el)));

            if (blocks.length > 0) {
                return blocks.map(el => window.__mcNodeToMarkdown(el).replace(/\\n{3,}/g, '\\n\\n').trim()).filter(Boolean);
            }

            // Fallback: inspect main chat column blocks (`rect.left >= 220`, above composer)
            const composer = window.__mcFindComposer();
            const composerTop = composer ? composer.getBoundingClientRect().top : (window.innerHeight - 140);
            const generic = window.__mcQueryAllDeep('article, [role="article"], [role="listitem"], .message, .turn, .chat-turn').filter(el => {
                const r = el.getBoundingClientRect();
                return r && r.width > 220 && r.height > 16 && r.left >= 200 && r.bottom <= composerTop + 20;
            });
            const outerGeneric = generic.filter(el => !generic.some(other => other !== el && other.contains && other.contains(el)));
            return outerGeneric.map(el => window.__mcNodeToMarkdown(el).replace(/\\n{3,}/g, '\\n\\n').trim()).filter(Boolean);
        };

        window.__mcSubmitPrompt = function(promptText) {
            const composer = window.__mcFindComposer();
            if (!composer) {
                return JSON.stringify({ ok: false, error: 'composer_not_found', url: location.href });
            }
            const existingBlocks = window.__mcGetMessageBlocks();
            window.__mcBaselineCount = existingBlocks.length;
            window.__mcBaselineLastText = existingBlocks.length > 0 ? existingBlocks[existingBlocks.length - 1] : '';
            window.__mcPromptPrefix = String(promptText || '').trim().slice(0, 80);
            window.__mcSubmitTimestamp = Date.now();
            window.__mcLastNetActivityAt = Date.now();
            window.__mcNetActiveRequests = 0;

            composer.focus();
            const tag = (composer.tagName || '').toLowerCase();
            if (tag === 'textarea' || tag === 'input') {
                const proto = tag === 'textarea' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
                const desc = Object.getOwnPropertyDescriptor(proto, 'value');
                if (desc && desc.set) {
                    desc.set.call(composer, promptText);
                } else {
                    composer.value = promptText;
                }
                composer.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, data: promptText, inputType: 'insertText' }));
                composer.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
            } else {
                try {
                    const sel = window.getSelection();
                    const range = document.createRange();
                    range.selectNodeContents(composer);
                    sel.removeAllRanges();
                    sel.addRange(range);
                    document.execCommand('insertText', false, promptText);
                } catch (e) {}
                const currentTxt = (composer.innerText || composer.textContent || '').trim();
                if (!currentTxt) {
                    composer.textContent = promptText;
                    composer.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, composed: true, data: promptText, inputType: 'insertText' }));
                    composer.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, data: promptText, inputType: 'insertText' }));
                }
            }

            setTimeout(() => {
                // Find Send button near the composer or dispatch Enter key
                const composerRect = composer.getBoundingClientRect();
                const buttons = window.__mcQueryAllDeep('button, [role="button"]');
                let sendBtn = null;
                for (const btn of buttons) {
                    if (btn.disabled || btn.getAttribute('aria-disabled') === 'true') continue;
                    const r = btn.getBoundingClientRect();
                    if (!r || r.width < 16 || r.height < 16) continue;
                    if (Math.abs(r.bottom - composerRect.bottom) > 140 || r.left < composerRect.left - 40) continue;
                    const label = ((btn.getAttribute('aria-label') || '') + ' ' + (btn.getAttribute('title') || '') + ' ' + (btn.innerText || '')).toLowerCase();
                    if (label.includes('send') || label.includes('submit') || label.includes('ส่ง') || label.includes('arrow_upward')) {
                        sendBtn = btn;
                        break;
                    }
                }
                if (sendBtn) {
                    sendBtn.click();
                } else {
                    const enterDown = new KeyboardEvent('keydown', {
                        key: 'Enter',
                        code: 'Enter',
                        keyCode: 13,
                        which: 13,
                        bubbles: true,
                        composed: true,
                        cancelable: true
                    });
                    composer.dispatchEvent(enterDown);
                    const enterUp = new KeyboardEvent('keyup', {
                        key: 'Enter',
                        code: 'Enter',
                        keyCode: 13,
                        which: 13,
                        bubbles: true,
                        composed: true
                    });
                    composer.dispatchEvent(enterUp);
                }
            }, 70);

            return JSON.stringify({ ok: true, baselineCount: window.__mcBaselineCount });
        };

        window.__mcPollAssistantReply = function() {
            const blocks = window.__mcGetMessageBlocks();
            const baseCount = window.__mcBaselineCount || 0;
            const baseLast = window.__mcBaselineLastText || '';
            const promptPrefix = window.__mcPromptPrefix || '';

            let candidateText = '';
            if (blocks.length > baseCount) {
                for (let i = blocks.length - 1; i >= baseCount; i--) {
                    const txt = (blocks[i] || '').trim();
                    if (!txt) continue;
                    if (promptPrefix && txt.startsWith(promptPrefix)) continue;
                    if (txt.includes('<microcode_ide_context>') || txt.includes('<current_request>')) continue;
                    candidateText = txt;
                    break;
                }
            } else if (blocks.length > 0) {
                const last = (blocks[blocks.length - 1] || '').trim();
                if (last && last !== baseLast && (!promptPrefix || !last.startsWith(promptPrefix)) && !last.includes('<microcode_ide_context>')) {
                    candidateText = last;
                }
            }

            // Strip trailing disclaimer if captured
            candidateText = candidateText
                .replace(/Generative AI may display inaccurate information[\\s\\S]*$/i, '')
                .trim();

            const netActive = window.__mcNetActiveRequests || 0;
            const msSinceNet = Date.now() - (window.__mcLastNetActivityAt || window.__mcSubmitTimestamp || Date.now());
            return JSON.stringify({
                text: candidateText,
                netActive: netActive,
                msSinceNet: msSinceNet,
                blockCount: blocks.length,
                url: location.href
            });
        };
    })();
    """

    private func ensureWebView(config: EnterpriseSessionConfig) async throws -> WKWebView {
        if let existing = self.webView {
            if let cookieHeader = config.cookieHeader, !cookieHeader.isEmpty {
                await syncCookieHeaderToWebKitStore(cookieHeader: cookieHeader)
            }
            let currentHost = existing.url?.host ?? ""
            if !currentHost.contains("vertexaisearch.cloud.google") || currentLoadedCID != config.cid {
                currentLoadedCID = config.cid
                isPageLoaded = false
                existing.load(URLRequest(url: config.activeURL))
            }
            return existing
        }

        let wkConfig = WKWebViewConfiguration()
        wkConfig.websiteDataStore = WKWebsiteDataStore.default()
        wkConfig.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15 MicroCode/2.0"

        let script = WKUserScript(
            source: Self.bridgeUserScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        wkConfig.userContentController.addUserScript(script)

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: wkConfig)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        wv.navigationDelegate = self
        wv.uiDelegate = self
        self.webView = wv

        if let cookieHeader = config.cookieHeader, !cookieHeader.isEmpty {
            await syncCookieHeaderToWebKitStore(cookieHeader: cookieHeader)
        }

        currentLoadedCID = config.cid
        isPageLoaded = false
        wv.load(URLRequest(url: config.activeURL))
        return wv
    }

    public func syncCookieHeaderToWebKitStore(cookieHeader: String) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let pairs = cookieHeader.components(separatedBy: ";")
        let domains = [".google.com", "vertexaisearch.cloud.google", ".cloud.google"]
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            for domain in domains {
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: "/",
                    .secure: "TRUE"
                ]
                if name.hasPrefix("__Host-") {
                    props[.domain] = "vertexaisearch.cloud.google"
                }
                if let cookie = HTTPCookie(properties: props) {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        store.setCookie(cookie) {
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        if let urlStr = webView.url?.absoluteString,
           urlStr.contains("vertexaisearch.cloud.google"),
           urlStr.contains("/cid/") {
            let parsed = Self.parseConfig(from: urlStr)
            Self.saveConfig(parsed)
        }
    }

    // MARK: - Stream Prompt Execution

    public func streamPrompt(
        prompt: String,
        model: String,
        rawTokenOrConfig: String,
        hasTools: Bool,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let config = Self.parseConfig(from: rawTokenOrConfig)
        Self.saveConfig(config)

        let wv = try await ensureWebView(config: config)

        // 1. Wait up to 18s for Vertex AI Search composer to mount in DOM
        var composerReady = false
        for _ in 0..<75 {
            if Task.isCancelled { throw CancellationError() }
            let currentURL = wv.url?.absoluteString ?? ""
            if currentURL.contains("accounts.google.com") || currentURL.contains("/signin") {
                throw NSError(
                    domain: "ThaiGeminiEnterprise",
                    code: 401,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Thai AI Gemini Enterprise (vertexaisearch.cloud.google) requires signing in. Click '1-Click Sign In' on Thai AI Gemini Enterprise in Settings → AI Provider → Subscription."
                    ]
                )
            }
            if let res = try? await wv.evaluateJavaScript("Boolean(window.__mcFindComposer && window.__mcFindComposer())") as? Bool,
               res == true {
                composerReady = true
                break
            }
            try await Task.sleep(nanoseconds: 240_000_000)
        }

        if !composerReady {
            let currentURL = wv.url?.absoluteString ?? config.activeURL.absoluteString
            throw NSError(
                domain: "ThaiGeminiEnterprise",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey: "Thai AI Gemini Enterprise workspace composer not ready at \(currentURL). Please sign in via Settings → AI Provider → Subscription → Thai AI Gemini Enterprise (1-Click Sign In)."
                ]
            )
        }

        // 2. Submit prompt into the live Vertex AI Search composer
        let encodedPromptData = try JSONSerialization.data(withJSONObject: [prompt])
        let encodedPromptArray = String(data: encodedPromptData, encoding: .utf8) ?? "[\"\"]"
        let submitJS = "window.__mcSubmitPrompt(\(encodedPromptArray)[0])"
        guard let submitRaw = try await wv.evaluateJavaScript(submitJS) as? String,
              let submitData = submitRaw.data(using: .utf8),
              let submitJson = try? JSONSerialization.jsonObject(with: submitData) as? [String: Any],
              (submitJson["ok"] as? Bool) == true else {
            throw NSError(
                domain: "ThaiGeminiEnterprise",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to submit prompt into Thai AI Gemini Enterprise composer."]
            )
        }

        // 3. Poll streaming response and emit incremental tokens
        var emittedLength = 0
        var fullReply = ""
        var visibleHoldBuffer = ""
        var lastChangeTime = Date()
        let startTime = Date()
        let maxDuration: TimeInterval = 180

        while Date().timeIntervalSince(startTime) < maxDuration {
            if Task.isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 140_000_000)

            guard let pollRaw = try? await wv.evaluateJavaScript("window.__mcPollAssistantReply()") as? String,
                  let pollData = pollRaw.data(using: .utf8),
                  let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] else {
                continue
            }

            let latestText = (pollJson["text"] as? String) ?? ""
            let netActive = (pollJson["netActive"] as? Int) ?? 0
            let msSinceNet = (pollJson["msSinceNet"] as? Int) ?? 0

            if latestText.count > fullReply.count && latestText.hasPrefix(fullReply) {
                let newDelta = String(latestText.dropFirst(emittedLength))
                emittedLength = latestText.count
                fullReply = latestText
                lastChangeTime = Date()
                emitFilteredDelta(newDelta, hasTools: hasTools, visibleHoldBuffer: &visibleHoldBuffer, onToken: onToken)
            } else if latestText != fullReply && !latestText.isEmpty {
                if latestText.count > emittedLength {
                    let newDelta = String(latestText.dropFirst(emittedLength))
                    emittedLength = latestText.count
                    emitFilteredDelta(newDelta, hasTools: hasTools, visibleHoldBuffer: &visibleHoldBuffer, onToken: onToken)
                }
                fullReply = latestText
                lastChangeTime = Date()
            }

            // Early exit in Agent Mode as soon as a complete `</tool_call>` tag is received
            if hasTools && (fullReply.contains("</tool_call>") || fullReply.contains("</function_call>")) {
                break
            }

            let idleSeconds = Date().timeIntervalSince(lastChangeTime)
            if !fullReply.isEmpty && netActive == 0 && msSinceNet > 950 && idleSeconds > 1.1 {
                break
            }
            if !fullReply.isEmpty && idleSeconds > 3.2 {
                break
            }
        }

        if hasTools && !visibleHoldBuffer.isEmpty {
            let cleanedRemainder = AIStructuredTurnCodec.stripToolCallArtifacts(visibleHoldBuffer)
            if !cleanedRemainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onToken(cleanedRemainder)
            }
            visibleHoldBuffer = ""
        }

        if fullReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "ThaiGeminiEnterprise",
                code: 504,
                userInfo: [NSLocalizedDescriptionKey: "Thai AI Gemini Enterprise (\(model)) returned an empty response or timed out."]
            )
        }

        return fullReply
    }

    private func emitFilteredDelta(
        _ delta: String,
        hasTools: Bool,
        visibleHoldBuffer: inout String,
        onToken: @escaping (String) -> Void
    ) {
        guard !delta.isEmpty else { return }
        if !hasTools {
            onToken(delta)
            return
        }
        visibleHoldBuffer += delta
        let toolOpenTags = [
            "<tool_call", "<function_call", "<function_calls",
            "<invoke", "<parameter", "```tool_call", "```function_call", "[Tool Call:"
        ]
        if let tcRange = toolOpenTags.compactMap({ visibleHoldBuffer.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let before = String(visibleHoldBuffer[..<tcRange.lowerBound])
            if !before.isEmpty {
                onToken(before)
            }
            visibleHoldBuffer = String(visibleHoldBuffer[tcRange.lowerBound...])
        } else if !visibleHoldBuffer.contains("<") && !visibleHoldBuffer.contains("`") && !visibleHoldBuffer.contains("[") {
            onToken(visibleHoldBuffer)
            visibleHoldBuffer = ""
        }
    }
}
