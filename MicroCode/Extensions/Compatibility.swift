import SwiftUI

// MARK: - Color Compatibility
extension Color {
    static func compat(nsColor: NSColor) -> Color {
        if #available(macOS 12.0, *) {
            return Color(nsColor: nsColor)
        } else {
            return Color(nsColor)
        }
    }
}

// MARK: - Section Compatibility
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    // Wrapper to handle Section("Title") back to Section(header: Text("Title"))
    static func compat(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 12.0, *) {
            return Section(title, content: content)
        } else {
            return Section(header: Text(title), content: content)
        }
    }
}

// MARK: - View Modifiers
extension View {
    @ViewBuilder
    func compatTask(priority: TaskPriority? = nil, _ action: @escaping @Sendable () async -> Void) -> some View {
        if #available(macOS 12.0, *) {
            if let priority = priority {
                self.task(priority: priority, action)
            } else {
                self.task(action)
            }
        } else {
            self.onAppear {
                Task(priority: priority, operation: action)
            }
        }
    }
    
    @ViewBuilder
    func compatOnChange<T: Equatable>(of value: T, perform action: @escaping (T) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
    
    @ViewBuilder
    func compatSearchable(text: Binding<String>, placement: Any? = nil, prompt: String? = nil) -> some View {
        if #available(macOS 12.0, *) {
            // Placement type compatibility is hard, defaulting to automatic
            self.searchable(text: text, prompt: prompt ?? "Search")
        } else {
            // No-op on Big Sur or custom implementation needed
            // For now, no-op to allow compile
            self
        }
    }
    
    @ViewBuilder
    func compatTextSelection() -> some View {
        if #available(macOS 12.0, *) {
            self.textSelection(.enabled)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func compatButtonStyleBorderedProminent() -> some View {
        if #available(macOS 12.0, *) {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(DefaultButtonStyle()) // Fallback
        }
    }
    
    @ViewBuilder
    func compatScrollContentBackground(_ visibility: Visibility) -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(visibility)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func compatGroupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped)
        } else {
            self
        }
    }
}

// MARK: - Compatibility Views
struct CompatLabeledContent: View {
    let label: String
    let value: String
    
    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        if #available(macOS 13.0, *) {
            LabeledContent(label, value: value)
        } else {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - SplitView Compatibility
struct CompatHSplitView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        if #available(macOS 13.0, *) {
            HSplitView {
                content
            }
        } else {
            HStack(spacing: 0) {
                content
            }
        }
    }
}
