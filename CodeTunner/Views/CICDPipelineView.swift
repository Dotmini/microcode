import SwiftUI

// ==========================================
// Main CI/CD Pipeline View — Tabbed Layout
// ==========================================

struct CICDPipelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("Local Pipelines").tag(0)
                    Text("GitHub Actions").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Spacer()
                
                // Pipeline status indicator
                if LocalPipelineRunner.shared.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Running...")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if selectedTab == 0 {
                LocalPipelinesView()
            } else {
                GitHubActionsView()
            }
        }
    }
}

// ==========================================
// Tab 1: Local Pipelines
// ==========================================

struct LocalPipelinesView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var runner = LocalPipelineRunner.shared
    @State private var showingEditor = false
    @State private var editorFilename = ""
    @State private var editorContent = ""
    @State private var editorIsNew = false
    @State private var selectedPipeline: LocalPipeline?
    @State private var selectedHistory: PipelineRunRecord?
    @State private var showSecretsSheet = false
    
    var body: some View {
        HSplitView {
            // Left: Pipeline List + History
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Pipelines")
                        .font(.headline)
                    Spacer()
                    
                    // Auto-detect magic button
                    Button(action: autoGeneratePipeline) {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Auto-detect project & generate pipeline")
                    
                    Button(action: {
                        editorIsNew = true
                        editorFilename = "new-pipeline"
                        editorContent = ""
                        showingEditor = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Button(action: { runner.scanPipelines() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(10)
                
                Divider()
                
                if runner.pipelines.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Pipelines")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Auto-detect or create a pipeline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: autoGeneratePipeline) {
                            Label("Auto-Generate", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Pipeline list
                    List {
                        Section("Workflows") {
                            ForEach(runner.pipelines) { pipeline in
                                Button(action: { selectedPipeline = pipeline }) {
                                    HStack {
                                        Image(systemName: "gear")
                                            .foregroundColor(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pipeline.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text("\(pipeline.jobs.count) jobs · \(pipeline.trigger)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                                .background(selectedPipeline?.filename == pipeline.filename ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                                .contextMenu {
                                    Button("Edit") {
                                        editorIsNew = false
                                        editorFilename = pipeline.filename
                                        editorContent = runner.getPipelineContent(filename: pipeline.filename)
                                        showingEditor = true
                                    }
                                    Button("Run") { Task { await runner.runPipeline(pipeline) } }
                                    Divider()
                                    Button("Delete", role: .destructive) { runner.deletePipeline(filename: pipeline.filename) }
                                }
                            }
                        }
                        
                        // Run History
                        if !runner.runHistory.isEmpty {
                            Section("Recent Runs") {
                                ForEach(runner.runHistory.prefix(10)) { record in
                                    Button(action: { selectedHistory = record }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: record.status.icon)
                                                .foregroundColor(record.status.color)
                                                .font(.caption)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(record.pipelineName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                Text(formatRelativeDate(record.startedAt))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(String(format: "%.1fs", record.totalDuration))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
            
            // Center: Pipeline Detail / Run Result
            VStack(spacing: 0) {
                if let pipeline = selectedPipeline {
                    // Pipeline header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pipeline.name).font(.headline)
                            Text("\(pipeline.jobs.count) jobs · \(pipeline.trigger)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Button(action: {
                            editorIsNew = false
                            editorFilename = pipeline.filename
                            editorContent = runner.getPipelineContent(filename: pipeline.filename)
                            showingEditor = true
                        }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .controlSize(.small)
                        
                        Button(action: { showSecretsSheet = true }) {
                            Label("Secrets", systemImage: "key.fill")
                        }
                        .controlSize(.small)
                        
                        if runner.isRunning {
                            Button(action: { runner.cancelPipeline() }) {
                                Label("Cancel", systemImage: "stop.fill")
                            }
                            .controlSize(.small)
                            .tint(.red)
                        } else {
                            Button(action: { Task { await runner.runPipeline(pipeline) } }) {
                                Label("Run", systemImage: "play.fill")
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(10)
                    
                    Divider()
                    
                    // Visual Pipeline Graph
                    pipelineGraph(pipeline)
                    
                    Divider()
                    
                    // Active run job results
                    if let run = runner.activeRun {
                        runResultsView(run)
                    } else if let hist = selectedHistory {
                        runResultsView(hist)
                    }
                    
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Select a pipeline")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Right: Live Console
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "terminal")
                        .foregroundColor(.green)
                    Text("Console")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if runner.isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }
                    
                    Spacer()
                    Button(action: { runner.liveLog = [] }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(10)
                
                Divider()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(runner.liveLog) { entry in
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.type.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 0.5)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: runner.liveLog.count) { _ in
                        if let last = runner.liveLog.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(minWidth: 250, idealWidth: 350)
        }
        .onAppear {
            if let workspace = appState.workspaceFolder {
                runner.setWorkspace(workspace.path)
            }
        }
        .sheet(isPresented: $showingEditor) {
            WorkflowEditorSheet(
                isPresented: $showingEditor,
                filename: $editorFilename,
                content: $editorContent,
                isNew: editorIsNew,
                onSave: { name, content in
                    runner.savePipeline(filename: name, content: content)
                }
            )
        }
        .sheet(isPresented: $showSecretsSheet) {
            secretsSheet
        }
    }
    
    // MARK: - Visual Pipeline Graph
    
    private func pipelineGraph(_ pipeline: LocalPipeline) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(pipeline.jobs.enumerated()), id: \.element.id) { idx, job in
                    pipelineJobNode(job: job)
                    
                    if idx < pipeline.jobs.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                    }
                }
            }
            .padding(10)
        }
        .frame(height: 70)
        .background(Color.primary.opacity(0.02))
    }
    
    private func pipelineJobNode(job: PipelineJob) -> some View {
        let icon = jobStatusIcon(job.key)
        let clr = jobStatusColor(job.key)
        return VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(clr)
            Text(job.name)
                .font(.system(size: 10, weight: .bold))
            Text("\(job.steps.count) steps")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(minWidth: 80)
        .background(clr.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(clr.opacity(0.3), lineWidth: 1))
    }
    
    private func jobStatusIcon(_ jobKey: String) -> String {
        if let run = runner.activeRun,
           let result = run.jobResults.first(where: { $0.jobKey == jobKey }) {
            return result.status.icon
        }
        return "cube.box"
    }
    
    private func jobStatusColor(_ jobKey: String) -> Color {
        if let run = runner.activeRun,
           let result = run.jobResults.first(where: { $0.jobKey == jobKey }) {
            return result.status.color
        }
        return .secondary
    }
    
    // MARK: - Run Results View
    
    private func runResultsView(_ run: PipelineRunRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Run summary
                HStack {
                    Image(systemName: run.status.icon)
                        .foregroundColor(run.status.color)
                    Text(run.status.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(run.status.color)
                    Spacer()
                    Text(String(format: "%.1fs", run.totalDuration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(run.status.color.opacity(0.05))
                .cornerRadius(6)
                
                // Job results
                ForEach(run.jobResults) { jobResult in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: jobResult.status.icon)
                                    .foregroundColor(jobResult.status.color)
                                Text(jobResult.jobName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.1fs", jobResult.duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            ForEach(jobResult.stepResults) { step in
                                HStack(spacing: 6) {
                                    Image(systemName: step.status.icon)
                                        .foregroundColor(step.status.color)
                                        .font(.caption)
                                    Text(step.name)
                                        .font(.caption)
                                    Spacer()
                                    if step.exitCode != 0 {
                                        Text("exit \(step.exitCode)")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                    Text(String(format: "%.1fs", step.duration))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding(10)
        }
    }
    
    // MARK: - Secrets Sheet
    
    private var secretsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "key.fill").foregroundColor(.orange)
                Text("Pipeline Secrets").font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(runner.secrets.keys.sorted()), id: \.self) { key in
                        HStack {
                            let keyStr: String = key
                            TextField("KEY", text: .constant(keyStr))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .font(.system(.caption, design: .monospaced))
                            Text("=")
                            SecureField("value", text: Binding(
                                get: { runner.secrets[key] ?? "" },
                                set: { runner.secrets[key] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Button(action: { runner.secrets.removeValue(forKey: key) }) {
                                Image(systemName: "minus.circle").foregroundColor(.red)
                            }.buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    
                    Button(action: { runner.secrets["NEW_SECRET"] = "" }) {
                        Label("Add Secret", systemImage: "plus.circle")
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { showSecretsSheet = false }
                Spacer()
                Button("Save") {
                    runner.saveSecrets()
                    showSecretsSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
    }
    
    // MARK: - Helpers
    
    private func autoGeneratePipeline() {
        let content = runner.autoDetectPipeline()
        editorIsNew = true
        editorFilename = "build"
        editorContent = content
        showingEditor = true
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// ==========================================
// Run Detail View
// ==========================================

struct RunDetailView: View {
    let run: PipelineRun
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(run.jobs) { job in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                PipelineStatusIcon(status: job.status)
                                Text(job.name).font(.subheadline).fontWeight(.medium)
                                Spacer()
                                Text(job.status)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            ForEach(job.steps) { step in
                                HStack(spacing: 6) {
                                    Image(systemName: step.status == "success" ? "checkmark.circle.fill" :
                                            step.status == "failed" ? "xmark.circle.fill" :
                                            step.status == "running" ? "arrow.clockwise.circle.fill" :
                                            "circle")
                                    .foregroundColor(step.status == "success" ? .green :
                                                        step.status == "failed" ? .red :
                                                        step.status == "running" ? .blue : .secondary)
                                    .font(.caption)
                                    
                                    Text(step.name)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    if let code = step.exit_code, code != 0 {
                                        Text("exit \(code)")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding(10)
        }
    }
}

// ==========================================
// Pipeline Status Icon
// ==========================================

struct PipelineStatusIcon: View {
    let status: String
    
    var body: some View {
        switch status {
        case "success":
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "failed":
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case "running":
            ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
        case "cancelled":
            Image(systemName: "stop.circle.fill").foregroundColor(.orange)
        default:
            Image(systemName: "circle").foregroundColor(.secondary)
        }
    }
}

// ==========================================
// Smart GUI Workflow Builder
// ==========================================

class EditableStep: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var stepType: StepType
    @Published var command: String
    @Published var host: String
    @Published var user: String
    @Published var keyPath: String
    @Published var port: String
    @Published var source: String
    @Published var target: String
    @Published var branch: String
    @Published var remote: String
    
    enum StepType: String, CaseIterable {
        case shell = "Shell Command"
        case sshDeploy = "SSH Deploy (rsync)"
        case sshRun = "SSH Run Command"
        case gitSync = "Git Sync"
        
        var icon: String {
            switch self {
            case .shell: return "terminal"
            case .sshDeploy: return "arrow.up.doc"
            case .sshRun: return "bolt.horizontal"
            case .gitSync: return "arrow.triangle.2.circlepath"
            }
        }
    }
    
    init(name: String = "New Step", stepType: StepType = .shell, command: String = "") {
        self.name = name
        self.stepType = stepType
        self.command = command
        self.host = ""
        self.user = ""
        self.keyPath = "~/.ssh/id_rsa"
        self.port = "22"
        self.source = "./dist/"
        self.target = "/var/www/app/"
        self.branch = "main"
        self.remote = "origin"
    }
}

class EditableJob: ObservableObject, Identifiable {
    let id = UUID()
    @Published var key: String
    @Published var name: String
    @Published var needs: String
    @Published var steps: [EditableStep]
    
    init(key: String = "build", name: String = "Build", needs: String = "", steps: [EditableStep] = []) {
        self.key = key
        self.name = name
        self.needs = needs
        self.steps = steps
    }
}

struct WorkflowEditorSheet: View {
    @Binding var isPresented: Bool
    @Binding var filename: String
    @Binding var content: String
    var isNew: Bool
    var onSave: (String, String) -> Void
    
    @State private var workflowName = "My Pipeline"
    @State private var triggerType = "manual"
    @State private var envVars: [(String, String)] = []
    @State private var jobs: [EditableJob] = []
    @State private var showYAML = false
    
    let triggerOptions = ["manual", "push", "schedule"]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.2").foregroundColor(.blue)
                Text(isNew ? "New Pipeline" : "Edit Pipeline").font(.headline)
                Spacer()
                Picker("", selection: $showYAML) {
                    Label("Visual", systemImage: "square.grid.2x2").tag(false)
                    Label("YAML", systemImage: "chevron.left.forwardslash.chevron.right").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 180)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if showYAML {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Basic Settings
                        GroupBox {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "doc.text").foregroundColor(.blue)
                                    Text("Basic Settings").font(.subheadline).bold()
                                }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Pipeline Name").font(.caption).foregroundColor(.secondary)
                                        TextField("My Pipeline", text: $workflowName).textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Filename").font(.caption).foregroundColor(.secondary)
                                        TextField("deploy.yml", text: $filename).textFieldStyle(.roundedBorder).frame(width: 150)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Trigger").font(.caption).foregroundColor(.secondary)
                                        Picker("", selection: $triggerType) {
                                            ForEach(triggerOptions, id: \.self) { Text($0).tag($0) }
                                        }.frame(width: 120)
                                    }
                                }
                            }.padding(4)
                        }
                        
                        // Environment Variables
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle").foregroundColor(.purple)
                                    Text("Environment Variables").font(.subheadline).bold()
                                    Spacer()
                                    Button(action: { envVars.append(("", "")) }) {
                                        Image(systemName: "plus.circle")
                                    }.buttonStyle(BorderlessButtonStyle())
                                }
                                if envVars.isEmpty {
                                    Text("No environment variables — click + to add")
                                        .font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
                                } else {
                                    ForEach(envVars.indices, id: \.self) { i in
                                        HStack(spacing: 8) {
                                            TextField("KEY", text: Binding(get: { envVars[i].0 }, set: { envVars[i].0 = $0 }))
                                                .textFieldStyle(.roundedBorder).frame(width: 150).font(.system(.body, design: .monospaced))
                                            Text("=").foregroundColor(.secondary)
                                            TextField("value", text: Binding(get: { envVars[i].1 }, set: { envVars[i].1 = $0 }))
                                                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                                            Button(action: { envVars.remove(at: i) }) {
                                                Image(systemName: "minus.circle").foregroundColor(.red)
                                            }.buttonStyle(BorderlessButtonStyle())
                                        }
                                    }
                                }
                            }.padding(4)
                        }
                        
                        // Jobs
                        HStack {
                            Image(systemName: "flowchart").foregroundColor(.orange)
                            Text("Jobs").font(.subheadline).bold()
                            Spacer()
                            Button(action: { addJob() }) { Label("Add Job", systemImage: "plus.circle") }
                                .buttonStyle(BorderlessButtonStyle())
                        }
                        
                        ForEach(Array(jobs.enumerated()), id: \.element.id) { _, job in
                            JobEditorCard(job: job, onDelete: { jobs.removeAll { $0.id == job.id } })
                        }
                    }.padding()
                }
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                if !showYAML {
                    Button("Preview YAML") { content = generateYAML(); showYAML = true }
                }
                Button("Save") {
                    if !showYAML { content = generateYAML() }
                    let name = filename.hasSuffix(".yml") || filename.hasSuffix(".yaml") ? filename : "\(filename).yml"
                    onSave(name, content)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 780, height: 620)
        .onAppear {
            if !content.isEmpty { parseYAMLToGUI() }
            else if isNew {
                let s1 = EditableStep(name: "Install Dependencies", stepType: .shell, command: "npm install")
                let s2 = EditableStep(name: "Build", stepType: .shell, command: "npm run build")
                let buildJob = EditableJob(key: "build", name: "Build", steps: [s1, s2])
                let ds = EditableStep(name: "Deploy to Server", stepType: .sshDeploy)
                ds.host = "your-server.com"; ds.user = "deploy"
                let deployJob = EditableJob(key: "deploy", name: "Deploy", needs: "build", steps: [ds])
                jobs = [buildJob, deployJob]
                workflowName = "Deploy Production"
            }
        }
    }
    
    func generateYAML() -> String {
        var y = "name: \(workflowName)\non: \(triggerType)\n"
        if !envVars.isEmpty {
            y += "\nenv:\n"
            for (k, v) in envVars where !k.isEmpty { y += "  \(k): \(v)\n" }
        }
        y += "\njobs:\n"
        for job in jobs {
            y += "  \(job.key):\n    name: \(job.name)\n"
            if !job.needs.isEmpty { y += "    needs: \(job.needs)\n" }
            y += "    steps:\n"
            for step in job.steps {
                y += "      - name: \(step.name)\n"
                switch step.stepType {
                case .shell:
                    if step.command.contains("\n") {
                        y += "        run: |\n"
                        for line in step.command.components(separatedBy: "\n") { y += "          \(line)\n" }
                    } else { y += "        run: \(step.command)\n" }
                case .sshDeploy:
                    y += "        uses: ssh-deploy\n        with:\n"
                    y += "          host: \(step.host)\n          user: \(step.user)\n"
                    if step.keyPath != "~/.ssh/id_rsa" && !step.keyPath.isEmpty { y += "          key_path: \(step.keyPath)\n" }
                    if step.port != "22" { y += "          port: \(step.port)\n" }
                    y += "          source: \(step.source)\n          target: \(step.target)\n"
                case .sshRun:
                    y += "        uses: ssh-run\n        with:\n"
                    y += "          host: \(step.host)\n          user: \(step.user)\n"
                    if step.keyPath != "~/.ssh/id_rsa" && !step.keyPath.isEmpty { y += "          key_path: \(step.keyPath)\n" }
                    if step.port != "22" { y += "          port: \(step.port)\n" }
                    y += "          command: \(step.command)\n"
                case .gitSync:
                    y += "        uses: git-sync\n        with:\n"
                    y += "          remote: \(step.remote)\n          branch: \(step.branch)\n"
                }
            }
        }
        return y
    }
    
    func parseYAMLToGUI() {
        if let r = content.range(of: "name: ") { workflowName = String(content[r.upperBound...].prefix(while: { $0 != "\n" })) }
        if let r = content.range(of: "on: ") { triggerType = String(content[r.upperBound...].prefix(while: { $0 != "\n" })) }
        envVars = []
        if let er = content.range(of: "env:\n") {
            for line in content[er.upperBound...].components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || !line.hasPrefix("  ") || t.hasPrefix("jobs:") { break }
                if t.contains(": ") && !t.hasPrefix("#") {
                    let p = t.components(separatedBy: ": ")
                    if p.count >= 2 { envVars.append((p[0], p.dropFirst().joined(separator: ": "))) }
                }
            }
        }
        jobs = []
        let lines = content.components(separatedBy: "\n")
        var ck = "", cn = "", cneeds = ""
        var cs: [EditableStep] = []
        var inJ = false, inS = false, inW = false
        var curS: EditableStep?
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "jobs:" { inJ = true; continue }
            guard inJ else { continue }
            if line.hasPrefix("  ") && !line.hasPrefix("    ") && t.hasSuffix(":") && !t.hasPrefix("-") {
                if !ck.isEmpty {
                    if let s = curS { cs.append(s) }
                    jobs.append(EditableJob(key: ck, name: cn.isEmpty ? ck : cn, needs: cneeds, steps: cs))
                }
                ck = String(t.dropLast()); cn = ""; cneeds = ""; cs = []; curS = nil; inS = false; inW = false; continue
            }
            if t.hasPrefix("name: ") && !inS { cn = String(t.dropFirst(6)) }
            if t.hasPrefix("needs: ") { cneeds = String(t.dropFirst(7)) }
            if t == "steps:" { inS = true; continue }
            if inS {
                if t.hasPrefix("- name: ") {
                    if let s = curS { cs.append(s) }
                    curS = EditableStep(name: String(t.dropFirst(8))); inW = false
                } else if let step = curS {
                    if t.hasPrefix("run: ") { step.stepType = .shell; step.command = String(t.dropFirst(5)) }
                    else if t.hasPrefix("uses: ssh-deploy") { step.stepType = .sshDeploy }
                    else if t.hasPrefix("uses: ssh-run") { step.stepType = .sshRun }
                    else if t.hasPrefix("uses: git-sync") { step.stepType = .gitSync }
                    else if t == "with:" { inW = true }
                    else if inW {
                        if t.hasPrefix("host: ") { step.host = String(t.dropFirst(6)) }
                        if t.hasPrefix("user: ") { step.user = String(t.dropFirst(6)) }
                        if t.hasPrefix("key_path: ") { step.keyPath = String(t.dropFirst(10)) }
                        if t.hasPrefix("port: ") { step.port = String(t.dropFirst(6)) }
                        if t.hasPrefix("source: ") { step.source = String(t.dropFirst(8)) }
                        if t.hasPrefix("target: ") { step.target = String(t.dropFirst(8)) }
                        if t.hasPrefix("command: ") { step.command = String(t.dropFirst(9)) }
                        if t.hasPrefix("branch: ") { step.branch = String(t.dropFirst(8)) }
                        if t.hasPrefix("remote: ") { step.remote = String(t.dropFirst(8)) }
                    }
                }
            }
        }
        if !ck.isEmpty {
            if let s = curS { cs.append(s) }
            jobs.append(EditableJob(key: ck, name: cn.isEmpty ? ck : cn, needs: cneeds, steps: cs))
        }
    }
    
    func addJob() {
        let c = jobs.count + 1
        jobs.append(EditableJob(key: "job\(c)", name: "Job \(c)", steps: [
            EditableStep(name: "Run command", stepType: .shell, command: "echo \"Hello\"")
        ]))
    }
}

// ==========================================
// Job Editor Card
// ==========================================

struct JobEditorCard: View {
    @ObservedObject var job: EditableJob
    var onDelete: () -> Void
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "cube.box").foregroundColor(.orange)
                    HStack(spacing: 8) {
                        TextField("job_key", text: $job.key).textFieldStyle(.roundedBorder).frame(width: 120)
                            .font(.system(.body, design: .monospaced))
                        TextField("Display Name", text: $job.name).textFieldStyle(.roundedBorder).frame(width: 160)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("needs:").font(.caption).foregroundColor(.secondary)
                        TextField("job key", text: $job.needs).textFieldStyle(.roundedBorder).frame(width: 100)
                            .font(.system(.caption, design: .monospaced))
                    }
                    Button(action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }
                        .buttonStyle(BorderlessButtonStyle())
                }
                Divider()
                ForEach(Array(job.steps.enumerated()), id: \.element.id) { idx, step in
                    StepEditorRow(step: step, index: idx, total: job.steps.count,
                        onMoveUp: { if idx > 0 { job.steps.swapAt(idx, idx - 1) } },
                        onMoveDown: { if idx < job.steps.count - 1 { job.steps.swapAt(idx, idx + 1) } },
                        onDelete: { job.steps.removeAll { $0.id == step.id } })
                    if idx < job.steps.count - 1 { Divider().padding(.vertical, 2) }
                }
                Button(action: { job.steps.append(EditableStep(name: "New Step", stepType: .shell, command: "echo hello")) }) {
                    Label("Add Step", systemImage: "plus.circle").font(.caption)
                }.buttonStyle(BorderlessButtonStyle()).padding(.top, 4)
            }.padding(4)
        }
    }
}

// ==========================================
// Step Editor Row
// ==========================================

struct StepEditorRow: View {
    @ObservedObject var step: EditableStep
    var index: Int
    var total: Int
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: step.stepType.icon).foregroundColor(.blue).frame(width: 16)
                TextField("Step Name", text: $step.name).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Picker("", selection: $step.stepType) {
                    ForEach(EditableStep.StepType.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }.frame(width: 180)
                Spacer()
                HStack(spacing: 2) {
                    Button(action: onMoveUp) { Image(systemName: "chevron.up") }.disabled(index == 0).buttonStyle(BorderlessButtonStyle())
                    Button(action: onMoveDown) { Image(systemName: "chevron.down") }.disabled(index >= total - 1).buttonStyle(BorderlessButtonStyle())
                    Button(action: onDelete) { Image(systemName: "xmark.circle").foregroundColor(.red) }.buttonStyle(BorderlessButtonStyle())
                }
            }
            switch step.stepType {
            case .shell:
                TextEditor(text: $step.command).font(.system(.caption, design: .monospaced)).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            case .sshDeploy:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) { Text("Host").font(.caption2).foregroundColor(.secondary); TextField("server.com", text: $step.host).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 2) { Text("User").font(.caption2).foregroundColor(.secondary); TextField("deploy", text: $step.user).textFieldStyle(.roundedBorder).frame(width: 80) }
                    VStack(alignment: .leading, spacing: 2) { Text("Port").font(.caption2).foregroundColor(.secondary); TextField("22", text: $step.port).textFieldStyle(.roundedBorder).frame(width: 50) }
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) { Text("Source").font(.caption2).foregroundColor(.secondary); TextField("./dist/", text: $step.source).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)) }
                    Image(systemName: "arrow.right").foregroundColor(.secondary).padding(.top, 12)
                    VStack(alignment: .leading, spacing: 2) { Text("Target").font(.caption2).foregroundColor(.secondary); TextField("/var/www/app/", text: $step.target).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)) }
                }
                VStack(alignment: .leading, spacing: 2) { Text("SSH Key").font(.caption2).foregroundColor(.secondary); TextField("~/.ssh/id_rsa", text: $step.keyPath).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)) }
            case .sshRun:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) { Text("Host").font(.caption2).foregroundColor(.secondary); TextField("server.com", text: $step.host).textFieldStyle(.roundedBorder) }
                    VStack(alignment: .leading, spacing: 2) { Text("User").font(.caption2).foregroundColor(.secondary); TextField("deploy", text: $step.user).textFieldStyle(.roundedBorder).frame(width: 80) }
                    VStack(alignment: .leading, spacing: 2) { Text("Port").font(.caption2).foregroundColor(.secondary); TextField("22", text: $step.port).textFieldStyle(.roundedBorder).frame(width: 50) }
                }
                VStack(alignment: .leading, spacing: 2) { Text("Command").font(.caption2).foregroundColor(.secondary); TextField("sudo systemctl restart app", text: $step.command).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced)) }
            case .gitSync:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) { Text("Remote").font(.caption2).foregroundColor(.secondary); TextField("origin", text: $step.remote).textFieldStyle(.roundedBorder).frame(width: 120) }
                    VStack(alignment: .leading, spacing: 2) { Text("Branch").font(.caption2).foregroundColor(.secondary); TextField("main", text: $step.branch).textFieldStyle(.roundedBorder).frame(width: 120) }
                }
            }
        }
        .padding(6).background(Color(nsColor: .controlBackgroundColor).opacity(0.5)).cornerRadius(6)
    }
}

