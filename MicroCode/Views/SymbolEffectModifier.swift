
import SwiftUI

struct SymbolEffectModifier: ViewModifier {
    let value: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}
