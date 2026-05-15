import SwiftUI
import AppKit

struct ContentView: View {
    @State var text = "print('Hello World')\n\n\n\n"
    var body: some View {
        VStack {
            SyntaxHighlightedCodeView(text: $text, language: "python", isScrollEnabled: true)
                .frame(height: 150)
            SyntaxHighlightedCodeView(text: $text, language: "python", isScrollEnabled: false)
                .frame(height: 150)
        }
    }
}

// Just compile it to see if it imports our local module...
