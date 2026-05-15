import SwiftUI

struct LocalGitCommit: Identifiable, Codable {
    let id: String
    let author: String
    let message: String
    let date: String
}

struct GitHistoryView: View {
    @State private var commits: [LocalGitCommit] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Git History")
                .font(.headline)
                .padding(.horizontal)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(commits) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(commit.author)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(commit.date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(commit.message)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(2)
                        Text(commit.id.prefix(7))
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            fetchHistory()
        }
    }
    
    func fetchHistory() {
        isLoading = true
        // Mock API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.commits = [
                LocalGitCommit(id: "a1b2c3d", author: "dotmini", message: "Fix layout issues on mobile #Task-123", date: "2 mins ago"),
                LocalGitCommit(id: "e5f6g7h", author: "dotmini", message: "Initial commit for Phase 10", date: "1 hour ago")
            ]
            self.isLoading = false
        }
    }
}
