import Foundation

/// Tracks the relationship between an editor's NSTextView buffer and its SwiftUI `@Binding var text`.
///
/// Keystrokes reach the binding only after a debounce, so for a short window the binding is behind the
/// buffer. SwiftUI may call `updateNSView` at any time in that window (any AppState change re-renders the
/// representable), handing back the *old* binding value.
struct EditorBindingSyncState {
    private(set) var lastPushedBindingText: String?
    private(set) var hasPendingLocalEdits = false

    /// The user changed the buffer; the binding has not been told yet.
    mutating func noteLocalEdit() {
        hasPendingLocalEdits = true
    }

    /// The buffer's text was written to the binding.
    mutating func notePushedToBinding(_ text: String) {
        lastPushedBindingText = text
        hasPendingLocalEdits = false
    }

    /// A binding value was written into the buffer (initial load, file switch, AI edit, collaboration).
    mutating func noteAppliedFromBinding(_ text: String) {
        lastPushedBindingText = text
        hasPendingLocalEdits = false
    }

    /// Whether `applyContent` should replace the buffer with the binding value SwiftUI just handed over.
    ///
    /// While keystrokes are still waiting for the debounced sync, an incoming value equal to what the binding
    /// last held is just a stale echo of the past, not an edit: applying it would delete what the user just
    /// typed (and move the caret), then re-insert it when the debounce fires. Any other value is a genuine
    /// external change (AI edit, collaboration, reload) and wins.
    func shouldApplyIncoming(_ incoming: String, bufferText: String) -> Bool {
        guard incoming != bufferText else { return false }
        if hasPendingLocalEdits, let lastPushedBindingText, incoming == lastPushedBindingText {
            return false
        }
        return true
    }
}