// ==========================================
// Tab 2: GitHub Actions (Production-Grade)
// ==========================================

struct GitHubActionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var runs: [WorkflowRun] = []
    @State private var selectedRun: WorkflowRun?
    @State private var jobs: [Job] = []
    @State private var selectedJob: Job?
    @State private var jobLogs: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSettings = false
    
    private let cicdService = CICDService.shared
    
    private var isConfigured: Bool {
        !appState.githubOwner.isEmpty && !appState.githubRepo.isEmpty && !appState.githubToken.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                if isConfigured {
                    Image(systemName: "bolt.circle.fill").foregroundColor(.green)
                    Text("\(appState.githubOwner)/\(appState.githubRepo)")
                        .font(.subheadline).fontWeight(.medium)
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text("GitHub not configured").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                
                if isConfigured {
                    Button(action: fetchRuns) {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(BorderlessButtonStyle()).disabled(isLoading)
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                }.buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if !isConfigured {
                // Onboarding
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 40)).foregroundColor(.secondary)
                    Text("Connect GitHub Repository")
                        .font(.title3).fontWeight(.medium)
                    Text("Configure your GitHub owner, repository, and personal access token to view workflow runs.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                    Button("Configure") { showingSettings = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Left: Workflow Runs
                    VStack(spacing: 0) {
                        if isLoading && runs.isEmpty {
                            VStack { Spacer(); ProgressView("Loading..."); Spacer() }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if runs.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 28)).foregroundColor(.secondary)
                                Text("No workflow runs").font(.subheadline).foregroundColor(.secondary)
                                Button("Refresh") { fetchRuns() }.controlSize(.small)
                                Spacer()
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(runs, selection: Binding(
                                get: { selectedRun?.id },
                                set: { id in
                                    selectedRun = runs.first { $0.id == id }
                                    if let run = selectedRun { fetchJobs(for: run) }
                                }
                            )) { run in
                                HStack(spacing: 8) {
                                    ghStatusIcon(run.conclusion ?? run.status)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.display_title)
                                            .font(.subheadline).fontWeight(.medium).lineLimit(1)
                                        Text("#\(run.run_number) · \(run.name)")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(formatDate(run.created_at))
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                                .tag(run.id)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .frame(minWidth: 250, idealWidth: 320)
                    
                    // Right: Jobs + Logs
                    VStack(spacing: 0) {
                        if let run = selectedRun {
                            // Run header
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.display_title).font(.headline)
                                    HStack(spacing: 8) {
                                        Text(run.name).font(.caption).foregroundColor(.secondary)
                                        ghStatusBadge(run.conclusion ?? run.status)
                                    }
                                }
                                Spacer()
                                Link(destination: URL(string: run.html_url)!) {
                                    Label("Open in GitHub", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                            .padding(10)
                            
                            Divider()
                            
                            // Jobs
                            if jobs.isEmpty {
                                VStack { Spacer(); ProgressView(); Spacer() }
                                    .frame(maxHeight: 100)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(jobs) { job in
                                            Button(action: {
                                                selectedJob = job
                                                fetchLogs(for: job)
                                            }) {
                                                HStack(spacing: 6) {
                                                    ghStatusIcon(job.conclusion ?? job.status)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(job.name).font(.caption).fontWeight(.medium)
                                                        if let steps = job.steps {
                                                            Text("\(steps.count) steps").font(.caption2).foregroundColor(.secondary)
                                                        }
                                                    }
                                                }
                                                .padding(8)
                                                .background(selectedJob?.id == job.id ?
                                                    Color.accentColor.opacity(0.15) :
                                                    Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(6)
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                                                    selectedJob?.id == job.id ? Color.accentColor : Color.clear,
                                                    lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(10)
                                }
                                
                                Divider()
                                
                                // Steps list for selected job
                                if let job = selectedJob, let steps = job.steps {
                                    VStack(spacing: 0) {
                                        ForEach(steps) { step in
                                            HStack(spacing: 6) {
                                                ghStatusIcon(step.conclusion ?? step.status)
                                                    .font(.caption)
                                                Text(step.name).font(.caption).lineLimit(1)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                        }
                                    }
                                    .frame(maxHeight: 120)
                                    
                                    Divider()
                                }
                            }
                            
                            // Logs
                            ScrollView {
                                Text(jobLogs.isEmpty ? "Select a job to view logs" : jobLogs)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(jobLogs.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .background(Color(nsColor: .textBackgroundColor))
                            
                        } else {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "sidebar.left").font(.system(size: 32)).foregroundColor(.secondary)
                                Text("Select a workflow run").foregroundColor(.secondary)
                                Spacer()
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            
            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(err).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }.controlSize(.mini)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }
        }
        .onAppear {
            if isConfigured { fetchRuns() }
            else if let folder = appState.workspaceFolder {
                appState.detectGitRemote(for: folder)
            }
        }
        .sheet(isPresented: $showingSettings) {
            GitHubSettingsSheet(isPresented: $showingSettings)
        }
    }
    
    func fetchRuns() {
        isLoading = true; errorMessage = nil
        cicdService.fetchWorkflowRuns(owner: appState.githubOwner, repo: appState.githubRepo, token: appState.githubToken) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let r): runs = r
                case .failure(let e): errorMessage = e.localizedDescription
                }
            }
        }
    }
    
    func fetchJobs(for run: WorkflowRun) {
        jobs = []; selectedJob = nil; jobLogs = ""
        cicdService.fetchJobs(owner: appState.githubOwner, repo: appState.githubRepo, token: appState.githubToken, runId: run.id) { result in
            DispatchQueue.main.async {
                if case .success(let j) = result { jobs = j }
            }
        }
    }
    
    func fetchLogs(for job: Job) {
        jobLogs = "Loading logs..."
        cicdService.getJobLogs(owner: appState.githubOwner, repo: appState.githubRepo, token: appState.githubToken, jobId: job.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let logs): jobLogs = logs
                case .failure(let e): jobLogs = "Error: \(e.localizedDescription)"
                }
            }
        }
    }
    
    func formatDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        if let date = fmt.date(from: iso) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
    
    @ViewBuilder
    func ghStatusIcon(_ status: String) -> some View {
        switch status {
        case "success": Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "failure": Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case "in_progress": ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
        case "queued": Image(systemName: "clock.fill").foregroundColor(.orange)
        case "cancelled", "skipped": Image(systemName: "stop.circle.fill").foregroundColor(.secondary)
        default: Image(systemName: "circle").foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    func ghStatusBadge(_ status: String) -> some View {
        let color: Color = status == "success" ? .green : status == "failure" ? .red : status == "in_progress" ? .blue : .secondary
        Text(status.replacingOccurrences(of: "_", with: " "))
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// ==========================================
// GitHub Settings Sheet
// ==========================================

struct GitHubSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    @State private var owner: String = ""
    @State private var repo: String = ""
    @State private var token: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gear").foregroundColor(.blue)
                Text("GitHub Settings").font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "person.fill").foregroundColor(.blue)
                            Text("Repository").font(.subheadline).bold()
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Owner").font(.caption).foregroundColor(.secondary)
                                TextField("owner", text: $owner).textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Repository").font(.caption).foregroundColor(.secondary)
                                TextField("repo", text: $repo).textFieldStyle(.roundedBorder)
                            }
                        }
                    }.padding(4)
                }
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "key.fill").foregroundColor(.orange)
                            Text("Authentication").font(.subheadline).bold()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Personal Access Token").font(.caption).foregroundColor(.secondary)
                            SecureField("ghp_xxxxxxxxxxxx", text: $token).textFieldStyle(.roundedBorder)
                        }
                        Text("Requires repo scope. Create at github.com/settings/tokens")
                            .font(.caption2).foregroundColor(.secondary)
                    }.padding(4)
                }
                
                if let folder = appState.workspaceFolder {
                    Button(action: {
                        appState.detectGitRemote(for: folder)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            owner = appState.githubOwner
                            repo = appState.githubRepo
                        }
                    }) {
                        Label("Auto-detect from Git", systemImage: "wand.and.stars")
                    }
                    .controlSize(.small)
                }
            }
            .padding()
            
            Divider()
            
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") {
                    appState.githubOwner = owner
                    appState.githubRepo = repo
                    appState.githubToken = token
                    appState.saveGitHubSettings()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(width: 480, height: 380)
        .onAppear {
            owner = appState.githubOwner
            repo = appState.githubRepo
            token = appState.githubToken
        }
    }
}
