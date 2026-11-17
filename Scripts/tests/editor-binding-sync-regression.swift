import Foundation

// Regression: typing in the Editor / Cell / Playground code editors must never be reverted by SwiftUI
// re-rendering with the not-yet-synced (debounced) binding value.
// Compiled with the real MicroCode/SyntaxEngine/EditorBindingSyncPolicy.swift by run-editor-binding-sync.sh.

@main struct EditorBindingSyncRegression {
    static func main() {
        var sync = EditorBindingSyncState()

        // File opened: binding and buffer both "pri".
        sync.noteAppliedFromBinding("pri")
        precondition(!sync.shouldApplyIncoming("pri", bufferText: "pri"))

        // User types "nt" quickly; the 90 ms binding debounce has not fired yet.
        sync.noteLocalEdit()
        var buffer = "print"

        // Autocomplete publishes on AppState → SwiftUI calls updateNSView with the OLD binding value "pri".
        // Applying it would delete the characters the user just typed and move the caret.
        precondition(!sync.shouldApplyIncoming("pri", bufferText: buffer),
                     "stale binding echo must not revert unsynced keystrokes")

        // Debounce fires: the binding catches up, and the echo of that value is a no-op.
        sync.notePushedToBinding(buffer)
        precondition(!sync.shouldApplyIncoming("print", bufferText: buffer))

        // A genuine external edit (AI replace_in_file, collaboration, file reload) still applies,
        // even while the user has pending keystrokes.
        sync.noteLocalEdit()
        buffer = "print("
        precondition(sync.shouldApplyIncoming("print('hi')", bufferText: buffer),
                     "external edits must be applied")
        sync.noteAppliedFromBinding("print('hi')")
        buffer = "print('hi')"
        precondition(!sync.shouldApplyIncoming("print('hi')", bufferText: buffer))

        // With no pending local edits, any different binding value is authoritative (e.g. undo via model).
        precondition(sync.shouldApplyIncoming("", bufferText: buffer))

        print("EDITOR BINDING SYNC REGRESSION: PASS")
    }
}
