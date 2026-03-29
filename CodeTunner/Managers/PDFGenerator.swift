import Foundation
import WebKit
import AppKit

class PDFGenerator: NSObject {
    static let shared = PDFGenerator()
    
    // Hidden WebView for rendering
    private var webView: WKWebView?
    
    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1123), configuration: config) // A4 Aspect Ratio roughly
    }
    
    func generatePDF(htmlContent: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let webView = self.webView else {
            completion(.failure(NSError(domain: "PDFGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView not initialized"])))
            return
        }
        
        // Load HTML
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        // Wait for load to complete (Simulated with logic hook or delegate)
        // For simplicity in this context, we'll check navigation delegate
        // But to make it robust, we create a temporary delegate wrapper
        let delegate = PDFGenerationDelegate { [weak self] error in
            if let error = error {
                completion(.failure(error))
            } else {
                // PDF config
                let pdfConfig = WKPDFConfiguration()
                pdfConfig.rect = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4 Size in points
                
                webView.createPDF(configuration: pdfConfig) { result in
                    switch result {
                    case .success(let data):
                        completion(.success(data))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }
        
        webView.navigationDelegate = delegate
        // Attach delegate to stay alive
        objc_setAssociatedObject(webView, "PDFDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

private class PDFGenerationDelegate: NSObject, WKNavigationDelegate {
    let completion: (Error?) -> Void
    
    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion(nil)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(error)
    }
}
