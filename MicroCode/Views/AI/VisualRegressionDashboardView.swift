//
//  VisualRegressionDashboardView.swift
//  MicroCode
//
//  Visual Regression Testing & UI Verification Dashboard (Phase 4)
//  Shows snapshot baselines, visual comparison results, and pixel-diff highlights.
//

import SwiftUI
import AppKit

struct VisualRegressionDashboardView: View {
    @StateObject private var service = VisualRegressionService.shared
    @State private var selectedResult: VisualComparisonResult?
    @State private var showingSaveSheet = false
    @State private var newBaselineName = ""
    @State private var newBaselineScreen = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            Divider()
            
            // Content
            HSplitView {
                // Left sidebar: Baselines & Results
                VStack(spacing: 0) {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Results (\(service.lastResults.count))").tag(0)
                        Text("Baselines (\(service.baselines.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                    
                    Divider()
                    
                    if selectedTab == 0 {
                        resultsList
                    } else {
                        baselinesList
                    }
                }
                .frame(minWidth: 260, maxWidth: 360)
                
                // Right detail: Comparison Diff Inspector
                detailInspector
                    .frame(minWidth: 400)
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            saveBaselineSheet
        }
    }
    
    @State private var selectedTab = 0
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 14))
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Visual Regression Engine")
                    .font(.system(size: 13, weight: .semibold))
                Text("Pixel-Accurate UI Verification & Golden Baselines")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Threshold Slider
            HStack(spacing: 6) {
                Text("Tolerance:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f%%", service.mismatchThreshold))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Slider(value: $service.mismatchThreshold, in: 0.1...5.0, step: 0.1)
                    .frame(width: 80)
                    .controlSize(.mini)
            }
            
            Button {
                showingSaveSheet = true
            } label: {
                Label("Capture Baseline", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    // MARK: - Results List
    
    private var resultsList: some View {
        Group {
            if service.lastResults.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No Visual Test Results")
                        .font(.system(size: 12, weight: .medium))
                    Text("Agent or user has not run any visual comparisons yet.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            } else {
                List(service.lastResults, id: \.id, selection: $selectedResult) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.passed ? .green : .red)
                                .font(.system(size: 12))
                            Text(result.baseline.name)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f%%", result.mismatchPercentage))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(result.passed ? .green : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(result.passed ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                .cornerRadius(4)
                        }
                        
                        HStack(spacing: 8) {
                            Text(result.baseline.deviceName)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            Text("\(result.mismatchPixels) px mismatch")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(result.timestamp, style: .time)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(result)
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - Baselines List
    
    private var baselinesList: some View {
        Group {
            if service.baselines.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "photo.stack")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No Baselines Recorded")
                        .font(.system(size: 12, weight: .medium))
                    Text("Capture a golden snapshot from the preview or simulator.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Spacer()
                }
            } else {
                List(service.baselines) { baseline in
                    HStack(spacing: 10) {
                        if let img = NSImage(contentsOfFile: baseline.baselineImagePath) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 48)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 36, height: 48)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(baseline.name)
                                .font(.system(size: 12, weight: .medium))
                            if !baseline.screenName.isEmpty {
                                Text(baseline.screenName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(baseline.deviceName) • \(Int(baseline.resolution.width))x\(Int(baseline.resolution.height))")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - Detail Inspector
    
    private var detailInspector: some View {
        Group {
            if let result = selectedResult ?? service.lastResults.first {
                VStack(spacing: 0) {
                    // Summary Banner
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(result.baseline.name)
                                    .font(.system(size: 14, weight: .bold))
                                Text(result.passed ? "PASSED" : "FAILED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(result.passed ? .green : .red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(result.passed ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text("Screen: \(result.baseline.screenName.isEmpty ? "Default" : result.baseline.screenName) | Device: \(result.baseline.deviceName)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f%% Mismatch", result.mismatchPercentage))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(result.passed ? .green : .red)
                            Text("\(result.mismatchPixels) of \(result.totalPixels) pixels differ")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // Side-by-side Image View
                    ScrollView([.horizontal, .vertical]) {
                        HStack(spacing: 20) {
                            // Baseline
                            imageCard(
                                title: "Baseline (Golden)",
                                path: result.baseline.baselineImagePath
                            )
                            
                            // Diff Highlight
                            if let diff = result.diffImagePath {
                                imageCard(
                                    title: "Pixel Diff (Red Highlight)",
                                    path: diff,
                                    isDiff: true
                                )
                            }
                            
                            // Actual Current Screen
                            imageCard(
                                title: "Actual (Current Run)",
                                path: result.actualImagePath
                            )
                        }
                        .padding(16)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a Comparison Result")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("View side-by-side visual diffs and pixel mismatch highlights.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
            }
        }
    }
    
    private func imageCard(title: String, path: String, isDiff: Bool = false) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDiff ? .red : .primary)
            
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 460)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDiff ? Color.red.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 200, height: 350)
                    .overlay(Text("Image not found").font(.system(size: 10)).foregroundColor(.secondary))
            }
        }
    }
    
    // MARK: - Save Baseline Sheet
    
    private var saveBaselineSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture New Golden Baseline")
                .font(.system(size: 14, weight: .bold))
            Text("Takes a screenshot of the currently active simulator or preview and records it as a baseline.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Baseline Identifier")
                    .font(.system(size: 11, weight: .medium))
                TextField("e.g. HomeScreen_Dark", text: $newBaselineName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Screen / View Name (Optional)")
                    .font(.system(size: 11, weight: .medium))
                TextField("e.g. Dashboard", text: $newBaselineScreen)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    showingSaveSheet = false
                }
                .controlSize(.small)
                
                Button("Capture & Save") {
                    captureCurrentBaseline()
                    showingSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newBaselineName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 360)
    }
    
    private func captureCurrentBaseline() {
        Task {
            let tmpPath = "\(NSTemporaryDirectory())manual_baseline_\(Int(Date().timeIntervalSince1970)).png"
            do {
                _ = try await DeviceRuntimeService.shared.executeForAgent(
                    operation: "screenshot",
                    workspacePath: nil,
                    deviceID: nil,
                    x: nil, y: nil, x2: nil, y2: nil, duration: nil,
                    text: nil, key: nil, packageName: nil,
                    filePath: tmpPath, command: nil
                )
                if let img = NSImage(contentsOfFile: tmpPath) {
                    _ = service.saveBaseline(
                        image: img,
                        name: newBaselineName,
                        deviceType: "simulator",
                        deviceName: "Simulator",
                        screenName: newBaselineScreen
                    )
                }
            } catch {
                NSLog("⚠️ Failed to capture baseline screenshot: \(error)")
            }
        }
    }
}
