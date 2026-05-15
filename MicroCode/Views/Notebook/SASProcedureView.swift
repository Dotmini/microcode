import SwiftUI

struct SASProcedureView: View {
    @ObservedObject var cell: NotebookCellModel
    let onRun: () -> Void
    @State private var moduleType: SASModuleType = .dataStep
    @State private var params = SASProcedureParams(moduleType: SASModuleType.dataStep.rawValue)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Divider()
            
            moduleSelector
            
            Divider()
            
            parameterConfig
            
            Spacer()
            
            codePreview
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            loadMetadata()
        }
        .onChange(of: moduleType) { _ in updateMetadata() }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: moduleType.icon)
                .foregroundColor(moduleType.color)
            Text("SAS Procedure: \(moduleType.rawValue)")
                .font(.headline)
            Spacer()
            Button(action: onRun) {
                Label("Run Module", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(moduleType.color)
        }
    }
    
    private var moduleSelector: some View {
        Picker("Module Type", selection: $moduleType) {
            ForEach(SASModuleType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var parameterConfig: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch moduleType {
                case .dataStep:
                    dataStepConfig
                case .procSql:
                    procSqlConfig
                case .procMeans:
                    procMeansConfig
                case .procReg:
                    procRegConfig
                case .procFreq:
                    procFreqConfig
                }
            }
        }
    }
    
    // MARK: - Specialized Config Views
    
    private var dataStepConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Input Table", text: $params.inputTable)
            TextField("Output Table", text: $params.outputTable)
            Text("Operations (Not implemented)").font(.caption).foregroundColor(.secondary)
        }
        .textFieldStyle(.roundedBorder)
    }
    
    private var procSqlConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $params.customCode)
                .frame(height: 100)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
        }
    }
    
    private var procMeansConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Input Table", text: $params.inputTable)
            Text("Statistics: MEAN, MIN, MAX, STD").font(.caption)
        }
        .textFieldStyle(.roundedBorder)
    }
    
    private var procRegConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Dependent Variable (Y)", text: $params.targetVariable)
            TextField("Independent Variable (X)", text: $params.inputTable) // Proxy
        }
        .textFieldStyle(.roundedBorder)
    }
    
    private var procFreqConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Table", text: $params.inputTable)
        }
        .textFieldStyle(.roundedBorder)
    }
    
    private var codePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generated Python Code")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { transpile(to: "Python") }) {
                    Label("AI Transpile (Python)", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Button(action: { transpile(to: "Rust") }) {
                    Label("AI Transpile (Rust)", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
            }
            
            Text(generatePythonCode())
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
        }
    }

    private func transpile(to language: String) {
        let code = generatePythonCode() // Use the generated code as a base or the metadata
        let instructions = "Optimize for performance and readability. Use idiomatic \(language) patterns."
        
        Task {
            do {
                let transpiled = try await BackendService.shared.transpileCode(
                    code: code,
                    targetLanguage: language,
                    instructions: instructions,
                    provider: nil,
                    model: nil,
                    apiKey: nil
                )
                
                DispatchQueue.main.async {
                    // Update cell content or show in a sheet
                    cell.content = transpiled
                    cell.type = .code
                    cell.language = (language == "Python" ? .python : .rust)
                }
            } catch {
                print("Transpilation failed: \(error)")
            }
        }
    }
    
    private func generatePythonCode() -> String {
        switch moduleType {
        case .dataStep:
            return """
            import pandas as pd
            
            # DATA Step: \(params.outputTable)
            def data_step():
                df = pd.read_csv('\(params.inputTable)') if '\(params.inputTable)'.endswith('.csv') else pd.DataFrame()
                # Operations
                \(params.whereClause.isEmpty ? "" : "df = df.query('\(params.whereClause)')")}
                return df

            \(params.outputTable) = data_step()
            print(f"Created table \(params.outputTable) with {len(\(params.outputTable))} rows")
            """
        case .procSql:
            return """
            import pandas as pd
            from pandasql import sqldf
            
            # PROC SQL
            pysqldf = lambda q: sqldf(q, globals())
            
            query = \"\"\"
            \(params.customCode)
            \"\"\"
            
            result = pysqldf(query)
            print(result)
            """
        case .procMeans:
            return """
            import pandas as pd
            
            # PROC MEANS
            df = \(params.inputTable)
            stats = df.describe()
            print("--- Statistical Summary ---")
            print(stats)
            """
        case .procReg:
            return """
            import statsmodels.api as sm
            import pandas as pd
            
            # PROC REG: \(params.targetVariable) ~ \(params.inputTable)
            X = \(params.inputTable)
            y = \(params.targetVariable)
            X = sm.add_constant(X)
            model = sm.OLS(y, X).fit()
            print(model.summary())
            """
        case .procFreq:
            return """
            import pandas as pd
            
            # PROC FREQ
            df = \(params.inputTable)
            for col in \(params.selectedVariables.description):
                print(f"\\nFrequency Table for {col}:")
                print(df[col].value_counts())
            """
        }
    }
    
    private func loadMetadata() {
        let metadata = cell.procedureMetadata
        if let typeValue = metadata["moduleType"],
           let typeRaw = typeValue.value as? String,
           let type = SASModuleType(rawValue: typeRaw) {
            self.moduleType = type
        }
        // Load other params...
    }
    
    private func updateMetadata() {
        var metadata = cell.procedureMetadata
        metadata["moduleType"] = AnyCodable(moduleType.rawValue)
        cell.procedureMetadata = metadata
        cell.generatedCode = generatePythonCode()
    }
}
