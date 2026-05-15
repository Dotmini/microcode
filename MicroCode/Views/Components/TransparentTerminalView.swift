import SwiftUI
import WebKit

struct TransparentTerminalView: NSViewRepresentable {
    let url: URL
    let theme: AppTheme
    let fontSize: Int
    let fontFamily: String
    
    // Binding to execute scripts into the WebView
    @Binding var externalCommand: String?
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent NSView
        // Also needed for newer macOS to respect transparency
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        
        // Load xterm.js html
        let htmlContent = generateHTML()
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        context.coordinator.webView = webView
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Handle theme changes via JS injection if needed
        // For now, simpler to just reload if major config changes, or inject JS
        
        if let cmd = externalCommand {
            // Execute command in terminal via xterm.js
            let js = "socket.send('\(cmd)\\n');"
            webView.evaluateJavaScript(js)
            
            DispatchQueue.main.async {
                self.externalCommand = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: TransparentTerminalView
        weak var webView: WKWebView?
        
        init(_ parent: TransparentTerminalView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Handle callbacks from JS if needed
        }
    }
    
    private func generateHTML() -> String {
        // Theme Colors
        let fg = theme.editorText.toHex
        let bg = theme.editorBackground.toHex
        let cursor = theme.keywordColor.toHex
        
        // Background should be transparent for the "Transparent" effect, or semi-transparent
        
        return """
        <!doctype html>
        <html>
          <head>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
            <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/xterm-addon-webgl@0.16.0/lib/xterm-addon-webgl.js"></script>
            <style>
              body { margin: 0; background-color: transparent; overflow: hidden; height: 100vh; }
              #terminal { width: 100vw; height: 100vh; }
              .xterm-viewport { background-color: transparent !important; }
            </style>
          </head>
          <body>
            <div id="terminal"></div>
            <script>
              // XTerm Setup
              const term = new Terminal({
                fontFamily: '\(fontFamily), menlo, monospace',
                fontSize: \(fontSize),
                cursorBlink: true,
                macOptionIsMeta: true,
                allowTransparency: true,
                theme: {
                  background: '#00000000', // Fully transparent
                  foreground: '\(fg)',
                  cursor: '\(cursor)',
                  selectionBackground: 'rgba(255, 255, 255, 0.3)'
                }
              });
              
              const fitAddon = new FitAddon.FitAddon();
              term.loadAddon(fitAddon);
              
              // Enable WebGL for performance if supported
              try {
                  const webgl = new WebglAddon.WebglAddon();
                  webgl.onContextLoss(e => {
                    webgl.dispose();
                  });
                  term.loadAddon(webgl);
              } catch (e) {
                  console.warn("WebGL not supported, falling back to canvas");
              }
              
              term.open(document.getElementById('terminal'));
              fitAddon.fit();
              
              // WebSocket Connection optimization
              // We use the passed URL
              const ws = new WebSocket("\(url.absoluteString)");
              window.socket = ws; // Expose for external access
              
              ws.binaryType = 'arraybuffer';
              
              ws.onopen = () => {
                // Send initial size
                ws.send(`R:${term.cols},${term.rows}`);
                term.focus();
              };
              
              ws.onmessage = (ev) => {
                if (typeof ev.data === 'string') {
                    term.write(ev.data);
                } else {
                    term.write(new Uint8Array(ev.data));
                }
              };
              
              ws.onclose = () => {
                  term.write('\\r\\n\\x1b[31m[Connection Closed]\\x1b[0m');
              };
              
              ws.onerror = (e) => {
                  term.write('\\r\\n\\x1b[31m[Connection Error]\\x1b[0m');
              };
              
              term.onData(data => {
                if (ws.readyState === WebSocket.OPEN) {
                    ws.send(data);
                }
              });
              
              term.onResize(size => {
                if (ws.readyState === WebSocket.OPEN) {
                    ws.send(`R:${size.cols},${size.rows}`);
                }
              });
              
              window.addEventListener('resize', () => {
                  fitAddon.fit();
              });
            </script>
          </body>
        </html>
        """
    }
}

// Private helper to avoid scope issues
extension NSColor {
    fileprivate var toHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
