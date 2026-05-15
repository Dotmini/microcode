import SwiftUI

struct NodeVersionPicker: View {
    @State private var versions: [NodeVersion] = []
    @State private var selectedVersionId: String = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Text("Select Node Version")
                Divider()
                Button("System Default") {
                    selectVersion("")
                }
                ForEach(versions) { version in
                    Button(action: {
                        selectVersion(version.version)
                    }) {
                        HStack {
                            Text(version.version)
                            if version.is_current {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh") {
                    loadVersions()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hexagon.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Text(currentVersionDisplay)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
            
            if let error = error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
                    .help(error)
            }
        }
        .onAppear {
            loadVersions()
        }
    }
    
    private var currentVersionDisplay: String {
        if let current = versions.first(where: { $0.is_current }) {
            return current.version
        }
        if !selectedVersionId.isEmpty {
            return selectedVersionId
        }
        return "System"
    }

    private func loadVersions() {
        isLoading = true
        error = nil
        Task {
            do {
                let fetchedVersions = try await BackendService.shared.listNodeVersions()
                await MainActor.run {
                    self.versions = fetchedVersions
                    if let current = fetchedVersions.first(where: { $0.is_current }) {
                        self.selectedVersionId = current.version
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load"
                    self.isLoading = false
                }
            }
        }
    }

    private func selectVersion(_ version: String) {
        Task {
            do {
                try await BackendService.shared.selectNodeVersion(version)
            } catch {
                print("Failed to select version: \(error)")
            }
        }
    }
}
