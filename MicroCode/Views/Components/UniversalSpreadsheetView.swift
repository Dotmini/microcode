//
//  UniversalSpreadsheetView.swift
//  MicroCode
//
//  Versatile Excel and CSV Spreadsheet Viewer
//  Dual-mode: Interactive Native Data Table Grid + Apple QuickLook Document View
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import SwiftUI
import QuickLookUI
import AppKit

struct UniversalSpreadsheetView: View {
    let url: URL
    
    @State private var viewMode: SpreadsheetViewMode = .table
    @State private var headers: [String] = []
    @State private var rows: [[String]] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var totalRowCount: Int = 0
    @State private var totalColCount: Int = 0
    
    enum SpreadsheetViewMode: String, CaseIterable, Identifiable {
        case table = "Table Grid"
        case quickLook = "QuickLook"
        var id: String { rawValue }
    }
    
    var isBinaryExcel: Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "xlsx" || ext == "xls" || ext == "numbers"
    }
    
    var filteredRows: [[String]] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return rows }
        return rows.filter { row in
            row.contains { $0.lowercased().contains(query) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                // Info Badge
                HStack(spacing: 6) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if totalRowCount > 0 {
                        Text("\(totalRowCount) rows • \(totalColCount) cols")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    } else {
                        Text(url.pathExtension.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                
                // Mode Toggle
                Picker("", selection: $viewMode) {
                    ForEach(SpreadsheetViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                
                Spacer()
                
                // Search Field (Active in Table Mode)
                if viewMode == .table && !headers.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        TextField("Search rows…", text: $searchText)
                            .font(.system(size: 10))
                            .textFieldStyle(.plain)
                            .frame(width: 120)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                
                // Actions Menu
                Menu {
                    Button("Open in Excel / Numbers") {
                        NSWorkspace.shared.open(url)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Divider()
                    Button("Copy File Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Content
            if viewMode == .quickLook || (isBinaryExcel && headers.isEmpty) {
                QuickLookDocumentHost(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tableGridView
            }
        }
        .onAppear {
            loadSpreadsheet()
        }
        .onChange(of: url) { _ in
            loadSpreadsheet()
        }
    }
    
    @ViewBuilder
    private var tableGridView: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading tabular data…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("Switch to QuickLook View") {
                    viewMode = .quickLook
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if headers.isEmpty {
            VStack(spacing: 8) {
                Text("No tabular rows found")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("View in QuickLook Mode") {
                    viewMode = .quickLook
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // High-Performance Data Grid
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Row
                    HStack(spacing: 0) {
                        // Row Number Header
                        Text("#")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .center)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08))
                        
                        ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                            Divider()
                            Text(header)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06))
                        }
                    }
                    
                    Divider()
                    
                    // Data Rows
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredRows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                // Row Number
                                Text("\(rowIndex + 1)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .center)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.02))
                                
                                ForEach(0..<headers.count, id: \.self) { colIndex in
                                    Divider()
                                    let cellValue = colIndex < row.count ? row[colIndex] : ""
                                    Text(cellValue)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 120, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                }
                            }
                            .background(rowIndex % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
                            
                            Divider()
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    private func loadSpreadsheet() {
        isLoading = true
        errorMessage = nil
        
        let ext = url.pathExtension.lowercased()
        if ext == "xlsx" || ext == "xls" || ext == "numbers" {
            // For binary spreadsheets, default to QuickLook mode which renders full Excel natively
            viewMode = .quickLook
            isLoading = false
            return
        }
        
        // CSV / TSV text parsing
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try String(contentsOf: self.url, encoding: .utf8)
                let delimiter = ext == "tsv" ? "\t" : ","
                let parsed = Self.parseDelimitedText(content, delimiter: delimiter)
                
                DispatchQueue.main.async {
                    if let first = parsed.first {
                        self.headers = first
                        self.rows = Array(parsed.dropFirst())
                        self.totalRowCount = self.rows.count
                        self.totalColCount = self.headers.count
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to parse text. Switch to QuickLook view."
                    self.viewMode = .quickLook
                    self.isLoading = false
                }
            }
        }
    }
    
    private static func parseDelimitedText(_ text: String, delimiter: String) -> [[String]] {
        var results: [[String]] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            // Simple split supporting quoted strings
            var cells: [String] = []
            var currentCell = ""
            var insideQuotes = false
            
            for char in line {
                if char == "\"" {
                    insideQuotes.toggle()
                } else if String(char) == delimiter && !insideQuotes {
                    cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                    currentCell = ""
                } else {
                    currentCell.append(char)
                }
            }
            cells.append(currentCell.trimmingCharacters(in: .whitespaces))
            results.append(cells)
        }
        
        return results
    }
}

// MARK: - Native QuickLook Host View
struct QuickLookDocumentHost: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> QLPreviewView {
        let qlView = QLPreviewView()
        qlView.autostarts = true
        qlView.previewItem = url as QLPreviewItem
        return qlView
    }
    
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if nsView.previewItem?.previewItemURL != url {
            nsView.previewItem = url as QLPreviewItem
        }
    }
}
