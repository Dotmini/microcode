import SwiftUI

struct DataFrameView: View {
    let rawPath: String // Path to source file
    @State private var dataFrameId: String?
    @State private var schema: [String: String] = [:]
    @State private var rows: [[String: Any]] = []
    @State private var isLoading: Bool = true
    @State private var error: String?
    @State private var columns: [String] = []
    @State private var viewMode: ViewMode = .table
    var onGenerateCode: ((String) -> Void)? = nil
    
    enum ViewMode {
        case table, profile
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack {
                Picker("View Mode", selection: $viewMode) {
                    Text("Table").tag(ViewMode.table)
                    Text("Profile").tag(ViewMode.profile)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                
                Spacer()
                
                Text("\(rows.count) rows")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            if isLoading {
                ProgressView("Loading DataFrame...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else {
                if viewMode == .table {
                    tableView
                } else {
                    DataProfilingView(rows: rows, columns: columns, schema: schema, onGenerateCode: onGenerateCode)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadData()
        }
    }
    
    private var tableView: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 1) {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .font(.caption.bold())
                            .padding(8)
                            .frame(width: 150, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                Rectangle()
                                    .frame(width: 1, height: nil, alignment: .trailing)
                                    .foregroundColor(Color.gray.opacity(0.3)),
                                alignment: .trailing
                            )
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                // Data Rows
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { index in
                        let row = rows[index]
                        HStack(spacing: 1) {
                            ForEach(columns, id: \.self) { column in
                                let value = row[column] ?? ""
                                Text("\(value)")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(8)
                                    .frame(width: 150, alignment: .leading)
                                    .overlay(
                                        Rectangle()
                                            .frame(width: 1, height: nil, alignment: .trailing)
                                            .foregroundColor(Color.gray.opacity(0.1)),
                                        alignment: .trailing
                                    )
                            }
                        }
                        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))
                        
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }
    
    private func loadData() async {
        do {
            isLoading = true
            // 1. Load DataFrame
            let id = try await DataFrameService.shared.loadDataFrame(path: rawPath)
            self.dataFrameId = id
            
            // 2. Get Schema
            let schema = try await DataFrameService.shared.getSchema(id: id)
            self.schema = schema
            self.columns = schema.keys.sorted()
            
            // 3. Get First Slice
            let slice = try await DataFrameService.shared.getSlice(id: id, offset: 0, limit: 100)
            self.rows = slice
            
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}
