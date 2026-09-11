import SwiftUI

struct APIClientView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var service = APIClientService.shared
    @State private var method: HTTPMethod = .post
    @State private var url: String = "https://api.dotmini.net/v1/chat/completions"
    @State private var requestBody: String = "{\n  \"model\": \"gemini-2.5-flash\",\n  \"messages\": [\n    {\n      \"role\": \"user\",\n      \"content\": \"Hello\"\n    }\n  ],\n  \"max_tokens\": 4096,\n  \"stream\": false\n}"
    @State private var headers: [KeyValueItem] = [
        KeyValueItem(key: "Content-Type", value: "application/json"),
        KeyValueItem(key: "Authorization", value: "Bearer ")
    ]
    @State private var queryParams: [KeyValueItem] = []
    @State private var selectedReqTab: Int = 0
    @State private var selectedRespTab: Int = 0
    @State private var sidebarTab: Int = 0
    @State private var auth = APIAuth()
    @State private var showCurlSheet = false
    @State private var curlText = ""
    @State private var requestName = "New Request"
    @State private var showEnvSheet = false
    @State private var searchText = ""
    @State private var showCodeExportSheet = false
    @State private var selectedExportLanguage: CodeSnippetLanguage = .swift
    @State private var toastMessage: String? = nil

    @Environment(\.presentationMode) var presentationMode

    private var panelBg: Color {
        Color(nsColor: appState.appTheme.panelBackground)
    }

    private var editorBg: Color {
        Color(nsColor: appState.appTheme.editorBackground)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            HSplitView {
                sidebar.frame(minWidth: 240, maxWidth: 320)
                mainContent
            }
        }
        .background(editorBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCodeExportSheet) { codeExportSheet }
        .sheet(isPresented: $showCurlSheet) { curlSheet }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Studio Title & Native Badge
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text("API Studio")
                    .font(.system(size: 13, weight: .bold))
                Text("100% Native")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }

            if let msg = service.routeScanMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let toast = toastMessage {
                Text(toast)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Postman-Killer Action Bar
            HStack(spacing: 8) {
                // Feature 1: Scan Workspace Routes
                Button(action: {
                    Task {
                        let path = appState.workspaceFolder?.path ?? AgentToolBox.shared.workspaceRoot
                        _ = await service.scanWorkspaceRoutes(workspacePath: path)
                        sidebarTab = 1
                    }
                }) {
                    HStack(spacing: 5) {
                        if service.isScanningRoutes {
                            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 11))
                        }
                        Text("Scan Routes").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Scan FastAPI, Next.js, Express, Axum, Go routes in workspace")

                // Feature 2: Load Project .env
                Button(action: {
                    let path = appState.workspaceFolder?.path ?? AgentToolBox.shared.workspaceRoot
                    let count = service.loadProjectDotEnv(workspacePath: path)
                    toastMessage = "Loaded \(count) variables from .env"
                    sidebarTab = 2
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "key.fill").font(.system(size: 10))
                        Text("Load .env").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Load environment variables from project .env")

                // Feature 3: Code Snippet / SDK
                Button(action: {
                    showCodeExportSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "curlybraces").font(.system(size: 11))
                        Text("Code Snippet").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Generate modern Swift, TypeScript, Python, Rust or cURL code")

                Divider().frame(height: 14)

                // Return to Code Editor
                Button(action: {
                    appState.setEditorMode(.code)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Exit to Code").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Return to Code Editor")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(panelBg)
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Tabs: History / Collections / Env
            Picker("", selection: $sidebarTab) {
                Image(systemName: "clock").tag(0)
                Image(systemName: "folder").tag(1)
                Image(systemName: "gearshape.2").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()

            Group {
                switch sidebarTab {
                case 0: historyList
                case 1: collectionsList
                default: environmentsList
                }
            }
        }
        .background(panelBg)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    if service.history.isEmpty {
                        Text("No history yet")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                            .padding(.top, 24)
                    }
                    ForEach(service.history.filter { searchText.isEmpty || $0.request.url.localizedCaseInsensitiveContains(searchText) }) { entry in
                        Button(action: { loadHistoryEntry(entry) }) {
                            HStack(spacing: 8) {
                                Text(entry.request.method)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(HTTPMethod(rawValue: entry.request.method)?.color ?? .gray)
                                    .frame(width: 38, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shortURL(entry.request.url))
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        statusBadge(entry.status, size: 6)
                                        Text("\(entry.duration)ms")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            if !service.history.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button("Clear History") { service.clearHistory() }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                        .buttonStyle(.plain)
                    Spacer()
                }
                .padding(8)
            }
        }
    }

    private var collectionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(service.collections) { col in
                    DisclosureGroup(col.name) {
                        ForEach(col.requests) { req in
                            Button(action: { loadRequest(req) }) {
                                HStack(spacing: 6) {
                                    Text(req.method).font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(HTTPMethod(rawValue: req.method)?.color ?? .gray)
                                    Text(req.name).font(.system(size: 11)).lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                }
                Button(action: { service.collections.append(APICollection(name: "New Collection")) }) {
                    Label("New Collection", systemImage: "plus").font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
    }

    private var environmentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach($service.environments) { $env in
                    DisclosureGroup {
                        ForEach($env.variables) { $v in
                            HStack(spacing: 4) {
                                Toggle("", isOn: $v.isEnabled).labelsHidden().scaleEffect(0.7)
                                TextField("Key", text: $v.key).font(.system(size: 10, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Value", text: $v.value).font(.system(size: 10, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.vertical, 2)
                        }
                        Button(action: { env.variables.append(KeyValueItem()) }) {
                            Label("Add Variable", systemImage: "plus").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    } label: {
                        HStack {
                            Text(env.name).font(.system(size: 11, weight: .medium))
                            Spacer()
                            if service.activeEnvironment?.id == env.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(red: 0.22, green: 0.60, blue: 0.44))
                                    .font(.system(size: 10))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { service.activeEnvironment = env }
                    }
                    .padding(.horizontal, 8)
                }
                Button(action: { service.environments.append(APIEnvironment(name: "New Env")) }) {
                    Label("New Environment", systemImage: "plus").font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            requestBar
            Divider()
            HSplitView {
                requestPanel.frame(minHeight: 200)
                responsePanel.frame(minHeight: 200)
            }
        }
        .background(editorBg)
    }

    // MARK: - Request Bar
    private var requestBar: some View {
        HStack(spacing: 8) {
            // Method picker
            Picker("", selection: $method) {
                ForEach(HTTPMethod.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .frame(width: 90)
            .labelsHidden()

            // URL Field
            TextField("Enter URL or paste cURL", text: $url)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .onSubmit { sendRequest() }

            // Send
            Button(action: sendRequest) {
                HStack(spacing: 6) {
                    if service.isLoading {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 10))
                    }
                    Text("Send").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading || url.isEmpty)

            // Save / Menu
            Menu {
                Button("Save to Collection") {
                    let req = buildRequest()
                    service.saveToCollection(req)
                }
                Button("Export cURL") {
                    curlText = service.exportCURL(buildRequest())
                    showCurlSheet = true
                }
                Button("Import cURL") { showCurlSheet = true; curlText = "" }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(panelBg)
        .sheet(isPresented: $showCurlSheet) { curlSheet }
    }

    // MARK: - Request Panel
    private var requestPanel: some View {
        VStack(spacing: 0) {
            // Tabs
            HStack(spacing: 4) {
                reqTabBtn("Body", tab: 0)
                reqTabBtn("Headers", tab: 1)
                reqTabBtn("Params", tab: 2)
                reqTabBtn("Auth", tab: 3)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(panelBg.opacity(0.5))

            Divider()

            Group {
                switch selectedReqTab {
                case 0: bodyEditor
                case 1: headersEditor
                case 2: paramsEditor
                default: authEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reqTabBtn(_ title: String, tab: Int) -> some View {
        Button(action: { selectedReqTab = tab }) {
            Text(title)
                .font(.system(size: 11, weight: selectedReqTab == tab ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedReqTab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                .foregroundColor(selectedReqTab == tab ? .accentColor : .secondary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: Binding(get: { headers.first(where: { $0.key == "Content-Type" })?.value ?? "application/json" }, set: { v in
                    if let i = headers.firstIndex(where: { $0.key == "Content-Type" }) { headers[i].value = v }
                    else { headers.append(KeyValueItem(key: "Content-Type", value: v)) }
                })) {
                    Text("JSON").tag("application/json")
                    Text("XML").tag("application/xml")
                    Text("Text").tag("text/plain")
                    Text("Form").tag("application/x-www-form-urlencoded")
                }
                .frame(width: 100)
                .padding(6)
                Spacer()
            }
            TextEditor(text: $requestBody)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(editorBg)
                .onChange(of: requestBody, perform: { newValue in
                    let fixed = newValue
                        .replacingOccurrences(of: "“", with: "\"")
                        .replacingOccurrences(of: "”", with: "\"")
                        .replacingOccurrences(of: "‘", with: "'")
                        .replacingOccurrences(of: "’", with: "'")
                    if fixed != newValue {
                        requestBody = fixed
                    }
                })
        }
    }

    private var headersEditor: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($headers) { $item in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $item.isEnabled).labelsHidden().scaleEffect(0.7)
                            TextField("Key", text: $item.key)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            TextField("Value", text: $item.value)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            Button(action: { headers.removeAll { $0.id == item.id } }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            HStack {
                Button(action: { headers.append(KeyValueItem()) }) {
                    Label("Add Header", systemImage: "plus").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(8)
        }
    }

    private var paramsEditor: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($queryParams) { $p in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $p.isEnabled).labelsHidden().scaleEffect(0.7)
                            TextField("Key", text: $p.key)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            TextField("Value", text: $p.value)
                                .font(.system(size: 11, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            Button(action: { queryParams.removeAll { $0.id == p.id } }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            HStack {
                Button(action: { queryParams.append(KeyValueItem()) }) {
                    Label("Add Param", systemImage: "plus").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(8)
        }
    }

    private var authEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $auth.type) {
                ForEach(APIAuthType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 220)
            .padding(.top, 8)

            switch auth.type {
            case .bearer:
                HStack {
                    Text("Token").font(.system(size: 11)).frame(width: 50)
                    TextField("Bearer token", text: $auth.bearerToken).textFieldStyle(.roundedBorder)
                }
            case .basic:
                HStack {
                    Text("User").font(.system(size: 11)).frame(width: 50)
                    TextField("Username", text: $auth.basicUser).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Pass").font(.system(size: 11)).frame(width: 50)
                    SecureField("Password", text: $auth.basicPassword).textFieldStyle(.roundedBorder)
                }
            case .apiKey:
                HStack {
                    Text("Key").font(.system(size: 11)).frame(width: 50)
                    TextField("Header name", text: $auth.apiKeyName).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Value").font(.system(size: 11)).frame(width: 50)
                    TextField("API key value", text: $auth.apiKeyValue).textFieldStyle(.roundedBorder)
                }
                Picker("In", selection: $auth.apiKeyIn) {
                    Text("Header").tag("header")
                    Text("Query").tag("query")
                }.frame(width: 180)
            case .none:
                Text("No authentication required")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            Spacer()
        }
        .padding(12)
    }

    // MARK: - Response Panel
    private var responsePanel: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack(spacing: 10) {
                Text("Response")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if service.isLoading {
                    ProgressView(value: service.requestProgress).frame(width: 70)
                }
                if let r = service.lastResponse {
                    statusBadge(r.status, size: 8)
                    Text(r.statusText).font(.system(size: 11, weight: .semibold)).foregroundColor(r.statusColor)
                    Text("\(r.duration_ms)ms").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    Text(formatBytes(r.bodySize)).font(.system(size: 10)).foregroundColor(.secondary)
                    Button(action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.body, forType: .string) }) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Body")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(panelBg.opacity(0.7))

            // Response Tabs
            HStack(spacing: 4) {
                respTabBtn("Body", tab: 0)
                respTabBtn("Headers", tab: 1)
                respTabBtn("Raw", tab: 2)
                respTabBtn("AI Tests (\(service.activeTestAssertions.count))", tab: 3)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(panelBg.opacity(0.3))

            Divider()

            Group {
                if let r = service.lastResponse {
                    switch selectedRespTab {
                    case 0: responseBodyView(r)
                    case 1: responseHeadersView(r)
                    case 2: responseRawView(r)
                    default: responseAITestsView(r)
                    }
                } else if let err = service.error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundColor(Color(red: 0.82, green: 0.32, blue: 0.32))
                        Text(err).font(.system(size: 11)).foregroundColor(Color(red: 0.82, green: 0.32, blue: 0.32)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedRespTab == 3 {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor.opacity(0.4))
                        Text("No tests executed yet")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Send any request to auto-verify status, SLA latency, schema & headers")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.message")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("Send a request to see the response")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func respTabBtn(_ title: String, tab: Int) -> some View {
        Button(action: { selectedRespTab = tab }) {
            Text(title)
                .font(.system(size: 11, weight: selectedRespTab == tab ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedRespTab == tab ? Color.accentColor.opacity(0.14) : Color.clear)
                .foregroundColor(selectedRespTab == tab ? .accentColor : .secondary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private func responseBodyView(_ r: APIResponse) -> some View {
        ScrollView {
            Text(r.formattedBody)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(editorBg)
    }

    // MARK: - AI Test Assertions View
    private func responseAITestsView(_ r: APIResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                let passCount = service.activeTestAssertions.filter { $0.passed }.count
                let totalCount = service.activeTestAssertions.count
                
                HStack(spacing: 6) {
                    Image(systemName: passCount == totalCount ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(passCount == totalCount ? Color(red: 0.22, green: 0.60, blue: 0.44) : Color(red: 0.85, green: 0.55, blue: 0.20))
                    Text("AI Contract & SLA Verification: \(passCount)/\(totalCount) Passed")
                        .font(.system(size: 12, weight: .bold))
                }
                
                Spacer()
                
                Button(action: {
                    let req = buildRequest()
                    _ = service.generateAITestSuite(for: req, response: r)
                }) {
                    Label("Re-run Tests", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(service.activeTestAssertions) { assertion in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: assertion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(assertion.passed ? Color(red: 0.22, green: 0.60, blue: 0.44) : Color(red: 0.82, green: 0.32, blue: 0.32))
                                .font(.system(size: 13))
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(assertion.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(assertion.details)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(assertion.passed ? "PASS" : "FAIL")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(assertion.passed ? Color(red: 0.22, green: 0.60, blue: 0.44).opacity(0.15) : Color(red: 0.82, green: 0.32, blue: 0.32).opacity(0.15))
                                .foregroundColor(assertion.passed ? Color(red: 0.22, green: 0.60, blue: 0.44) : Color(red: 0.82, green: 0.32, blue: 0.32))
                                .cornerRadius(4)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(6)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(editorBg)
    }

    // MARK: - Code Snippet Sheet
    private var codeExportSheet: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "curlybraces")
                        .foregroundColor(.accentColor)
                    Text("Generate Code & SDK").font(.headline)
                }
                Spacer()
                Picker("", selection: $selectedExportLanguage) {
                    ForEach(CodeSnippetLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .frame(width: 190)
            }
            
            let code = service.generateCodeSnippet(for: buildRequest(), language: selectedExportLanguage)
            
            ScrollView {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .frame(height: 280)
            
            HStack {
                Button("Close") { showCodeExportSheet = false }
                Spacer()
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    showCodeExportSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private func responseHeadersView(_ r: APIResponse) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(r.header_map.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Text(value)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
            }
            .padding(6)
        }
        .background(editorBg)
    }

    private func responseRawView(_ r: APIResponse) -> some View {
        ScrollView {
            Text(r.body)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(editorBg)
    }

    // MARK: - cURL Sheet
    private var curlSheet: some View {
        VStack(spacing: 12) {
            Text(curlText.isEmpty ? "Import cURL" : "Export cURL").font(.headline)
            TextEditor(text: $curlText).font(.system(size: 11, design: .monospaced)).frame(height: 200)
            HStack {
                Button("Cancel") { showCurlSheet = false }
                Spacer()
                if curlText.isEmpty || !curlText.contains("curl") {
                    Button("Paste & Import") {
                        if let clip = NSPasteboard.general.string(forType: .string) { curlText = clip }
                    }
                } else {
                    Button("Import") {
                        if let req = service.importCURL(curlText) {
                            url = req.url
                            method = HTTPMethod(rawValue: req.method) ?? .get
                            requestBody = req.body ?? ""
                            auth = req.auth
                        }
                        showCurlSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !curlText.isEmpty && curlText.contains("curl") {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(curlText, forType: .string)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    // MARK: - Actions
    private func sendRequest() {
        Task {
            let req = buildRequest()
            _ = try? await service.execute(req)
        }
    }

    private func buildRequest() -> APIRequest {
        var headerDict: [String: String] = [:]
        for item in headers where item.isEnabled && !item.key.isEmpty { headerDict[item.key] = item.value }
        return APIRequest(name: requestName, method: method.rawValue, url: url, headers: headerDict,
                          body: method == .get ? nil : requestBody, auth: auth,
                          queryParams: queryParams.filter { $0.isEnabled })
    }

    private func loadHistoryEntry(_ entry: APIHistoryEntry) {
        url = entry.request.url
        method = HTTPMethod(rawValue: entry.request.method) ?? .get
        requestBody = entry.request.body ?? ""
        auth = entry.request.auth
    }

    private func loadRequest(_ req: APIRequest) {
        url = req.url
        method = HTTPMethod(rawValue: req.method) ?? .get
        requestBody = req.body ?? ""
        auth = req.auth
        requestName = req.name
    }

    // MARK: - Helpers
    private func statusBadge(_ code: Int, size: CGFloat) -> some View {
        Circle().fill(code >= 200 && code < 300 ? Color(red: 0.22, green: 0.60, blue: 0.44) : code >= 400 ? Color(red: 0.82, green: 0.32, blue: 0.32) : Color(red: 0.85, green: 0.55, blue: 0.20))
            .frame(width: size, height: size)
    }

    private func shortURL(_ u: String) -> String {
        u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    private func formatBytes(_ b: Int) -> String {
        b < 1024 ? "\(b) B" : b < 1048576 ? "\(b/1024) KB" : "\(b/1048576) MB"
    }
}
