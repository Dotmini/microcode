import SwiftUI

struct ContextProviderSuggestionView: View {
    let suggestions: [ContextProviderType]
    var onSelect: (ContextProviderType) -> Void
    @Binding var selectedIndex: Int
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, provider in
                Button(action: {
                    onSelect(provider)
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: provider.icon)
                            .foregroundColor(.primary)
                            .frame(width: 20, height: 20)
                            .padding(6)
                            .background(Color.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text(provider.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(index == selectedIndex ? Color.primary.opacity(0.1) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(width: 300)
    }
}

struct ContextProviderSecondLevelView: View {
    @ObservedObject var service = ContextProviderService.shared
    @EnvironmentObject var appState: AppState
    
    @State private var query: String = ""
    @Binding var selectedIndex: Int
    var onSelect: (ContextItem) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let provider = service.selectedProviderType {
                    Image(systemName: provider.icon)
                        .foregroundColor(.primary)
                }
                TextField("Search...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onChange(of: query) { newValue in
                        if let provider = service.selectedProviderType {
                            service.secondLevelItems = service.loadSecondLevel(for: provider, query: newValue, appState: appState)
                            selectedIndex = 0
                        }
                    }
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    if service.secondLevelItems.isEmpty {
                        Text("No results")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(Array(service.secondLevelItems.enumerated()), id: \.element.id) { index, item in
                            Button(action: {
                                onSelect(item)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        if let subtitle = item.subtitle {
                                            Text(subtitle)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    Spacer()
                                    
                                    Text("~\(item.tokenEstimate) tokens")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == selectedIndex ? Color.primary.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(width: 400)
        .onAppear {
            if let provider = service.selectedProviderType {
                service.secondLevelItems = service.loadSecondLevel(for: provider, query: query, appState: appState)
            }
        }
    }
}

struct AttachedContextBadgeView: View {
    @ObservedObject var service = ContextProviderService.shared
    
    var body: some View {
        if !service.attachedContexts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.attachedContexts) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.provider.icon)
                                .font(.system(size: 10))
                            
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            
                            Button(action: {
                                service.removeContext(item)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    
                    let totalTokens = service.attachedContexts.reduce(0) { $0 + $1.tokenEstimate }
                    Text("~\(totalTokens) tokens")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }
}
