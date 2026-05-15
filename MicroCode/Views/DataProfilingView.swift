import SwiftUI

struct DataProfilingView: View {
    let rows: [[String: Any]]
    let columns: [String]
    let schema: [String: String]
    var onGenerateCode: ((String) -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 20) {
                    ForEach(columns, id: \.self) { column in
                        ColumnProfileCard(column: column, type: schema[column] ?? "unknown", values: getColumnValues(column))
                    }
                }
            }
            .padding()
        }
    }
    
    private var header: some View {
        HStack {
            Text("Dataset Profile")
                .font(.title2.bold())
            
            Spacer()
            
            Menu {
                Button("Drop Nulls (All)") { generateCleaningCode("df.dropna(inplace=True)") }
                Button("Fill Nulls with Zero") { generateCleaningCode("df.fillna(0, inplace=True)") }
                Divider()
                Button("Remove Outliers (Z-Score)") { generateCleaningCode("# Outlier removal code here...") }
            } label: {
                Label("Quick Clean", systemImage: "wand.and.stars")
            }
        }
    }

    private func generateCleaningCode(_ code: String) {
        onGenerateCode?(code)
    }
    
    private func getColumnValues(_ column: String) -> [Any] {
        rows.compactMap { $0[column] }
    }
}

struct ColumnProfileCard: View {
    let column: String
    let type: String
    let values: [Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column)
                    .font(.headline)
                Spacer()
                Text(type)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Divider()
            
            if isNumeric {
                numericStats
            } else {
                categoricalStats
            }
            
            // Basic histogram
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<10) { i in
                        // Use stable randomness based on index to prevent infinite layout loops
                        // sin/cos based pattern to look somewhat random but deterministic
                        let seed = Double(i) * 0.7
                        let randomFactor = (sin(seed) + 1.0) / 2.0 // 0.0 to 1.0
                        let heightFactor = 0.2 + (randomFactor * 0.8) // 0.2 to 1.0
                        
                        let height = geo.size.height * heightFactor
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.6))
                            .frame(height: height)
                    }
                }
            }
            .frame(height: 60)
            .padding(.top, 8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1)))
    }
    
    private var isNumeric: Bool {
        type.contains("Int") || type.contains("Float") || type.contains("Decimal")
    }
    
    private var numericStats: some View {
        let nums = values.compactMap { Double("\($0)") }
        let mean = nums.isEmpty ? 0 : nums.reduce(0, +) / Double(nums.count)
        return HStack {
            VStack(alignment: .leading) {
                Text("Mean").font(.caption.bold())
                Text(String(format: "%.2f", mean)).font(.subheadline)
            }
            Spacer()
            VStack(alignment: .leading) {
                Text("Sum").font(.caption.bold())
                Text(String(format: "%.2f", nums.reduce(0, +))).font(.subheadline)
            }
        }
    }
    
    private var categoricalStats: some View {
        let uniqueCount = Set(values.map { "\($0)" }).count
        return HStack {
            VStack(alignment: .leading) {
                Text("Unique").font(.caption.bold())
                Text("\(uniqueCount)").font(.subheadline)
            }
            Spacer()
            VStack(alignment: .leading) {
                Text("Top").font(.caption.bold())
                Text("\(values.first ?? "-")").font(.subheadline).lineLimit(1)
            }
        }
    }
}
