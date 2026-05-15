import SwiftUI
import WebKit

struct TerminalWebView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow access to local files if needed, but we are loading from bundle or string
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent
        
        // Load xterm.js from a hosted CDN or local resource
        // For this implementation, we inject the HTML directly
        let htmlContent = """
        <!doctype html>
        <html>
          <head>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css" />
            <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js"></script>
            <style>
              body { margin: 0; background-color: #1e1e1e; overflow: hidden; }
              #terminal { width: 100vw; height: 100vh; }
            </style>
          </head>
          <body>
            <div id="terminal"></div>
            <script>
              const term = new Terminal({
                theme: { background: '#1e1e1e' },
                cursorBlink: true,
                macOptionIsMeta: true
              });
              const fitAddon = new FitAddon.FitAddon();
              term.loadAddon(fitAddon);
              term.open(document.getElementById('terminal'));
              fitAddon.fit();
              
              // Connect WebSocket
              const ws = new WebSocket("ws://localhost:3000/ws/terminal");
              
              ws.binaryType = 'arraybuffer';
              
              ws.onopen = () => {
                term.writeln('\\r\\nCreate new terminal session...\\r\\n');
                
                // Send initial resize
                ws.send(`R:${term.cols},${term.rows}`);
              };
              
              ws.onmessage = (ev) => {
                if (typeof ev.data === 'string') {
                    term.write(ev.data);
                } else {
                    // Binary array buffer
                    term.write(new Uint8Array(ev.data));
                }
              };
              
              term.onData(data => {
                ws.send(data);
              });
              
              term.onResize(size => {
                ws.send(`R:${size.cols},${size.rows}`);
              });
              
              window.addEventListener('resize', () => {
                  fitAddon.fit();
              });
            </script>
          </body>
        </html>
        """
        
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
