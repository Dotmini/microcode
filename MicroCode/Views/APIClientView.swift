import SwiftUI

struct APIClientView: View {
    @StateObject private var service = APIClientService.shared
    @State private var method: HTTPMethod = .get
    @State private var url: String = "https://httpbin.org/get"
    @State private var requestBody: String = "{\n  \"key\": \"value\"\n}"
    @State private var headers: [KeyValueItem] = [KeyValueItem(key: "Content-Type", value: "application/json")]
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

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 220, maxWidth: 280)
            mainContent
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
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
            .pickerStyle(.segmented).padding(8)

            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 8).font(.system(size: 11))

            Divider().padding(.top, 4)

            switch sidebarTab {
            case 0: historyList
            case 1: collectionsList
            default: environmentsList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var historyList: some View {
        List {
            if service.history.isEmpty {
                Text("No history yet").foregroundColor(.secondary).font(.system(size: 11))
            }
            ForEach(service.history.filter { searchText.isEmpty || $0.request.url.localizedCaseInsensitiveContains(searchText) }) { entry in
                Button(action: { loadHistoryEntry(entry) }) {
                    HStack(spacing: 6) {
                        Text(entry.request.method).font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(HTTPMethod(rawValue: entry.request.method)?.color ?? .gray)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortURL(entry.request.url)).font(.system(size: 11)).lineLimit(1)
                            HStack(spacing: 4) {
                                statusBadge(entry.status, size: 8)
                                Text("\(entry.duration)ms").font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            if !service.history.isEmpty {
                Button("Clear History") { service.clearHistory() }
                    .font(.system(size: 10)).padding(6)
            }
        }
    }

    private var collectionsList: some View {
        List {
            ForEach(service.collections) { col in
                DisclosureGroup(col.name) {
                    ForEach(col.requests) { req in
                        Button(action: { loadRequest(req) }) {
                            HStack(spacing: 4) {
                                Text(req.method).font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(HTTPMethod(rawValue: req.method)?.color ?? .gray)
                                Text(req.name).font(.system(size: 11)).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button(action: { service.collections.append(APICollection(name: "New Collection")) }) {
                Label("New Collection", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain).padding(.top, 4)
        }.listStyle(.sidebar)
    }

    private var environmentsList: some View {
        List {
            ForEach($service.environments) { $env in
                DisclosureGroup {
                    ForEach($env.variables) { $v in
                        HStack(spacing: 4) {
                            Toggle("", isOn: $v.isEnabled).labelsHidden().scaleEffect(0.7)
                            TextField("Key", text: $v.key).font(.system(size: 10, design: .monospaced))
                            TextField("Value", text: $v.value).font(.system(size: 10, design: .monospaced))
                        }
                    }
                    Button(action: { env.variables.append(KeyValueItem()) }) {
                        Label("Add Variable", systemImage: "plus").font(.system(size: 10))
                    }.buttonStyle(.plain)
                } label: {
                    HStack {
                        Text(env.name).font(.system(size: 11, weight: .medium))
                        Spacer()
                        if service.activeEnvironment?.id == env.id {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 10))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { service.activeEnvironment = env }
                }
            }
            Button(action: { service.environments.append(APIEnvironment(name: "New Env")) }) {
                Label("New Environment", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain)
        }.listStyle(.sidebar)
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            requestBar
            Divider()
            HSplitView {
                requestPanel.frame(minHeight: 200)
                responsePanel
            }
        }
    }

    // MARK: - Request Bar
    private var requestBar: some View {
        HStack(spacing: 8) {
            // Method picker
            Picker("", selection: $method) {
                ForEach(HTTPMethod.allCases) { m in
                    Text(m.rawValue).foregroundColor(m.color).tag(m)
                }
            }.frame(width: 100)

            // URL Field
            TextField("Enter URL or paste cURL", text: $url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit { sendRequest() }

            // Send
            Button(action: sendRequest) {
                HStack(spacing: 4) {
                    if service.isLoading {
                        ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 11))
                    }
                    Text("Send").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.blue)
            .disabled(service.isLoading || url.isEmpty)

            // Save
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
                Image(systemName: "square.and.arrow.down").font(.system(size: 12))
            }.menuStyle(.borderlessButton).frame(width: 24)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showCurlSheet) { curlSheet }
    }

    // MARK: - Request Panel
    private var requestPanel: some View {
        VStack(spacing: 0) {
            // Tabs
            HStack(spacing: 0) {
                reqTabBtn("Body", tab: 0)
                reqTabBtn("Headers", tab: 1)
                reqTabBtn("Params", tab: 2)
                reqTabBtn("Auth", tab: 3)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 6)

            Divider().padding(.top, 4)

            switch selectedReqTab {
            case 0: bodyEditor
            case 1: headersEditor
            case 2: paramsEditor
            default: authEditor
            }
        }
    }

    private func reqTabBtn(_ title: String, tab: Int) -> some View {
        Button(action: { selectedReqTab = tab }) {
            Text(title).font(.system(size: 11, weight: selectedReqTab == tab ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(selectedReqTab == tab ? Color.blue.opacity(0.12) : Color.clear)
                .cornerRadius(6)
        }.buttonStyle(.plain)
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
                }.frame(width: 120).padding(6)
                Spacer()
            }
            TextEditor(text: $requestBody)
                .font(.system(size: 12, design: .monospaced))
                .padding(4)
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
            // Header row
            HStack(spacing: 4) {
                Text("Key").font(.system(size: 9, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Value").font(.system(size: 9, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("").frame(width: 24)
            }.padding(.horizontal, 10).padding(.vertical, 4).background(Color.secondary.opacity(0.06))

            List {
                ForEach($headers) { $item in
                    HStack(spacing: 4) {
                        Toggle("", isOn: $item.isEnabled).labelsHidden().scaleEffect(0.7)
                        TextField("Key", text: $item.key).font(.system(size: 11, design: .monospaced))
                        TextField("Value", text: $item.value).font(.system(size: 11, design: .monospaced))
                        Button(action: { headers.removeAll { $0.id == item.id } }) {
                            Image(systemName: "xmark.circle").font(.system(size: 10)).foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }.listStyle(.plain)

            Button(action: { headers.append(KeyValueItem()) }) {
                Label("Add Header", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain).padding(6)
        }
    }

    private var paramsEditor: some View {
        VStack(spacing: 0) {
            List {
                ForEach($queryParams) { $p in
                    HStack(spacing: 4) {
                        Toggle("", isOn: $p.isEnabled).labelsHidden().scaleEffect(0.7)
                        TextField("Key", text: $p.key).font(.system(size: 11, design: .monospaced))
                        TextField("Value", text: $p.value).font(.system(size: 11, design: .monospaced))
                        Button(action: { queryParams.removeAll { $0.id == p.id } }) {
                            Image(systemName: "xmark.circle").font(.system(size: 10)).foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }.listStyle(.plain)
            Button(action: { queryParams.append(KeyValueItem()) }) {
                Label("Add Param", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain).padding(6)
        }
    }

    private var authEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $auth.type) {
                ForEach(APIAuthType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 250).padding(.top, 8)

            switch auth.type {
            case .bearer:
                HStack { Text("Token").frame(width: 60); TextField("Bearer token", text: $auth.bearerToken).textFieldStyle(.roundedBorder) }
            case .basic:
                HStack { Text("User").frame(width: 60); TextField("Username", text: $auth.basicUser).textFieldStyle(.roundedBorder) }
                HStack { Text("Pass").frame(width: 60); SecureField("Password", text: $auth.basicPassword).textFieldStyle(.roundedBorder) }
            case .apiKey:
                HStack { Text("Key").frame(width: 60); TextField("Header name", text: $auth.apiKeyName).textFieldStyle(.roundedBorder) }
                HStack { Text("Value").frame(width: 60); TextField("API key value", text: $auth.apiKeyValue).textFieldStyle(.roundedBorder) }
                Picker("In", selection: $auth.apiKeyIn) { Text("Header").tag("header"); Text("Query").tag("query") }.frame(width: 200)
            case .none: Text("No authentication").foregroundColor(.secondary).font(.system(size: 12))
            }
            Spacer()
        }.padding(.horizontal, 12)
    }

    // MARK: - Response Panel
    private var responsePanel: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack(spacing: 12) {
                Text("Response").font(.system(size: 12, weight: .semibold))
                Spacer()
                if service.isLoading {
                    ProgressView(value: service.requestProgress).frame(width: 80)
                }
                if let r = service.lastResponse {
                    statusBadge(r.status, size: 11)
                    Text(r.statusText).font(.system(size: 11)).foregroundColor(r.statusColor)
                    Text("\(r.duration_ms)ms").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    Text(formatBytes(r.bodySize)).font(.system(size: 10)).foregroundColor(.secondary)
                    Button(action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.body, forType: .string) }) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                    }.buttonStyle(.plain).help("Copy")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            // Response Tabs
            HStack(spacing: 0) {
                respTabBtn("Body", tab: 0)
                respTabBtn("Headers", tab: 1)
                respTabBtn("Raw", tab: 2)
                Spacer()
            }.padding(.horizontal, 8).padding(.top, 4)

            Divider().padding(.top, 4)

            if let r = service.lastResponse {
                switch selectedRespTab {
                case 0: responseBodyView(r)
                case 1: responseHeadersView(r)
                default: responseRawView(r)
                }
            } else if let err = service.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundColor(.red)
                    Text(err).font(.system(size: 12)).foregroundColor(.red).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.message").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                    Text("Send a request to see the response").font(.system(size: 12)).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func respTabBtn(_ title: String, tab: Int) -> some View {
        Button(action: { selectedRespTab = tab }) {
            Text(title).font(.system(size: 11, weight: selectedRespTab == tab ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(selectedRespTab == tab ? Color.green.opacity(0.12) : Color.clear)
                .cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func responseBodyView(_ r: APIResponse) -> some View {
        ScrollView {
            Text(r.formattedBody)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func responseHeadersView(_ r: APIResponse) -> some View {
        List {
            ForEach(r.header_map.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.blue)
                    Spacer()
                    Text(value).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(2)
                }
            }
        }.listStyle(.plain)
    }

    private func responseRawView(_ r: APIResponse) -> some View {
        ScrollView {
            Text(r.body).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            url = req.url; method = HTTPMethod(rawValue: req.method) ?? .get
                            requestBody = req.body ?? ""; auth = req.auth
                        }
                        showCurlSheet = false
                    }.buttonStyle(.borderedProminent)
                }
                if !curlText.isEmpty && curlText.contains("curl") {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(curlText, forType: .string) }
                }
            }
        }.padding(20).frame(width: 500)
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
        url = req.url; method = HTTPMethod(rawValue: req.method) ?? .get
        requestBody = req.body ?? ""; auth = req.auth; requestName = req.name
    }

    // MARK: - Helpers
    private func statusBadge(_ code: Int, size: CGFloat) -> some View {
        Circle().fill(code >= 200 && code < 300 ? Color.green : code >= 400 ? Color.red : Color.orange)
            .frame(width: size, height: size)
    }

    private func shortURL(_ u: String) -> String {
        u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    private func formatBytes(_ b: Int) -> String {
        b < 1024 ? "\(b) B" : b < 1048576 ? "\(b/1024) KB" : "\(b/1048576) MB"
    }
}
