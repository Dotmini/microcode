import SwiftUI
import SceneKit
import AppKit

struct ScienceModeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var agent = AgentService.shared
    @StateObject private var modelCatalog = AIModelCatalog.shared
    @State private var structure: ProteinStructureDocument?
    @State private var scene = SCNScene()
    @State private var isLoadingStructure = false
    @State private var loadError: String?
    @State private var showBackbone = true
    @State private var selectedPanel: SciencePanel = .project

    private var activeURL: URL? {
        guard let file = appState.currentFile else { return nil }
        return URL(fileURLWithPath: file.path)
    }

    private var isStructureFile: Bool {
        guard let ext = activeURL?.pathExtension.lowercased() else { return false }
        return ["pdb", "ent", "cif", "mmcif"].contains(ext)
    }

    private var activeExtension: String { activeURL?.pathExtension.lowercased() ?? "" }
    private var currentText: String { appState.currentFile?.content ?? "" }

    private var scienceModels: [AIModelDefinition] {
        modelCatalog.providers.flatMap(\.models).filter {
            let value = ($0.id + " " + $0.name).lowercased()
            return value.contains("medgemma") || value.contains("txgemma") || value.contains("biomed")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            scienceToolbar
            Divider()
            HSplitView {
                AIAgentView(allowsChatSidebar: false)
                    .environmentObject(appState)
                    .frame(minWidth: 420, idealWidth: 620)

                artifactPanel
                    .frame(minWidth: 360, idealWidth: 520)
            }
        }
        .background(Color(nsColor: appState.appTheme.workspaceBackground))
        .onAppear {
            agent.domain = .science
            if let workspace = appState.workspaceFolder {
                agent.setWorkspace(workspace.path)
                agent.refreshScienceProjectContext()
            }
            routeActiveArtifact()
            loadActiveArtifact()
        }
        .onDisappear {
            if agent.domain == .science { agent.domain = .software }
        }
        .onChange(of: appState.currentFile?.path) { _ in
            routeActiveArtifact()
            loadActiveArtifact()
        }
        .onChange(of: showBackbone) { _ in rebuildScene() }
    }

    private var scienceToolbar: some View {
        HStack(spacing: 12) {
            Text("Science")
                .font(.system(size: 12, weight: .semibold))
            Text("Research workspace")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Divider().frame(height: 16)

            Picker("Workspace", selection: $selectedPanel) {
                ForEach(SciencePanel.allCases) { panel in Text(panel.rawValue).tag(panel) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Spacer()

            Button("AlphaFold") { startAlphaFoldWorkflow() }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.bordered)

            Button("MedGemma") { startMedGemmaWorkflow() }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.bordered)

            Button("Analyze in Cells") { openInCells() }
                .font(.system(size: 10, weight: .medium)).buttonStyle(.bordered)

            Text("Research use")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("Open Artifact") { openArtifact() }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }

    @ViewBuilder
    private var artifactPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(selectedPanel.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if selectedPanel == .structure, structure != nil {
                    Toggle("Backbone", isOn: $showBackbone)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(size: 10))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(nsColor: appState.appTheme.panelBackground))
            Divider()

            switch selectedPanel {
            case .project: projectContent
            case .structure: structureContent
            case .results: resultsContent
            case .paper: paperContent
            }
        }
    }

    @ViewBuilder
    private var structureContent: some View {
        if isLoadingStructure {
            VStack(spacing: 12) {
                ProgressView()
                Text("Parsing structure off the main thread…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let structure {
            VStack(spacing: 0) {
                ProteinSceneView(scene: scene)
                Divider()
                structureMetadata(structure)
            }
        } else {
            scienceEmptyState
        }
    }

    private var scienceEmptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Protein Structure Preview")
                .font(.system(size: 18, weight: .semibold))
            Text(loadError ?? "Open a PDB or PDBx/mmCIF structure. AlphaFold 3 model outputs can be previewed directly.")
                .font(.system(size: 12))
                .foregroundColor(loadError == nil ? .secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                scienceCapability("PDB")
                scienceCapability("mmCIF")
                scienceCapability("AlphaFold")
            }
            Button("Choose Structure…") { openArtifact() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func structureMetadata(_ structure: ProteinStructureDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(structure.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(structure.format).font(.system(size: 9)).foregroundColor(.secondary)
            }
            HStack(spacing: 18) {
                metric("Atoms", "\(structure.sourceAtomCount)")
                metric("Residues", "\(structure.residueCount)")
                metric("Chains", "\(structure.chains.count)")
                metric("Ligands", "\(structure.ligandCount)")
                if let confidence = structure.meanConfidence { metric("Mean B / confidence", String(format: "%.1f", confidence)) }
            }
            if structure.wasDownsampled {
                Text("Rendering is sampled to protect UI performance; analysis uses the complete parsed structure.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: appState.appTheme.panelBackground))
    }

    private var projectContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.scienceProjectContext?.workspaceName ?? appState.workspaceFolder?.lastPathComponent ?? "Scientific Project")
                            .font(.system(size: 17, weight: .semibold))
                        Text(agent.isIndexingScienceProject ? "Indexing scientific artifacts…" : "Project-aware scientific context is ready")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if agent.isIndexingScienceProject { ProgressView().controlSize(.small) }
                    Button("Refresh Context") { agent.refreshScienceProjectContext() }
                        .buttonStyle(.bordered).controlSize(.small)
                }

                HStack(spacing: 8) {
                    projectMetric("Structures", agent.scienceProjectContext?.structures.count ?? 0)
                    projectMetric("Sequences", agent.scienceProjectContext?.sequences.count ?? 0)
                    projectMetric("Results", agent.scienceProjectContext?.results.count ?? 0)
                    projectMetric("Papers", agent.scienceProjectContext?.papers.count ?? 0)
                }

                Divider()
                Text("Scientific workflows").font(.system(size: 12, weight: .semibold))
                workflowButton("Analyze project evidence", "Inspect this scientific workspace and build an evidence map. Identify structures, sequences, datasets, figures, scripts and papers; separate observations from hypotheses and recommend the next reproducible analyses.")
                workflowButton("Compare wild type and mutation", "Find the wild-type and mutant structures or sequences in this project. Compare them using appropriate structural and sequence metrics, inspect confidence, and explain plausible functional consequences without overstating causality.")
                workflowButton("AlphaFold prediction workflow", "Inspect this project's sequence/MSA and AlphaFold-related files. Validate inputs, assess existing confidence outputs, and propose or execute only the locally configured reproducible next step.")
                workflowButton("Draft evidence-grounded paper", paperPrompt)

                Divider()
                section("Context + Memory + local RAG", "The Agent receives a compact index of this project on every Science request, retrieves relevant memory, then reads the exact artifacts it needs. Coordinates and large arrays stay local until explicitly used.")
                section("Scientific reasoning", "Responses must separate observations, inferences and hypotheses; retain provenance, units, uncertainty, controls, software/model versions and identifiers.")
            }
            .padding(22)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let url = activeURL, ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"].contains(activeExtension) {
            ImagePreviewView(url: url)
        } else if let url = activeURL, activeExtension == "pdf" {
            PDFPreviewView(url: url)
        } else if ["html", "htm"].contains(activeExtension), !currentText.isEmpty {
            GUIPreviewWebView(htmlContent: currentText)
        } else if let url = activeURL, ["svg"].contains(activeExtension) {
            UniversalFilePreview(url: url)
        } else if let url = activeURL {
            VStack(alignment: .leading, spacing: 10) {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold))
                Text("Scientific artifact preview").font(.system(size: 10)).foregroundColor(.secondary)
                ScrollView {
                    Text(currentText.isEmpty ? "Select a figure, PDF, HTML result, table, sequence, or report from the project tree." : String(currentText.prefix(100_000)))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
            }.padding(16)
        } else {
            sciencePanelEmpty("Results preview", "Select a figure, PDF, HTML result, table, or sequence from the project tree. It opens here without leaving Science Mode.")
        }
    }

    @ViewBuilder
    private var paperContent: some View {
        if activeExtension == "tex", !currentText.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text(activeURL?.lastPathComponent ?? "LaTeX Paper").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("Revise with Science Agent") { agent.enqueueMessage(paperPrompt) }
                        .buttonStyle(.bordered).controlSize(.small)
                }.padding(.horizontal, 12).frame(height: 36)
                Divider()
                LaTeXPreviewWebView(latexCode: latexPreviewText(currentText))
            }
        } else if let url = activeURL, activeExtension == "pdf" {
            PDFPreviewView(url: url)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                sciencePanelEmpty("Scientific paper workspace", "Select a .tex or PDF paper to preview it here, or ask the Science Agent to draft a reproducible LaTeX paper from project evidence, context and memory.")
                Button("Draft LaTeX Paper") { agent.enqueueMessage(paperPrompt) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }

    private var scientificDataContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Supported datasets", "FASTA/A3M sequences, CSV/TSV tables, JSON metadata, AlphaFold confidence files and structure coordinates.")
                section("Agent tools", "The Science Agent can inspect structures, summarize sequences and validate AlphaFold 3 input JSON locally before a run.")
                section("Privacy", "Scientific inspection tools operate on local workspace files. Data is sent to an AI provider only when included in an Agent request.")
                if let url = activeURL {
                    Divider()
                    Text(url.lastPathComponent).font(.system(size: 12, weight: .semibold))
                    Text(url.path).font(.system(size: 9)).foregroundColor(.secondary).textSelection(.enabled)
                }
            }
            .padding(22)
        }
    }

    private var protocolsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Reproducibility", "Ask the Agent to record inputs, model identifier, software version, random seeds, commands and generated artifacts.")
                section("AlphaFold 3", "Validate one alphafold3 JSON job per file, then run it in the environment configured by your project. Inference requires an appropriate GPU and authorized model parameters.")
                section("Medical AI", "MedGemma is treated as a developer research model. Outputs must be validated for the intended task and must not be presented as autonomous clinical advice.")
            }
            .padding(22)
        }
    }

    private func loadActiveArtifact() {
        guard isStructureFile, let url = activeURL else {
            structure = nil
            scene = SCNScene()
            loadError = nil
            return
        }
        isLoadingStructure = true
        loadError = nil
        let expectedPath = url.path
        Task {
            do {
                let document = try await Task.detached(priority: .userInitiated) { try ScienceService.loadStructure(at: url) }.value
                guard activeURL?.path == expectedPath else { return }
                structure = document
                scene = ScienceService.makeScene(for: document, showBackbone: showBackbone)
            } catch {
                structure = nil
                scene = SCNScene()
                loadError = error.localizedDescription
            }
            isLoadingStructure = false
        }
    }

    private func rebuildScene() {
        guard let structure else { return }
        scene = ScienceService.makeScene(for: structure, showBackbone: showBackbone)
    }

    private func openArtifact() {
        let panel = NSOpenPanel()
        panel.title = "Open Scientific Artifact"
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await appState.loadFile(url: url)
                appState.setEditorMode(.science)
                routeActiveArtifact()
                loadActiveArtifact()
            }
        }
    }

    private func routeActiveArtifact() {
        if ["pdb", "ent", "cif", "mmcif"].contains(activeExtension) { selectedPanel = .structure }
        else if ["tex", "bib"].contains(activeExtension) { selectedPanel = .paper }
        else if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "svg", "html", "htm", "pdf", "csv", "tsv", "json", "fasta", "fa", "faa", "fna", "a3m"].contains(activeExtension) { selectedPanel = .results }
    }

    private func startAlphaFoldWorkflow() {
        selectedPanel = .project
        agent.enqueueMessage("Inspect this scientific project's FASTA/A3M, AlphaFold inputs and existing prediction outputs. Validate the input locally, identify the exact configured pipeline, evaluate pLDDT/PAE/pTM/ipTM where available, and propose or run only a reproducible locally supported next step. Do not treat predictions as experimental evidence.")
    }

    private func startMedGemmaWorkflow() {
        if let model = scienceModels.first {
            appState.aiProvider = model.provider
            appState.aiModel = model.id
            appState.saveSettings()
            agent.enqueueMessage("Use the configured MedGemma scientific model to analyze the relevant project evidence. State the exact model, inputs, intended research task, uncertainty and validation requirements. Do not provide autonomous clinical diagnosis or treatment.")
        } else {
            agent.enqueueMessage("Prepare a MedGemma research workflow for this project. First inspect the available evidence and current model catalog, then state clearly that MedGemma is not currently exposed by the configured provider if unavailable. Specify the inputs, validation protocol and safety limits; do not substitute an unnamed model silently.")
        }
    }

    private func openInCells() {
        let path = activeURL?.path ?? appState.workspaceFolder?.path ?? ""
        appState.aiExportedCode = """
        # Science Mode → local Cell analysis
        from pathlib import Path

        artifact = Path(r"\(path)")
        print(f"Artifact: {artifact}")
        print(f"Exists: {artifact.exists()}")

        # Add a reproducible local analysis below. Record package versions,
        # random seeds, units, sample size, and output artifact paths.
        """
        appState.setEditorMode(.notebook)
    }

    private var paperPrompt: String {
        "Draft a publication-quality LaTeX paper grounded only in this project's indexed context, memory and artifacts. Inspect the relevant wild-type/mutant structures, sequences, figures, data and methods first. Explain the proposed protein malfunction by separating observations, quantitative results, inferences and hypotheses. Include methods, uncertainty, limitations, reproducibility details and only verified citations/identifiers. Write the result to a .tex file in the workspace and ensure it can be previewed in Science Mode."
    }

    private func workflowButton(_ title: String, _ prompt: String) -> some View {
        Button { agent.enqueueMessage(prompt) } label: {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.primary.opacity(0.035))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.14)))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }

    private func projectMetric(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count)").font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func sciencePanelEmpty(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func latexPreviewText(_ source: String) -> String {
        func replaceCommand(_ command: String, prefix: String, in text: String) -> String {
            guard let expression = try? NSRegularExpression(pattern: "\\\\\(command)\\{([^}]*)\\}") else { return text }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.stringByReplacingMatches(in: text, range: range, withTemplate: prefix + "$1")
        }
        let filtered = source.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return !value.hasPrefix("\\documentclass") && !value.hasPrefix("\\usepackage") &&
                value != "\\begin{document}" && value != "\\end{document}" && value != "\\maketitle"
        }.joined(separator: "\n")
        var result = replaceCommand("subsubsection", prefix: "#### ", in: filtered)
        result = replaceCommand("subsection", prefix: "### ", in: result)
        result = replaceCommand("section", prefix: "## ", in: result)
        result = replaceCommand("title", prefix: "# ", in: result)
        return result
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 11, weight: .medium, design: .monospaced))
            Text(label).font(.system(size: 8)).foregroundColor(.secondary)
        }
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scienceCapability(_ label: String) -> some View {
        Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.secondary).padding(.horizontal, 7).padding(.vertical, 4).background(Color.primary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private enum SciencePanel: String, CaseIterable, Identifiable {
    case project = "Project"
    case structure = "Structure"
    case results = "Results"
    case paper = "Paper"
    var id: String { rawValue }
}

private struct ProteinSceneView: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = .black
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
    }
}
