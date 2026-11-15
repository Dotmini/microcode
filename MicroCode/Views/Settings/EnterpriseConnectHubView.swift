//
//  EnterpriseConnectHubView.swift
//  MicroCode
//
//  Zero-Config Enterprise & Cloud AI Connect Hub:
//  - Pure Monochrome / Graphite executive aesthetic (zero garish colors or generic AI icons)
//  - Authentic Official Brand Logos (Google Cloud, Gemini, Claude, OpenAI, AWS, Microsoft Azure, Dotmini)
//  - Automatic SSO detection, smart active GCP project resolution, and 100% live upstream model catalog
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EnterpriseConnectHubView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared

    var onSelectModel: ((String, String) -> Void)?

    @State private var connectingDialect: EnterpriseProviderDialect? = nil
    @State private var expandedSetupDialect: EnterpriseProviderDialect? = nil
    @State private var inlineCredentialInput: String = ""
    @State private var modelSearchQuery: String = ""
    @State private var modelFamilyFilter: String = "all"
    @State private var showAdvancedSection: Bool = false
    @State private var customModelDraft: String = ""
    @State private var showHeadersSheet: Bool = false
    @State private var showPoliciesSheet: Bool = false
    @State private var copiedTeamLinkFeedback: Bool = false

    init(onSelectModel: ((String, String) -> Void)? = nil) {
        self.onSelectModel = onSelectModel
    }

    private static let primaryProviders: [EnterpriseProviderDialect] = [
        .vertexGemini,
        .awsBedrock,
        .azureOpenAI,
        .dotminiEnterprise,
        .openaiGateway
    ]

    private var activeProfile: EnterpriseAPIProfile? {
        enterprise.activeProfile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providersConnectCard
            liveModelSelectorCard
            advancedConfigurationCard
        }
        .task {
            await enterprise.autoBootstrapZeroConfigIfNeeded()
            if let prof = enterprise.activeProfile, !prof.defaultModel.isEmpty {
                onSelectModel?(prof.dialect.brandIconKey, prof.defaultModel)
            }
        }
        .sheet(isPresented: $showHeadersSheet) {
            if let prof = activeProfile {
                EnterpriseHeadersAndProxySheet(profileId: prof.id)
            }
        }
        .sheet(isPresented: $showPoliciesSheet) {
            EnterpriseComplianceSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - 1. Zero-Config Cloud & Enterprise Providers

    private var providersConnectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Cloud & Enterprise Providers")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if enterprise.isVerifying || enterprise.cliStatus.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Syncing live catalog…")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            await enterprise.detectLocalCLIs()
                            if let prof = activeProfile {
                                _ = await enterprise.discoverModelsAndVerify(profileId: prof.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .medium))
                            Text("Sync")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Re-scan local SSO sessions and refresh live models")
                }
            }

            Text("Click Connect — credentials, active cloud project, optimal endpoint, and live models are configured automatically.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                ForEach(Self.primaryProviders) { dialect in
                    providerRow(for: dialect)
                }
            }
        }
        .padding(14)
        .background(cardSurface)
    }

    @ViewBuilder
    private func providerRow(for dialect: EnterpriseProviderDialect) -> some View {
        let matchedProfile = enterprise.profiles.first(where: { $0.dialect == dialect })
        let isSelected = activeProfile?.dialect == dialect
        let isVerified = (matchedProfile?.isVerified == true) && !(matchedProfile?.discoveredModels.isEmpty ?? true)
        let isBusy = (connectingDialect == dialect) || (isSelected && enterprise.isVerifying)
        let isSetupExpanded = expandedSetupDialect == dialect

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                AIProviderBrandIcon(provider: dialect.brandIconKey, size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(providerDisplayTitle(for: dialect))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)

                        if dialect == .vertexGemini {
                            HStack(spacing: 3) {
                                AIProviderBrandIcon(provider: "gemini", size: 11)
                                AIProviderBrandIcon(provider: "claude", size: 11)
                            }
                            .opacity(0.85)
                        }
                    }

                    HStack(spacing: 5) {
                        Circle()
                            .fill(providerDotColor(for: dialect, isVerified: isVerified))
                            .frame(width: 5.5, height: 5.5)
                        Text(providerStatusSubtitle(for: dialect, profile: matchedProfile))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if dialect == .openaiGateway || !canZeroClickSSO(for: dialect, profile: matchedProfile) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if expandedSetupDialect == dialect {
                                expandedSetupDialect = nil
                            } else {
                                expandedSetupDialect = dialect
                                inlineCredentialInput = ""
                            }
                        }
                    } label: {
                        Text(isSetupExpanded ? "Close" : "Configure")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    handleOneClickConnect(dialect: dialect, existingProfile: matchedProfile)
                } label: {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        } else if isSelected && isVerified {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        Text(isBusy ? "Connecting…" : (isSelected && isVerified ? "Connected" : "Connect"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(isSelected && isVerified ? .primary : Color(nsColor: .windowBackgroundColor))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected && isVerified ? Color.primary.opacity(0.09) : Color.primary.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(isSelected && isVerified ? 0.18 : 0.0), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let prof = matchedProfile {
                    enterprise.activateEnterpriseSelection(profileId: prof.id, modelId: prof.defaultModel)
                    if !prof.defaultModel.isEmpty {
                        onSelectModel?(prof.dialect.brandIconKey, prof.defaultModel)
                    }
                    if prof.discoveredModels.isEmpty && !enterprise.isVerifying {
                        Task { _ = await enterprise.discoverModelsAndVerify(profileId: prof.id) }
                    }
                }
            }

            if isSetupExpanded {
                inlineCredentialBox(for: dialect)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.065) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.primary.opacity(0.20) : Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func inlineCredentialBox(for dialect: EnterpriseProviderDialect) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().opacity(0.5)

            HStack(spacing: 8) {
                TextField(inlinePlaceholder(for: dialect), text: $inlineCredentialInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        submitInlineConnect(for: dialect)
                    }

                if dialect == .vertexGemini || dialect == .openaiGateway {
                    Button("Import .json") {
                        importFileForProvider(dialect: dialect)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let cliCmd = cliLoginCommand(for: dialect) {
                    Button("CLI Sign-In") {
                        enterprise.triggerInteractiveCLILogin(command: cliCmd)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Run `\(cliCmd)` in Terminal")
                }

                Button("Connect") {
                    submitInlineConnect(for: dialect)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(inlineCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 2. Real Live Model Selector (Zero Mock)

    private var liveModelSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let prof = activeProfile {
                let liveModels = prof.availableModels
                let filteredModels = filteredLiveModels(from: liveModels)

                HStack(spacing: 8) {
                    AIProviderBrandIcon(provider: prof.dialect.brandIconKey, size: 16)

                    Text("Live Models")
                        .font(.system(size: 12.5, weight: .semibold))

                    if !liveModels.isEmpty {
                        Text("\(liveModels.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }

                    Spacer()

                    if !prof.defaultModel.isEmpty {
                        HStack(spacing: 5) {
                            AIProviderBrandIcon(
                                provider: AIProviderBrandIcon.modelBrandKey(for: prof.defaultModel, fallback: prof.dialect.brandIconKey),
                                size: 12
                            )
                            Text(prof.defaultModel)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }

                    Button {
                        Task {
                            _ = await enterprise.discoverModelsAndVerify(profileId: prof.id)
                            if let updated = enterprise.profiles.first(where: { $0.id == prof.id }), !updated.defaultModel.isEmpty {
                                onSelectModel?(updated.dialect.brandIconKey, updated.defaultModel)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(enterprise.isVerifying)
                    .help("Fetch latest live models from upstream API")
                }

                // Inline Smart GCP Project Helper (shown automatically when Vertex AI project needs attention or has multiple active projects)
                if prof.dialect == .vertexGemini {
                    gcpSmartProjectBar(for: prof)
                } else if !prof.lastStatusMessage.isEmpty && !prof.isVerified {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(prof.lastStatusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.035)))
                }

                if liveModels.isEmpty {
                    HStack(spacing: 8) {
                        if enterprise.isVerifying {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching live models directly from \(providerDisplayTitle(for: prof.dialect))…")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "tray")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("No live models fetched yet. Click Connect on a provider above to fetch the real-time catalog.")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.025)))
                } else {
                    // Search + Family Filter Bar
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            TextField("Search \(liveModels.count) live models…", text: $modelSearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                            if !modelSearchQuery.isEmpty {
                                Button {
                                    modelSearchQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                        let hasGemini = liveModels.contains { $0.lowercased().contains("gemini") }
                        let hasClaude = liveModels.contains { $0.lowercased().contains("claude") }
                        if hasGemini && hasClaude {
                            familyFilterChip(id: "all", label: "All", brand: nil)
                            familyFilterChip(id: "gemini", label: "Gemini", brand: "gemini")
                            familyFilterChip(id: "claude", label: "Claude", brand: "claude")
                        }
                    }

                    // Clean Scrollable Live Model List
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredModels, id: \.self) { modelId in
                                let isActiveModel = (prof.defaultModel == modelId)
                                Button {
                                    enterprise.activateEnterpriseSelection(profileId: prof.id, modelId: modelId)
                                    onSelectModel?(prof.dialect.brandIconKey, modelId)
                                } label: {
                                    HStack(spacing: 9) {
                                        AIProviderBrandIcon(
                                            provider: AIProviderBrandIcon.modelBrandKey(for: modelId, fallback: prof.dialect.brandIconKey),
                                            size: 15
                                        )
                                        Text(modelId)
                                            .font(.system(size: 11.5, weight: isActiveModel ? .semibold : .regular, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        if let tier = subtleModelTierLabel(for: modelId) {
                                            Text(tier)
                                                .font(.system(size: 9.5, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Color.primary.opacity(0.045))
                                                .cornerRadius(4)
                                        }

                                        Image(systemName: isActiveModel ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(isActiveModel ? .primary : .secondary.opacity(0.35))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isActiveModel ? Color.primary.opacity(0.08) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                    }
                    .frame(minHeight: 150, maxHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .background(cardSurface)
    }

    @ViewBuilder
    private func gcpSmartProjectBar(for prof: EnterpriseAPIProfile) -> some View {
        let state = enterprise.gcpDiagnosticState
        let projects = enterprise.availableGCPProjects
        let orderedProjects: [String] = {
            var seen = Set<String>()
            var out: [String] = []
            for p in enterprise.readyGCPProjects where seen.insert(p).inserted { out.append(p) }
            if !prof.gcpProjectId.isEmpty && seen.insert(prof.gcpProjectId).inserted { out.append(prof.gcpProjectId) }
            for p in projects where seen.insert(p).inserted { out.append(p) }
            return out
        }()

        HStack(spacing: 8) {
            Text("GCP Project:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if !orderedProjects.isEmpty {
                Picker("", selection: Binding(
                    get: { prof.gcpProjectId },
                    set: { newProj in
                        var copy = prof
                        copy.gcpProjectId = newProj
                        enterprise.upsertProfile(copy, makeActive: true)
                        Task { _ = await enterprise.discoverModelsAndVerify(profileId: prof.id) }
                    }
                )) {
                    ForEach(orderedProjects, id: \.self) { pid in
                        let suffix = enterprise.readyGCPProjects.contains(pid) ? " (Vertex API Enabled)" : ""
                        Text("\(pid)\(suffix)").tag(pid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 260)
            } else {
                Text(prof.gcpProjectId.isEmpty ? "Auto-detecting…" : prof.gcpProjectId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer()

            if state == "billing_disabled" && !prof.gcpProjectId.isEmpty {
                Text("Billing inactive on project")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Button("Enable Billing") {
                    if let u = URL(string: "https://console.cloud.google.com/billing/linkedaccount?project=\(prof.gcpProjectId)") {
                        NSWorkspace.shared.open(u)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if state == "service_disabled" && !prof.gcpProjectId.isEmpty {
                Button("Enable Vertex AI API") {
                    Task { _ = await enterprise.enableVertexAIAPI(for: prof.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(enterprise.isVerifying)
            } else if state == "ready" {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 5, height: 5)
                    Text("Ready (\(prof.gcpLocation))")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder
    private func familyFilterChip(id: String, label: String, brand: String?) -> some View {
        let selected = modelFamilyFilter == id
        Button {
            modelFamilyFilter = id
        } label: {
            HStack(spacing: 4) {
                if let brand {
                    AIProviderBrandIcon(provider: brand, size: 11)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.11) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(selected ? 0.20 : 0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Collapsed Advanced Settings, Team Rollout & Security

    private var advancedConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showAdvancedSection.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAdvancedSection ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Text("Advanced Settings, Team Rollout & Security Policies")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Text("ZDR · DLP · Proxy")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvancedSection, let prof = activeProfile {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 12) {
                    // Region / Endpoint / Auth Overrides
                    HStack(spacing: 12) {
                        if prof.dialect == .vertexGemini || prof.dialect == .geminiEnterpriseAgentspace {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Google Cloud Project ID")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("my-gcp-project-id", text: binding(for: prof.id, keyPath: \.gcpProjectId))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Endpoint Region")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                Picker("", selection: binding(for: prof.id, keyPath: \.gcpLocation)) {
                                    ForEach(EnterpriseAIAuthService.supportedVertexLocations, id: \.id) { loc in
                                        Text(loc.label).tag(loc.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        } else if prof.dialect == .awsBedrock {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AWS Region")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("ap-southeast-1", text: binding(for: prof.id, keyPath: \.awsRegion))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AWS Profile")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("default", text: binding(for: prof.id, keyPath: \.awsProfileName))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                        } else if prof.dialect == .azureOpenAI {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Azure Resource / Endpoint")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("resource-name or https://…", text: binding(for: prof.id, keyPath: \.azureResourceName))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Deployment Name")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("gpt-4.1", text: binding(for: prof.id, keyPath: \.azureDeploymentName))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gateway Base URL")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                TextField("https://llm-gateway.company.com/v1", text: binding(for: prof.id, keyPath: \.baseURL))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }
                        }
                    }

                    // Custom Deployment ID
                    HStack(spacing: 8) {
                        TextField("Add custom deployment or fine-tuned model ID…", text: $customModelDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Add Model") {
                            let clean = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !clean.isEmpty else { return }
                            var copy = prof
                            if !copy.customModels.contains(clean) {
                                copy.customModels.insert(clean, at: 0)
                            }
                            copy.defaultModel = clean
                            enterprise.upsertProfile(copy, makeActive: true)
                            enterprise.activateEnterpriseSelection(profileId: copy.id, modelId: clean)
                            onSelectModel?(copy.dialect.brandIconKey, clean)
                            customModelDraft = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Divider().opacity(0.4)

                    // Action Buttons: Team Share, Proxy/Headers, Security & DLP
                    HStack(spacing: 8) {
                        Button {
                            if let link = enterprise.exportTeamShareLink(for: prof.id) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link, forType: .string)
                                copiedTeamLinkFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedTeamLinkFeedback = false
                                }
                            }
                        } label: {
                            Label(copiedTeamLinkFeedback ? "Copied Link" : "Copy Team Link", systemImage: copiedTeamLinkFeedback ? "checkmark" : "link")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            _ = enterprise.exportTeamShareFileWithSavePanel(for: prof.id)
                        } label: {
                            Label("Export .json", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            showHeadersSheet = true
                        } label: {
                            Label("Headers & Proxy (\(prof.customHeaders.count))", systemImage: "slider.horizontal.3")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button {
                            showPoliciesSheet = true
                        } label: {
                            Label("Security & DLP Policies", systemImage: "lock.shield")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(cardSurface)
    }

    // MARK: - Helpers & Actions

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func providerDisplayTitle(for dialect: EnterpriseProviderDialect) -> String {
        switch dialect {
        case .vertexGemini: return "Google Cloud Vertex AI"
        case .awsBedrock: return "Amazon Bedrock (AWS)"
        case .azureOpenAI: return "Microsoft Azure AI"
        case .dotminiEnterprise: return "Dotmini Sovereign Cloud"
        case .openaiGateway: return "Custom Enterprise Gateway"
        case .anthropicGateway: return "Anthropic Enterprise Proxy"
        case .geminiEnterpriseAgentspace: return "Google Agentspace"
        }
    }

    private func canZeroClickSSO(for dialect: EnterpriseProviderDialect, profile: EnterpriseAPIProfile?) -> Bool {
        switch dialect {
        case .vertexGemini, .geminiEnterpriseAgentspace:
            return enterprise.cliStatus.isGcloudReady || enterprise.hasVertexServiceAccount || !(profile.map { enterprise.readPrimarySecret(for: $0.id) } ?? "").isEmpty
        case .awsBedrock:
            return enterprise.cliStatus.isAWSReady || !(profile.map { enterprise.readPrimarySecret(for: $0.id) } ?? "").isEmpty
        case .azureOpenAI:
            return (enterprise.cliStatus.isAzureReady && !(profile?.azureResourceName.isEmpty ?? true))
                || !(profile.map { enterprise.readPrimarySecret(for: $0.id) } ?? "").isEmpty
        case .dotminiEnterprise:
            return DotminiPlatformKeyService.shared.authorizationToken != nil
                || SupabaseAuthService.shared.accessToken != nil
                || !(profile.map { enterprise.readPrimarySecret(for: $0.id) } ?? "").isEmpty
        case .openaiGateway, .anthropicGateway:
            return !(profile?.baseURL.isEmpty ?? true) && !(profile.map { enterprise.readPrimarySecret(for: $0.id) } ?? "").isEmpty
        }
    }

    private func providerDotColor(for dialect: EnterpriseProviderDialect, isVerified: Bool) -> Color {
        if isVerified {
            return Color.primary.opacity(0.85)
        }
        if canZeroClickSSO(for: dialect, profile: enterprise.profiles.first(where: { $0.dialect == dialect })) {
            return Color.primary.opacity(0.45)
        }
        return Color.secondary.opacity(0.28)
    }

    private func providerStatusSubtitle(for dialect: EnterpriseProviderDialect, profile: EnterpriseAPIProfile?) -> String {
        if let profile, profile.isVerified, !profile.discoveredModels.isEmpty {
            switch dialect {
            case .vertexGemini:
                let projLabel = profile.gcpProjectId.isEmpty ? "global" : profile.gcpProjectId
                return "\(projLabel) · \(profile.discoveredModels.count) live models"
            case .awsBedrock:
                return "\(profile.awsRegion) · \(profile.discoveredModels.count) live models"
            default:
                return "\(profile.discoveredModels.count) live models ready"
            }
        }

        switch dialect {
        case .vertexGemini:
            if enterprise.cliStatus.isGcloudReady {
                let acct = enterprise.cliStatus.gcloudAccount.isEmpty ? "ADC Ready" : enterprise.cliStatus.gcloudAccount
                return "Google Cloud SSO detected (\(acct)) — 1-click ready"
            }
            return "Gemini & Claude on Vertex via Google Cloud SSO or Service Account"
        case .awsBedrock:
            if let first = enterprise.cliStatus.awsProfiles.first {
                return "AWS profile '\(first)' (\(enterprise.cliStatus.awsDefaultRegion)) detected"
            }
            return "Claude, Nova & DeepSeek via AWS SSO or Bedrock API Key"
        case .azureOpenAI:
            if enterprise.cliStatus.isAzureReady {
                return "Entra ID (\(enterprise.cliStatus.azAccount)) detected"
            }
            return "Azure OpenAI & Microsoft AI Foundry deployments"
        case .dotminiEnterprise:
            if let email = SupabaseAuthService.shared.session?.email {
                return "Signed in as \(email) · Zero Data Retention"
            }
            return "Sovereign multi-model gateway with centralized billing"
        case .openaiGateway, .anthropicGateway, .geminiEnterpriseAgentspace:
            if let base = profile?.baseURL, !base.isEmpty, base != "https://llm-gateway.corp.internal/v1" {
                return base
            }
            return "LiteLLM, Kong, Apigee, Cloudflare AI Gateway, or VPC endpoint"
        }
    }

    private func inlinePlaceholder(for dialect: EnterpriseProviderDialect) -> String {
        switch dialect {
        case .vertexGemini:
            return "Paste Vertex API Key or Service Account JSON (or click CLI Sign-In)…"
        case .awsBedrock:
            return "Paste Bedrock API Key (ABSK…) or click CLI Sign-In…"
        case .azureOpenAI:
            return "Paste Azure Endpoint URL (https://….openai.azure.com/…) or API Key…"
        case .dotminiEnterprise:
            return "Paste Organization Key (sk-dotmini-ent-…)…"
        case .openaiGateway, .anthropicGateway, .geminiEnterpriseAgentspace:
            return "Paste Gateway URL, cURL command, or .env block…"
        }
    }

    private func cliLoginCommand(for dialect: EnterpriseProviderDialect) -> String? {
        switch dialect {
        case .vertexGemini:
            return "gcloud auth application-default login"
        case .awsBedrock:
            return "aws sso login"
        case .azureOpenAI:
            return "az login"
        default:
            return nil
        }
    }

    private func handleOneClickConnect(dialect: EnterpriseProviderDialect, existingProfile: EnterpriseAPIProfile?) {
        if !canZeroClickSSO(for: dialect, profile: existingProfile) && inlineCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedSetupDialect = dialect
            }
            return
        }
        connectingDialect = dialect
        Task {
            _ = await enterprise.connectProviderZeroConfig(dialect: dialect, credentialOrURL: inlineCredentialInput)
            connectingDialect = nil
            inlineCredentialInput = ""
            expandedSetupDialect = nil
            if let active = enterprise.activeProfile, !active.defaultModel.isEmpty {
                onSelectModel?(active.dialect.brandIconKey, active.defaultModel)
            }
        }
    }

    private func submitInlineConnect(for dialect: EnterpriseProviderDialect) {
        let raw = inlineCredentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        connectingDialect = dialect
        Task {
            _ = await enterprise.connectProviderZeroConfig(dialect: dialect, credentialOrURL: raw)
            connectingDialect = nil
            inlineCredentialInput = ""
            expandedSetupDialect = nil
            if let active = enterprise.activeProfile, !active.defaultModel.isEmpty {
                onSelectModel?(active.dialect.brandIconKey, active.defaultModel)
            }
        }
    }

    private func importFileForProvider(dialect: EnterpriseProviderDialect) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText]
        panel.title = "Import Enterprise Key or Configuration (.json / .env)"
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        connectingDialect = dialect
        Task {
            _ = await enterprise.connectProviderZeroConfig(dialect: dialect, credentialOrURL: content)
            connectingDialect = nil
            expandedSetupDialect = nil
            if let active = enterprise.activeProfile, !active.defaultModel.isEmpty {
                onSelectModel?(active.dialect.brandIconKey, active.defaultModel)
            }
        }
    }

    private func filteredLiveModels(from models: [String]) -> [String] {
        let q = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return models.filter { id in
            let l = id.lowercased()
            if modelFamilyFilter == "gemini" && !l.contains("gemini") && !l.contains("gemma") {
                return false
            }
            if modelFamilyFilter == "claude" && !l.contains("claude") {
                return false
            }
            if !q.isEmpty && !l.contains(q) {
                return false
            }
            return true
        }
    }

    private func subtleModelTierLabel(for modelId: String) -> String? {
        let l = modelId.lowercased()
        if l.contains("gemini-4") || l.contains("opus-5") || l.contains("sonnet-5") || l.contains("gpt-5") || l.contains("gpt-6") {
            return "Frontier"
        }
        if l.contains("pro") || l.contains("opus") || l.hasPrefix("o3") || l.hasPrefix("o4") {
            return "Reasoning"
        }
        if l.contains("flash") || l.contains("haiku") || l.contains("mini") || l.contains("lite") {
            return "Fast"
        }
        return nil
    }

    private func binding<Value>(for profileId: String, keyPath: WritableKeyPath<EnterpriseAPIProfile, Value>) -> Binding<Value> {
        Binding(
            get: {
                enterprise.profiles.first(where: { $0.id == profileId })![keyPath: keyPath]
            },
            set: { newValue in
                guard var prof = enterprise.profiles.first(where: { $0.id == profileId }) else { return }
                prof[keyPath: keyPath] = newValue
                enterprise.upsertProfile(prof, makeActive: false)
            }
        )
    }
}

// MARK: - Custom Headers & Corporate Proxy Sheet (Monochrome)

private struct EnterpriseHeadersAndProxySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared
    let profileId: String

    @State private var headerKey: String = ""
    @State private var headerValue: String = ""
    @State private var headerIsSecret: Bool = true
    @State private var proxyDraft: String = ""

    private var profile: EnterpriseAPIProfile? {
        enterprise.profiles.first(where: { $0.id == profileId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Custom Headers & Corporate Proxy")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") {
                    saveProxy()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("HTTPS / Forward Proxy URL (Optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("http://proxy.corp.internal:8080", text: $proxyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom HTTP Headers (CF-Access, Apigee, Kong, Custom Auth)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if let prof = profile, !prof.customHeaders.isEmpty {
                    ForEach(prof.customHeaders) { hdr in
                        HStack(spacing: 8) {
                            Text(hdr.key)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            Spacer()
                            Text(hdr.isSecret ? "Stored in Keychain" : hdr.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Button {
                                removeHeader(hdr.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }

                HStack(spacing: 8) {
                    TextField("Header-Name", text: $headerKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                    SecureField("Value", text: $headerValue)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                    Toggle("Keychain", isOn: $headerIsSecret)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    Button("Add") {
                        addHeader()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(headerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, height: 340)
        .onAppear {
            proxyDraft = profile?.proxyURL ?? ""
        }
    }

    private func saveProxy() {
        guard var prof = profile else { return }
        prof.proxyURL = proxyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        enterprise.upsertProfile(prof, makeActive: false)
    }

    private func addHeader() {
        guard var prof = profile else { return }
        let k = headerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        let item = EnterpriseHeaderItem(key: k, value: headerIsSecret ? "" : v, isSecret: headerIsSecret)
        if headerIsSecret && !v.isEmpty {
            enterprise.saveHeaderSecret(v, profileId: prof.id, headerId: item.id)
        }
        prof.customHeaders.append(item)
        enterprise.upsertProfile(prof, makeActive: false)
        headerKey = ""
        headerValue = ""
    }

    private func removeHeader(_ id: String) {
        guard var prof = profile else { return }
        enterprise.saveHeaderSecret("", profileId: prof.id, headerId: id)
        prof.customHeaders.removeAll { $0.id == id }
        enterprise.upsertProfile(prof, makeActive: false)
    }
}

// MARK: - Enterprise DLP, ZDR & Command Firewall Sheet (Monochrome)

private struct EnterpriseComplianceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Enterprise Security, ZDR & DLP Policies")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Toggle("Zero Data Retention (X-Dotmini-ZDR / no-store headers)", isOn: $enterprise.zeroDataRetention)
                .font(.system(size: 12))

            Toggle("Reversible Secret Vault DLP (tokenize API keys & PEM keys before outbound requests)", isOn: $enterprise.localDLPRedaction)
                .font(.system(size: 12))

            Toggle("Enterprise Shell Command Firewall (block destructive / exfiltration patterns)", isOn: $enterprise.commandFirewallEnabled)
                .font(.system(size: 12))

            Toggle("Confidential File Split-Routing (.env, *.pem, secrets/*)", isOn: $enterprise.enforceConfidentialSplitRouting)
                .font(.system(size: 12))

            Toggle("Air-Gapped Lockdown (restrict external egress)", isOn: $enterprise.isAirGappedLockdownEnabled)
                .font(.system(size: 12))

            Divider()

            HStack {
                Text("Vaulted Secrets: \(AgentPrivacyGuard.vaultedSecretCount) · Blocked Commands: \(enterprise.blockedCommandsCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Export Policy (.microcode/enterprise-policy.json)") {
                    _ = enterprise.exportWorkspacePolicyTemplate(workspacePath: appState.workspaceFolder?.path)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, height: 300)
    }
}
