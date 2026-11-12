//
//  EnterpriseConnectHubView.swift
//  MicroCode
//
//  1-Click Enterprise API Hub UI:
//  - Smart Paste (URL / cURL / .env / Service Account JSON / microcode://enterprise)
//  - Zero-Key CLI SSO Auto-Connect (gcloud / az / aws sso)
//  - Multi-Profile Management (Vertex AI, Gemini Enterprise Agentspace, Azure OpenAI,
//    AWS Bedrock, LiteLLM / Kong / Corporate VPC Gateways, Anthropic Enterprise, Dotmini ZDR)
//  - Live /models Discovery, Custom Keychain Headers, Corporate Proxy, & 1-Click Team Share.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct EnterpriseConnectHubView: View {
    @ObservedObject private var enterprise = EnterpriseAIAuthService.shared

    var onModelOrProfileChanged: ((String, String) -> Void)? = nil

    @State private var smartPasteInput: String = ""
    @State private var primarySecretInput: String = ""
    @State private var secondarySecretInput: String = ""
    @State private var customModelDraft: String = ""
    @State private var newHeaderKey: String = ""
    @State private var newHeaderValue: String = ""
    @State private var newHeaderIsSecret: Bool = true
    @State private var showAdvancedHeadersAndProxy: Bool = false
    @State private var showGovernanceSection: Bool = false
    @State private var toastBanner: String = ""

    private var activeProfileBinding: Binding<EnterpriseAPIProfile>? {
        guard let idx = enterprise.profiles.firstIndex(where: { $0.id == enterprise.activeProfileID })
                ?? enterprise.profiles.indices.first else {
            return nil
        }
        let targetId = enterprise.profiles[idx].id
        return Binding<EnterpriseAPIProfile>(
            get: {
                enterprise.profiles.first(where: { $0.id == targetId }) ?? enterprise.profiles[0]
            },
            set: { updated in
                enterprise.upsertProfile(updated, makeActive: true)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            smartPasteCard
            cliSSODetectorStrip
            profileBarCard
            if let profileBinding = activeProfileBinding {
                activeProfileEditorCard(profileBinding)
                modelsAndVerifyCard(profileBinding)
                teamShareAndNetworkCard(profileBinding)
            }
            governanceCard
        }
        .onAppear {
            syncSecretInputsForActiveProfile()
            Task { await enterprise.detectLocalCLIs() }
        }
        .onChange(of: enterprise.activeProfileID) { _ in
            syncSecretInputsForActiveProfile()
        }
    }

    private func syncSecretInputsForActiveProfile() {
        guard let prof = enterprise.activeProfile else { return }
        primarySecretInput = enterprise.readPrimarySecret(for: prof.id)
        if prof.dialect == .awsBedrock && prof.authScheme == .awsSigV4AccessKey {
            secondarySecretInput = enterprise.readSecondarySecret(for: prof.id)
        } else {
            secondarySecretInput = ""
        }
    }

    // MARK: - 1. Smart Paste Card

    private var smartPasteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("1-Click Smart Connect (Paste URL, cURL, .env, or Team Link)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string), !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        smartPasteInput = clip
                        runSmartPaste(clip)
                    }
                } label: {
                    Label("Paste Clipboard & Connect", systemImage: "doc.on.clipboard.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
            }

            Text("Paste any Azure OpenAI URL, Vertex AI / Gemini Enterprise URL, AWS Bedrock key (`ABSK…`), `curl` command, `.env` block, Service Account `.json`, or `microcode://enterprise` link — fields, headers, and dialect configure automatically.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("Paste endpoint URL, curl -H \"...\", AZURE_OPENAI_ENDPOINT=..., or ABSK...", text: $smartPasteInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        runSmartPaste(smartPasteInput)
                    }

                Button("Auto-Configure") {
                    runSmartPaste(smartPasteInput)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(smartPasteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    importTeamConfigFile()
                } label: {
                    Label("Import .json", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            if !toastBanner.isEmpty {
                Text(toastBanner)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(toastBanner.hasPrefix("✓") ? .green : .orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.indigo.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.indigo.opacity(0.22), lineWidth: 1))
        )
    }

    private func runSmartPaste(_ raw: String) {
        guard let result = enterprise.applySmartPaste(raw) else {
            toastBanner = "Could not recognize format. Paste a full https:// URL, cURL command, .env variables, or Service Account JSON."
            return
        }
        syncSecretInputsForActiveProfile()
        smartPasteInput = ""
        toastBanner = "✓ \(result.summary)"
        onModelOrProfileChanged?(result.profile.dialect.brandIconKey, result.profile.defaultModel)
        Task {
            _ = await enterprise.discoverModelsAndVerify(profileId: result.profile.id)
            if let refreshed = enterprise.activeProfile {
                onModelOrProfileChanged?(refreshed.dialect.brandIconKey, refreshed.defaultModel)
            }
        }
    }

    // MARK: - 2. Zero-Key CLI SSO Strip

    private var cliSSODetectorStrip: some View {
        let cli = enterprise.cliStatus
        return HStack(spacing: 10) {
            Label("Local SSO:", systemImage: "person.badge.shield.checkmark.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.secondary)

            // Google Cloud CLI
            Button {
                if cli.isGcloudReady {
                    var p = enterprise.createPresetProfile(dialect: .vertexGemini)
                    p.authScheme = .gcloudADC
                    if !cli.gcloudProject.isEmpty { p.gcpProjectId = cli.gcloudProject }
                    enterprise.upsertProfile(p, makeActive: true)
                    enterprise.activateEnterpriseSelection(profileId: p.id, modelId: p.defaultModel)
                    onModelOrProfileChanged?(p.dialect.brandIconKey, p.defaultModel)
                    toastBanner = "✓ Connected to Google Cloud SSO (\(p.gcpProjectId.isEmpty ? "ADC" : p.gcpProjectId))"
                } else {
                    enterprise.triggerInteractiveCLILogin(command: "gcloud auth application-default login")
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(cli.isGcloudReady ? Color.green : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
                    Text(cli.isGcloudReady ? "gcloud (\(cli.gcloudProject.isEmpty ? "Ready" : cli.gcloudProject))" : "gcloud SSO Login")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Azure CLI
            Button {
                if cli.isAzureReady {
                    var p = enterprise.createPresetProfile(dialect: .azureOpenAI)
                    p.authScheme = .azureEntraCLI
                    enterprise.upsertProfile(p, makeActive: true)
                    enterprise.activateEnterpriseSelection(profileId: p.id, modelId: p.defaultModel)
                    onModelOrProfileChanged?(p.dialect.brandIconKey, p.defaultModel)
                    toastBanner = "✓ Created Azure Entra ID SSO profile (\(cli.azAccount)) — enter Resource & Deployment below"
                } else {
                    enterprise.triggerInteractiveCLILogin(command: "az login")
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(cli.isAzureReady ? Color.green : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
                    Text(cli.isAzureReady ? "Azure Entra (\(cli.azAccount))" : "az login SSO")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // AWS SSO / CLI
            Button {
                if cli.isAWSReady {
                    let p = enterprise.createPresetProfile(dialect: .awsBedrock)
                    enterprise.activateEnterpriseSelection(profileId: p.id, modelId: p.defaultModel)
                    onModelOrProfileChanged?(p.dialect.brandIconKey, p.defaultModel)
                    toastBanner = "✓ Created AWS Bedrock SSO profile ('\(p.awsProfileName)' • \(p.awsRegion))"
                } else {
                    enterprise.triggerInteractiveCLILogin(command: "aws configure sso")
                }
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(cli.isAWSReady ? Color.green : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
                    Text(cli.isAWSReady ? "AWS (\(cli.awsProfiles.count) profile\(cli.awsProfiles.count == 1 ? "" : "s"))" : "AWS SSO Login")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                Task { await enterprise.detectLocalCLIs() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Rescan local gcloud, az, and aws CLI sessions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - 3. Multi-Profile Selector & Presets

    private var profileBarCard: some View {
        HStack(spacing: 10) {
            Text("Enterprise Profile:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { enterprise.activeProfileID },
                set: { newId in
                    enterprise.activateEnterpriseSelection(profileId: newId)
                    if let p = enterprise.activeProfile {
                        onModelOrProfileChanged?(p.dialect.brandIconKey, p.defaultModel)
                    }
                }
            )) {
                ForEach(enterprise.profiles) { p in
                    Text("\(p.isVerified ? "✓ " : "")\(p.name) — \(p.dialect.shortTitle)").tag(p.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 340)

            Menu {
                ForEach(EnterpriseProviderDialect.allCases) { dialect in
                    Button {
                        let p = enterprise.createPresetProfile(dialect: dialect)
                        enterprise.activateEnterpriseSelection(profileId: p.id, modelId: p.defaultModel)
                        onModelOrProfileChanged?(p.dialect.brandIconKey, p.defaultModel)
                    } label: {
                        Label(dialect.title, systemImage: dialect.systemIcon)
                    }
                }
            } label: {
                Label("Add Provider", systemImage: "plus.circle.fill")
            }
            .controlSize(.small)

            Spacer()

            if enterprise.profiles.count > 1, let active = enterprise.activeProfile {
                Button(role: .destructive) {
                    enterprise.deleteProfile(id: active.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete this Enterprise Profile")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - 4. Active Profile Dialect Editor

    private func activeProfileEditorCard(_ profile: Binding<EnterpriseAPIProfile>) -> some View {
        let p = profile.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: p.dialect.systemIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.dialect.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(p.dialect.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if p.isVerified {
                    Text("VERIFIED")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
            }

            Divider().opacity(0.6)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Name").font(.caption).foregroundColor(.secondary)
                    TextField("Company Production AI", text: profile.name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider Dialect").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { p.dialect },
                        set: { newDialect in
                            var copy = p
                            copy.dialect = newDialect
                            if !newDialect.supportedAuthSchemes.contains(copy.authScheme),
                               let firstScheme = newDialect.supportedAuthSchemes.first {
                                copy.authScheme = firstScheme
                            }
                            if copy.defaultModel.isEmpty || EnterpriseProviderDialect.allCases.flatMap(\.fallbackModels).contains(copy.defaultModel) {
                                copy.defaultModel = newDialect.fallbackModels.first ?? "gpt-4o"
                            }
                            enterprise.upsertProfile(copy, makeActive: true)
                        }
                    )) {
                        ForEach(EnterpriseProviderDialect.allCases) { d in
                            Text(d.title).tag(d)
                        }
                    }
                    .labelsHidden()
                }
            }

            // Dialect-specific minimal fields
            switch p.dialect {
            case .openaiGateway, .anthropicGateway, .dotminiEnterprise:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gateway Base URL").font(.caption).foregroundColor(.secondary)
                    TextField(
                        p.dialect == .anthropicGateway
                            ? "https://anthropic-gateway.corp.internal/v1"
                            : "https://litellm.corp.internal/v1",
                        text: profile.baseURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }

            case .azureOpenAI:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Azure Resource Name").font(.caption).foregroundColor(.secondary)
                        TextField("my-bank-openai", text: profile.azureResourceName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deployment Name").font(.caption).foregroundColor(.secondary)
                        TextField("gpt-4o-prod", text: Binding(
                            get: { p.azureDeploymentName },
                            set: { dep in
                                var copy = p
                                copy.azureDeploymentName = dep
                                if !dep.isEmpty { copy.defaultModel = dep }
                                enterprise.upsertProfile(copy, makeActive: true)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Version").font(.caption).foregroundColor(.secondary)
                        TextField("2024-10-21", text: profile.azureAPIVersion)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 115)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional Full Foundry / APIM Base URL Override (leave blank for standard `*.openai.azure.com`)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("https://my-foundry.services.ai.azure.com/models", text: profile.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                }

            case .vertexGemini:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Cloud Project ID").font(.caption).foregroundColor(.secondary)
                        TextField("my-enterprise-gcp-project", text: profile.gcpProjectId)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vertex AI Region").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: profile.gcpLocation) {
                            ForEach(EnterpriseAIAuthService.supportedVertexLocations, id: \.id) { loc in
                                Text(loc.label).tag(loc.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

            case .geminiEnterpriseAgentspace:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Cloud Project ID").font(.caption).foregroundColor(.secondary)
                        TextField("my-enterprise-gcp-project", text: profile.gcpProjectId)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data Store Location").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: profile.gcpLocation) {
                            Text("global").tag("global")
                            Text("us (Multi-Region US)").tag("us")
                            Text("eu (Multi-Region EU)").tag("eu")
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agentspace Engine / App ID (`cid/...`)").font(.caption).foregroundColor(.secondary)
                        TextField("1b5ab175-0783-4463-8a33-b61845396a2b", text: profile.discoveryEngineId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assistant ID").font(.caption).foregroundColor(.secondary)
                        TextField("default_assistant", text: profile.discoveryAssistantId)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }

            case .awsBedrock:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AWS Region").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: profile.awsRegion) {
                            Text("ap-southeast-1 (Singapore)").tag("ap-southeast-1")
                            Text("ap-northeast-1 (Tokyo)").tag("ap-northeast-1")
                            Text("us-east-1 (N. Virginia)").tag("us-east-1")
                            Text("us-west-2 (Oregon)").tag("us-west-2")
                            Text("eu-central-1 (Frankfurt)").tag("eu-central-1")
                        }
                        .labelsHidden()
                    }
                    if p.authScheme == .awsSigV4Profile {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AWS CLI / SSO Profile (`~/.aws/config`)").font(.caption).foregroundColor(.secondary)
                            if enterprise.cliStatus.awsProfiles.isEmpty {
                                TextField("default", text: profile.awsProfileName)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("", selection: profile.awsProfileName) {
                                    ForEach(enterprise.cliStatus.awsProfiles, id: \.self) { profName in
                                        Text(profName).tag(profName)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    } else if p.authScheme == .awsSigV4AccessKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AWS Access Key ID").font(.caption).foregroundColor(.secondary)
                            TextField("AKIA...", text: profile.awsAccessKeyId)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                    }
                }
            }

            // Authentication Scheme & Secret Input
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authentication Method").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: profile.authScheme) {
                        ForEach(p.dialect.supportedAuthSchemes) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }
                    .labelsHidden()
                }

                if p.authScheme.requiresPrimarySecretField {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.authScheme == .awsSigV4AccessKey ? "AWS Secret Access Key (Keychain)" : "API Key / Bearer Token (Keychain)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField(
                            p.authScheme == .awsBedrockAPIKey ? "ABSK..." : "Enter secret key (stored in macOS Keychain)",
                            text: Binding(
                                get: { primarySecretInput },
                                set: { val in
                                    primarySecretInput = val
                                    enterprise.savePrimarySecret(val, for: p.id)
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                } else if p.authScheme == .serviceAccountJSON {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Cloud Service Account Key").font(.caption).foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                importVertexServiceAccountFile(for: p)
                            } label: {
                                Label(
                                    enterprise.readSecondarySecret(for: p.id).isEmpty && !enterprise.hasVertexServiceAccount
                                        ? "Import Service Account .json…"
                                        : "Replace Service Account .json…",
                                    systemImage: "doc.badge.key"
                                )
                            }
                            .buttonStyle(.bordered)
                            if !enterprise.readSecondarySecret(for: p.id).isEmpty || enterprise.hasVertexServiceAccount {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            if p.authScheme == .awsSigV4AccessKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optional AWS Session Token (for temporary STS credentials)").font(.caption).foregroundColor(.secondary)
                    SecureField("IQoJb3JpZ2luX2Vj...", text: Binding(
                        get: { secondarySecretInput },
                        set: { val in
                            secondarySecretInput = val
                            enterprise.saveSecondarySecret(val, for: p.id)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - 5. Models Discovery & Connection Verification Card

    private func modelsAndVerifyCard(_ profile: Binding<EnterpriseAPIProfile>) -> some View {
        let p = profile.wrappedValue
        let models = p.availableModels
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Active Enterprise Model / Deployment", systemImage: "cpu.fill")
                    .font(.system(size: 12.5, weight: .semibold))

                Picker("", selection: Binding(
                    get: { p.defaultModel.isEmpty ? (models.first ?? "") : p.defaultModel },
                    set: { newModel in
                        var copy = p
                        copy.defaultModel = newModel
                        enterprise.upsertProfile(copy, makeActive: true)
                        enterprise.activateEnterpriseSelection(profileId: copy.id, modelId: newModel)
                        onModelOrProfileChanged?(copy.dialect.brandIconKey, newModel)
                    }
                )) {
                    ForEach(models, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                Spacer()

                Button {
                    Task {
                        let ok = await enterprise.discoverModelsAndVerify(profileId: p.id)
                        if ok, let updated = enterprise.activeProfile {
                            enterprise.activateEnterpriseSelection(profileId: updated.id, modelId: updated.defaultModel)
                            onModelOrProfileChanged?(updated.dialect.brandIconKey, updated.defaultModel)
                        }
                    }
                } label: {
                    Label(
                        enterprise.isVerifying ? "Testing & Fetching…" : "Verify & Fetch Models",
                        systemImage: "checkmark.shield.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(enterprise.isVerifying)
            }

            HStack(spacing: 8) {
                TextField("Add custom deployment / internal model ID (e.g. corp-gpt4o, claude-sonnet-4@20250514)", text: $customModelDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit { addCustomModel(to: p) }

                Button("Add & Select") {
                    addCustomModel(to: p)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !p.lastStatusMessage.isEmpty {
                Text(p.lastStatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(p.isVerified ? .green : .orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    private func addCustomModel(to p: EnterpriseAPIProfile) {
        let m = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        var copy = p
        if !copy.customModels.contains(m) {
            copy.customModels.insert(m, at: 0)
        }
        copy.defaultModel = m
        if copy.dialect == .azureOpenAI && copy.azureDeploymentName.isEmpty {
            copy.azureDeploymentName = m
        }
        enterprise.upsertProfile(copy, makeActive: true)
        enterprise.activateEnterpriseSelection(profileId: copy.id, modelId: m)
        onModelOrProfileChanged?(copy.dialect.brandIconKey, m)
        customModelDraft = ""
    }

    // MARK: - 6. 1-Click Team Onboarding + Custom Headers + Proxy

    private func teamShareAndNetworkCard(_ profile: Binding<EnterpriseAPIProfile>) -> some View {
        let p = profile.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Team Rollout, Custom Headers & Corporate Proxy", systemImage: "person.3.sequence.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button {
                    if let link = enterprise.exportTeamShareLink(for: p.id) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link, forType: .string)
                        toastBanner = "✓ Copied 1-Click Team Link (`microcode://enterprise?...`) — safe to share in Slack/Teams (secrets stripped)"
                    }
                } label: {
                    Label("Copy 1-Click Team Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    _ = enterprise.exportTeamShareFileWithSavePanel(for: p.id)
                } label: {
                    Label("Export Team .json", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(showAdvancedHeadersAndProxy ? "Hide Headers & Proxy" : "Headers & Proxy (\(p.customHeaders.count))") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAdvancedHeadersAndProxy.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showAdvancedHeadersAndProxy {
                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Corporate HTTP/HTTPS Proxy (Optional — e.g. Zscaler / Squid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://proxy.corp.internal:8080", text: profile.proxyURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom HTTP Headers (e.g. `CF-Access-Client-Id`, `CF-Access-Client-Secret`, `X-Cost-Center`)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(p.customHeaders) { hdr in
                        HStack(spacing: 8) {
                            Image(systemName: hdr.isSecret ? "lock.fill" : "tag")
                                .font(.system(size: 10))
                                .foregroundColor(hdr.isSecret ? .orange : .secondary)
                            Text(hdr.key)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            if hdr.isSecret {
                                SecureField(
                                    hdr.requiresUserSecret ? "Enter your secret value…" : "Stored in Keychain",
                                    text: Binding(
                                        get: { enterprise.readHeaderSecret(profileId: p.id, headerId: hdr.id) },
                                        set: { v in enterprise.saveHeaderSecret(v, profileId: p.id, headerId: hdr.id) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            } else {
                                Text(hdr.value)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            Button(role: .destructive) {
                                var copy = p
                                enterprise.saveHeaderSecret("", profileId: p.id, headerId: hdr.id)
                                copy.customHeaders.removeAll { $0.id == hdr.id }
                                enterprise.upsertProfile(copy, makeActive: true)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Header Name (e.g. CF-Access-Client-Secret)", text: $newHeaderKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                        if newHeaderIsSecret {
                            SecureField("Secret Value (Keychain)", text: $newHeaderValue)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Header Value", text: $newHeaderValue)
                                .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Keychain", isOn: $newHeaderIsSecret)
                            .font(.system(size: 11))
                            .toggleStyle(.checkbox)
                        Button("Add") {
                            let k = newHeaderKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            let v = newHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !k.isEmpty, !v.isEmpty else { return }
                            var copy = p
                            let item = EnterpriseHeaderItem(key: k, value: newHeaderIsSecret ? "" : v, isSecret: newHeaderIsSecret)
                            copy.customHeaders.append(item)
                            if newHeaderIsSecret {
                                enterprise.saveHeaderSecret(v, profileId: p.id, headerId: item.id)
                            }
                            enterprise.upsertProfile(copy, makeActive: true)
                            newHeaderKey = ""
                            newHeaderValue = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - 7. Sovereign DLP & Governance Card

    private var governanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Enterprise DLP, Command Firewall & Compliance", systemImage: "lock.shield.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("Vaulted: \(AgentPrivacyGuard.vaultedSecretCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .foregroundStyle(.green)
                Button(showGovernanceSection ? "Collapse" : "Configure Policies") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showGovernanceSection.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showGovernanceSection {
                Divider().opacity(0.6)
                Toggle("Zero Data Retention (ZDR) — Send no-training / no-logging headers on every request", isOn: $enterprise.zeroDataRetention)
                    .font(.system(size: 12))
                Toggle("Bidirectional DLP Secret Vault — Tokenize API keys/PEMs before prompts leave Mac", isOn: $enterprise.localDLPRedaction)
                    .font(.system(size: 12))
                Toggle("Confidential Split-Routing — Route turns reading .env / *.pem to Local LLM or Enterprise VPC", isOn: $enterprise.enforceConfidentialSplitRouting)
                    .font(.system(size: 12))
                Toggle("Enterprise Shell Command Firewall — Block destructive shell / DB / Terraform commands", isOn: $enterprise.commandFirewallEnabled)
                    .font(.system(size: 12))
                Toggle("Air-Gapped Sovereign Lockdown — Block public consumer AI endpoints", isOn: $enterprise.isAirGappedLockdownEnabled)
                    .font(.system(size: 12))

                HStack(spacing: 8) {
                    Button {
                        let wsPath = AppState.shared?.workspaceFolder?.path ?? UserDefaults.standard.string(forKey: "lastOpenedWorkspacePath")
                        _ = enterprise.exportWorkspacePolicyTemplate(workspacePath: wsPath)
                    } label: {
                        Label("Generate enterprise-policy.json", systemImage: "doc.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        _ = FlightRecorder.shared.saveComplianceReportWithPanel()
                    } label: {
                        Label("Export SOC2 / PDPA Report", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - File Import Helpers

    private func importTeamConfigFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a .microcode-enterprise.json Team Setup file or Google Cloud Service Account JSON"
        if panel.runModal() == .OK, let url = panel.url,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            runSmartPaste(text)
        }
    }

    private func importVertexServiceAccountFile(for profile: EnterpriseAPIProfile) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select Google Cloud Service Account JSON key file"
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            enterprise.saveSecondarySecret(content, for: profile.id)
            _ = enterprise.saveVertexServiceAccountJSON(content)
            var copy = profile
            if copy.gcpProjectId.isEmpty && !enterprise.vertexProjectId.isEmpty {
                copy.gcpProjectId = enterprise.vertexProjectId
            }
            enterprise.upsertProfile(copy, makeActive: true)
            toastBanner = "✓ Loaded Service Account JSON (\(url.lastPathComponent))"
        }
    }
}
