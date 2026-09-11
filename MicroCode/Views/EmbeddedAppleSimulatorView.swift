//
//  EmbeddedAppleSimulatorView.swift
//  MicroCode
//

import SwiftUI
import WebKit

/// Interactive iOS Simulator preview. serve-sim supplies a real device frame
/// and forwards mouse, trackpad, and keyboard events to the simulator.
struct EmbeddedAppleSimulatorView: View {
    @ObservedObject var serveSim = ServeSimService.shared
    @ObservedObject private var runtime = DeviceRuntimeService.shared
    var canvasColor: Color = Color(nsColor: .windowBackgroundColor)
    var onConfigure: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    private var previewUnavailable: Bool {
        serveSim.connectionState == .failed
    }

    private var previewTitle: String { runtime.selectedApplePreviewTitle }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                canvasColor
                // Do not remove the WebView during a reconnect. Removing it
                // destroys serve-sim's genuine Apple device frame and is the
                // visible flash/jank users were seeing whenever the stream
                // briefly changed state.
                if let url = serveSim.previewURL {
                    ServeSimPreviewView(url: url)
                } else {
                    AppleDeviceFramePlaceholder(family: runtime.selectedApplePreviewSymbolName)
                }

                if serveSim.previewURL == nil || serveSim.connectionState != .ready {
                    VStack(spacing: 10) {
                        Image(systemName: previewUnavailable ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(previewUnavailable ? .orange : .secondary)
                        Text(previewUnavailable ? "\(previewTitle) preview is unavailable" : "Opening \(previewTitle)…")
                            .font(.system(size: 12, weight: .medium))
                        Text(serveSim.statusMessage)
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 280)
                        if previewUnavailable {
                            Button("Retry Preview") {
                                Task { await serveSim.retryLastSimulator() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .background(canvasColor)
    }
}

private struct ServeSimPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: previewBrandingCleanupScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(url, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var loadedURL: String?

        func load(_ url: URL, in webView: WKWebView) {
            // The session query changes only after a helper restart. Normal
            // status/fps updates therefore do not reload WebKit or interrupt
            // touches, while a new helper on the same localhost port always
            // gets a fresh page instead of a permanently black old one.
            guard loadedURL != url.absoluteString else { return }
            loadedURL = url.absoluteString
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        }
    }
}

/// Keep a stable portrait device silhouette while a cold simulator is booting
/// or a stream is reconnecting. The actual Apple DeviceKit frame returns as
/// soon as serve-sim is ready; this avoids a distracting empty black panel.
private struct AppleDeviceFramePlaceholder: View {
    let family: String

    var body: some View {
        GeometryReader { proxy in
            let height = min(proxy.size.height * 0.82, proxy.size.width * 2.05)
            let width = family == "ipad" ? min(proxy.size.width * 0.78, height * 0.74) : height * 0.49
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.15, style: .continuous)
                    .fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: width * 0.15, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 3))
                RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .padding(width * 0.028)
                if family == "iphone" {
                    Capsule().fill(Color.black).frame(width: width * 0.31, height: height * 0.026).offset(y: -height * 0.43)
                }
            }
            .frame(width: width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// The bundled simulator page is an implementation detail. Keep its device
/// frame and controls, but remove implementation-branding and the large blue
/// DeviceKit placeholder artwork. The native toolbar already uses Apple's SF
/// Symbol, which is sharper and visually consistent with the rest of MicroCode.
private let previewBrandingCleanupScript = """
(() => {
  const injectThemeStyles = () => {
    let style = document.getElementById('microcode-theme-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'microcode-theme-style';
      document.head.appendChild(style);
    }
    style.textContent = `
      html, body, #root, .container, main, [data-serve-sim-root] {
        background: transparent !important;
        background-color: transparent !important;
      }
    `;
    if (document.documentElement) {
      document.documentElement.style.setProperty('background', 'transparent', 'important');
      document.documentElement.style.setProperty('background-color', 'transparent', 'important');
    }
    if (document.body) {
      document.body.style.setProperty('background', 'transparent', 'important');
      document.body.style.setProperty('background-color', 'transparent', 'important');
    }
  };

  const cleanElement = (element) => {
    if (!(element instanceof Element) || element.children.length !== 0) return;
    const label = (element.textContent || '').trim().toLowerCase();
    if (label === 'serve-sim') {
      element.style.setProperty('display', 'none', 'important');
      return;
    }
    if (label === 'live') {
      element.style.setProperty('display', 'none', 'important');
      const parent = element.parentElement;
      if (parent) {
        parent.querySelectorAll('*').forEach((sibling) => {
          if ((sibling.textContent || '').trim() === '•') {
            sibling.style.setProperty('display', 'none', 'important');
          }
        });
      }
    }
  };
  const cleanTree = (root) => {
    injectThemeStyles();
    cleanElement(root);
    if (root instanceof Element) {
      root.querySelectorAll('*').forEach(cleanElement);
      root.querySelectorAll('[data-microcode-device-art]').forEach((image) => image.remove());
    }
  };
  cleanTree(document.documentElement);
  new MutationObserver((records) => {
    injectThemeStyles();
    for (const record of records) {
      if (record.type === 'characterData') cleanElement(record.target.parentElement);
      record.addedNodes.forEach((node) => {
        if (node instanceof Element) {
          cleanTree(node);
        }
      });
    }
  }).observe(document.documentElement, { childList: true, characterData: true, subtree: true });
})();
"""
