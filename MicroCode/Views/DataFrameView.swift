//
//  DataFrameView.swift
//  MicroCode
//
//  High-Performance Data Science & Document Workbench Components for Cell Mode:
//  1) DataFrameView — File-backed DataFrame viewer (preserved API, theme-native UI)
//  2) NotebookInlineDataGridStudio — Auto-rendered virtualized DataFrame table, instant
//     search/sort, column profiling stats, SQL query generator, & native Retina Chart Studio
//  3) NotebookVariableInspectorBar — Live Kernel RAM / Tensor / Metal Memory Inspector with Sparklines
//  4) RichMarkdownCellView — Dual-mode rendered Markdown, LaTeX math, GFM tables, & {{var}} interpolation
//  5) CellParamWidgetsBar — Native reactive controls bound to `# @param` code annotations
//  6) CellInlineDiffBanner & CellVersionHistoryButton — AI Agent diff review & per-cell time travel
//  7) VirtualizedCellOutputLogView — 120FPS log windowing for massive streaming outputs
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 1. File-Backed DataFrameView (Preserved Signature, Bezel-Free Theme UI)

struct DataFrameView: View {
    let rawPath: String
    @State private var dataFrameId: String?
    @State private var schema: [String: String] = [:]
    @State private var rows: [[String: Any]] = []
    @State private var isLoading: Bool = true
    @State private var error: String?
    @State private var columns: [String] = []
    @State private var viewMode: ViewMode = .table
    var onGenerateCode: ((String) -> Void)? = nil

    enum ViewMode {
        case table, profile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    modeButton(title: "Table", mode: .table)
                    modeButton(title: "Profile", mode: .profile)
                }
                .padding(2)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)

                Spacer()

                Text("\(rows.count) rows")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            Divider()

            if isLoading {
                ProgressView("Loading DataFrame…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = error {
                Text("Error: \(error)")
                    .font(.system(size: 11.5))
                    .foregroundColor(.red)
                    .padding()
            } else {
                if viewMode == .table {
                    tableView
                } else {
                    DataProfilingView(rows: rows, columns: columns, schema: schema, onGenerateCode: onGenerateCode)
                }
            }
        }
        .background(Color.primary.opacity(0.02))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.11), lineWidth: 0.8)
        )
        .task {
            await loadData()
        }
    }

    @ViewBuilder
    private func modeButton(title: String, mode: ViewMode) -> some View {
        let active = viewMode == mode
        Button(action: { viewMode = mode }) {
            Text(title)
                .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                .foregroundColor(active ? .primary : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(active ? Color.primary.opacity(0.12) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private var tableView: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(width: 145, alignment: .leading)
                            .background(Color.primary.opacity(0.06))
                            .overlay(
                                Rectangle()
                                    .frame(width: 0.8)
                                    .foregroundColor(Color.primary.opacity(0.10)),
                                alignment: .trailing
                            )
                    }
                }
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { index in
                        let row = rows[index]
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.self) { column in
                                let value = row[column] ?? ""
                                Text("\(value)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(width: 145, alignment: .leading)
                                    .overlay(
                                        Rectangle()
                                            .frame(width: 0.8)
                                            .foregroundColor(Color.primary.opacity(0.06)),
                                        alignment: .trailing
                                    )
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func loadData() async {
        do {
            isLoading = true
            let id = try await DataFrameService.shared.loadDataFrame(path: rawPath)
            self.dataFrameId = id
            let schema = try await DataFrameService.shared.getSchema(id: id)
            self.schema = schema
            self.columns = schema.keys.sorted()
            let slice = try await DataFrameService.shared.getSlice(id: id, offset: 0, limit: 150)
            self.rows = slice
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}

// MARK: - 2. Native Virtualized Inline DataFrame Grid & Instant Retina Chart Studio

struct NotebookInlineDataGridStudio: View {
    let payload: InlineDataFramePayload
    let isDark: Bool
    var onCreateSQLQueryCell: ((String) -> Void)? = nil

    enum Tab: String {
        case table = "Table"
        case chart = "Chart"
        case stats = "Stats"
    }

    enum ChartKind: String, CaseIterable {
        case bar = "Bar"
        case line = "Line"
        case scatter = "Scatter"
        case histogram = "Histogram"

        var icon: String {
            switch self {
            case .bar: return "chart.bar.fill"
            case .line: return "chart.xyaxis.line"
            case .scatter: return "circle.dotted"
            case .histogram: return "chart.bar.xaxis"
            }
        }
    }

    @State private var activeTab: Tab = .table
    @State private var filterText: String = ""
    @State private var sortColumnIndex: Int? = nil
    @State private var sortAscending: Bool = true
    @State private var chartKind: ChartKind = .bar
    @State private var xColumn: String = ""
    @State private var yColumn: String = ""
    @State private var copiedCSV: Bool = false

    private var numericColumns: [String] {
        payload.columns.filter { col in
            if let st = payload.stats[col], st.minVal != nil { return true }
            let dt = (payload.dtypes[col] ?? "").lowercased()
            return dt.contains("int") || dt.contains("float") || dt.contains("double") || dt.contains("f64") || dt.contains("i64")
        }
    }

    private var filteredAndSortedRows: [[String]] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var base = payload.rows
        if !needle.isEmpty {
            base = base.filter { row in
                row.contains { $0.lowercased().contains(needle) }
            }
        }
        if let colIdx = sortColumnIndex, colIdx >= 0 && colIdx < payload.columns.count {
            base.sort { a, b in
                let va = colIdx < a.count ? a[colIdx] : ""
                let vb = colIdx < b.count ? b[colIdx] : ""
                if let da = Double(va), let db = Double(vb) {
                    return sortAscending ? (da < db) : (da > db)
                }
                return sortAscending
                    ? (va.localizedStandardCompare(vb) == .orderedAscending)
                    : (va.localizedStandardCompare(vb) == .orderedDescending)
            }
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().opacity(0.6)

            switch activeTab {
            case .table:
                gridBody
            case .chart:
                chartStudioBody
            case .stats:
                columnStatsBody
            }
        }
        .background(Color.primary.opacity(isDark ? 0.032 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.12 : 0.09), lineWidth: 0.8)
        )
        .onAppear {
            if xColumn.isEmpty {
                xColumn = payload.columns.first ?? ""
            }
            if yColumn.isEmpty {
                yColumn = numericColumns.first ?? payload.columns.dropFirst().first ?? xColumn
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text(payload.variableName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("· \(payload.totalRows) × \(payload.totalCols)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .fixedSize()

            // Tab switcher (always untruncated)
            HStack(spacing: 2) {
                ForEach([Tab.table, .chart, .stats], id: \.rawValue) { t in
                    let sel = activeTab == t
                    Button(action: { activeTab = t }) {
                        Text(t.rawValue)
                            .font(.system(size: 10, weight: sel ? .semibold : .medium))
                            .foregroundColor(sel ? .primary : .secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2.5)
                            .background(sel ? Color.primary.opacity(isDark ? 0.13 : 0.09) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            .padding(2)
            .background(Color.primary.opacity(isDark ? 0.055 : 0.04))
            .cornerRadius(5)
            .fixedSize()

            if activeTab == .table {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    TextField("Filter…", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .frame(minWidth: 42, maxWidth: 105)
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Color.primary.opacity(isDark ? 0.05 : 0.035))
                .cornerRadius(4.5)
            }

            Spacer(minLength: 3)

            if let onCreateSQLQueryCell, let csvPath = payload.csvExportPath {
                Button(action: {
                    let safeVar = payload.variableName.replacingOccurrences(of: " ", with: "_")
                    let pySQL = """
                    import sqlite3, pandas as pd
                    _conn = sqlite3.connect(":memory:")
                    pd.read_csv(r"\(csvPath)").to_sql("\(safeVar)", _conn, index=False, if_exists="replace")
                    sql_result = pd.read_sql_query("SELECT * FROM \(safeVar) LIMIT 25", _conn)
                    sql_result
                    """
                    onCreateSQLQueryCell(pySQL)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "cylinder")
                            .font(.system(size: 9))
                        Text("SQL")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.cyan.opacity(0.11))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Insert a SQL query cell over this DataFrame")
            }

            Button(action: copyAsCSV) {
                HStack(spacing: 3) {
                    Image(systemName: copiedCSV ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(copiedCSV ? "Copied" : "CSV")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(copiedCSV ? .green : .secondary)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(Color.primary.opacity(isDark ? 0.055 : 0.04))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Copy visible DataFrame slice as CSV")

            Button(action: exportCSVToDisk) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 21, height: 20)
                    .background(Color.primary.opacity(isDark ? 0.055 : 0.04))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Save DataFrame as CSV…")
        }
        .padding(.horizontal, 9)
        .frame(height: 29)
    }

    private var gridBody: some View {
        let rows = filteredAndSortedRows
        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    Text("#")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .padding(.trailing, 6)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(isDark ? 0.065 : 0.045))

                    ForEach(Array(payload.columns.enumerated()), id: \.offset) { idx, col in
                        let dtype = payload.dtypes[col] ?? ""
                        let isSorted = sortColumnIndex == idx
                        Button(action: {
                            if sortColumnIndex == idx {
                                sortAscending.toggle()
                            } else {
                                sortColumnIndex = idx
                                sortAscending = true
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 3) {
                                    Text(col)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    if isSorted {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                Text(dtype)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .frame(width: 132, alignment: .leading)
                            .background(Color.primary.opacity(isDark ? 0.065 : 0.045))
                            .overlay(
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 0.7),
                                alignment: .trailing
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.55)

                // Virtualized Data Rows
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                        HStack(spacing: 0) {
                            Text("\(rIdx + 1)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.75))
                                .frame(width: 38, alignment: .trailing)
                                .padding(.trailing, 6)
                                .padding(.vertical, 4)

                            ForEach(0..<payload.columns.count, id: \.self) { cIdx in
                                let val = cIdx < row.count ? row[cIdx] : ""
                                let isNum = Double(val) != nil
                                Text(val.isEmpty ? "null" : val)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(val.isEmpty ? .secondary.opacity(0.45) : .primary.opacity(0.92))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(width: 132, alignment: isNum ? .trailing : .leading)
                                    .overlay(
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(width: 0.7),
                                        alignment: .trailing
                                    )
                            }
                        }
                        .background(rIdx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(isDark ? 0.024 : 0.018))
                    }
                }
            }
        }
        .frame(maxHeight: 255)
    }

    // MARK: - Native Retina Vector Chart Studio

    private var chartStudioBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ChartKind.allCases, id: \.rawValue) { k in
                    let active = chartKind == k
                    Button(action: { chartKind = k }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: k.icon)
                                .font(.system(size: 9.5))
                            Text(k.rawValue)
                                .font(.system(size: 10, weight: active ? .semibold : .medium))
                        }
                        .foregroundColor(active ? .primary : .secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(active ? Color.primary.opacity(isDark ? 0.13 : 0.09) : Color.primary.opacity(0.04))
                        .cornerRadius(4.5)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 6)

                if chartKind != .histogram {
                    columnSelectorPill(prefix: "X", selected: $xColumn, candidates: payload.columns)
                }
                columnSelectorPill(
                    prefix: chartKind == .histogram ? "Col" : "Y",
                    selected: $yColumn,
                    candidates: numericColumns.isEmpty ? payload.columns : numericColumns
                )
            }

            let points = extractChartSeries()
            if points.isEmpty {
                Text("Select a numeric column for Y to render chart.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 165, alignment: .center)
            } else {
                let ys = points.map(\.y)
                let minY = ys.min() ?? 0
                let maxY = ys.max() ?? 1
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .trailing) {
                        Text(formatCompactNumber(maxY))
                        Spacer()
                        Text(formatCompactNumber((minY + maxY) * 0.5))
                        Spacer()
                        Text(formatCompactNumber(minY))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 168)

                    Canvas { ctx, size in
                        drawChart(ctx: &ctx, size: size, points: points, minY: minY, maxY: maxY)
                    }
                    .frame(height: 168)
                }

                HStack {
                    Text(points.first?.label ?? "")
                    Spacer()
                    Text("\(points.count) points · \(yColumn)")
                    Spacer()
                    Text(points.last?.label ?? "")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.leading, 50)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func columnSelectorPill(prefix: String, selected: Binding<String>, candidates: [String]) -> some View {
        Button(action: {
            let menu = NSMenu(title: prefix)
            menu.autoenablesItems = false
            for c in candidates {
                let item = NSMenuItem(
                    title: c,
                    action: #selector(ClosureMenuActionHandler.performMenuAction(_:)),
                    keyEquivalent: ""
                )
                item.target = ClosureMenuActionHandler.shared
                item.state = (selected.wrappedValue == c) ? .on : .off
                item.representedObject = { selected.wrappedValue = c } as () -> Void
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }) {
            HStack(spacing: 3.5) {
                Text("\(prefix):")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(selected.wrappedValue.isEmpty ? "Select" : selected.wrappedValue)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6.5)
            .frame(height: 20)
            .background(Color.primary.opacity(isDark ? 0.07 : 0.045))
            .cornerRadius(4.5)
        }
        .buttonStyle(.plain)
    }

    private func extractChartSeries() -> [(x: Double, y: Double, label: String)] {
        guard let yIdx = payload.columns.firstIndex(of: yColumn) else { return [] }
        let xIdx = payload.columns.firstIndex(of: xColumn) ?? 0

        if chartKind == .histogram {
            let vals = payload.rows.compactMap { r -> Double? in
                guard yIdx < r.count else { return nil }
                return Double(r[yIdx])
            }
            guard let lo = vals.min(), let hi = vals.max() else { return [] }
            if hi == lo {
                return [(0, Double(vals.count), formatCompactNumber(lo))]
            }
            let bins = min(20, max(6, Int(sqrt(Double(vals.count)))))
            var counts = Array(repeating: 0, count: bins)
            let span = hi - lo
            for v in vals {
                let b = min(bins - 1, max(0, Int(((v - lo) / span) * Double(bins))))
                counts[b] += 1
            }
            return counts.enumerated().map { idx, cnt in
                let edge = lo + (Double(idx) / Double(bins)) * span
                return (Double(idx), Double(cnt), formatCompactNumber(edge))
            }
        }

        var pts: [(Double, Double, String)] = []
        for (i, r) in payload.rows.prefix(120).enumerated() {
            guard yIdx < r.count, let yVal = Double(r[yIdx]) else { continue }
            let rawX = xIdx < r.count ? r[xIdx] : "\(i)"
            let xVal = Double(rawX) ?? Double(i)
            pts.append((xVal, yVal, rawX))
        }
        return pts
    }

    private func drawChart(
        ctx: inout GraphicsContext,
        size: CGSize,
        points: [(x: Double, y: Double, label: String)],
        minY: Double,
        maxY: Double
    ) {
        let w = max(10, size.width)
        let h = max(10, size.height)
        let yBase = chartKind == .bar || chartKind == .histogram ? min(0, minY) : minY
        let spanY = max(1e-9, maxY - yBase)

        // Subtle horizontal gridlines
        for g in 0...3 {
            let gy = h * CGFloat(g) / 3.0
            var gp = Path()
            gp.move(to: CGPoint(x: 0, y: gy))
            gp.addLine(to: CGPoint(x: w, y: gy))
            ctx.stroke(gp, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.7)
        }

        func mapY(_ v: Double) -> CGFloat {
            let norm = (v - yBase) / spanY
            return h - CGFloat(norm) * (h - 8) - 4
        }

        switch chartKind {
        case .bar, .histogram:
            let n = CGFloat(max(1, points.count))
            let slot = w / n
            let barW = max(2, slot * 0.74)
            let zeroY = mapY(max(0, yBase))
            for (idx, pt) in points.enumerated() {
                let x = CGFloat(idx) * slot + (slot - barW) * 0.5
                let topY = min(zeroY, mapY(pt.y))
                let botY = max(zeroY, mapY(pt.y))
                let rect = CGRect(x: x, y: topY, width: barW, height: max(1.5, botY - topY))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.accentColor.opacity(0.82)))
            }

        case .line:
            guard points.count >= 2 else {
                if let p = points.first {
                    let c = CGRect(x: w * 0.5 - 3, y: mapY(p.y) - 3, width: 6, height: 6)
                    ctx.fill(Path(ellipseIn: c), with: .color(.accentColor))
                }
                return
            }
            var linePath = Path()
            var areaPath = Path()
            for (idx, pt) in points.enumerated() {
                let px = (CGFloat(idx) / CGFloat(points.count - 1)) * (w - 8) + 4
                let py = mapY(pt.y)
                if idx == 0 {
                    linePath.move(to: CGPoint(x: px, y: py))
                    areaPath.move(to: CGPoint(x: px, y: h))
                    areaPath.addLine(to: CGPoint(x: px, y: py))
                } else {
                    linePath.addLine(to: CGPoint(x: px, y: py))
                    areaPath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            areaPath.addLine(to: CGPoint(x: w - 4, y: h))
            areaPath.closeSubpath()
            ctx.fill(areaPath, with: .color(.accentColor.opacity(0.14)))
            ctx.stroke(linePath, with: .color(.accentColor), lineWidth: 1.8)

        case .scatter:
            let xs = points.map(\.x)
            let minX = xs.min() ?? 0
            let spanX = max(1e-9, (xs.max() ?? 1) - minX)
            for pt in points {
                let px = CGFloat((pt.x - minX) / spanX) * (w - 10) + 5
                let py = mapY(pt.y)
                let dot = CGRect(x: px - 3, y: py - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(.cyan.opacity(0.85)))
            }
        }
    }

    private var columnStatsBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Column").frame(width: 135, alignment: .leading)
                    Text("Dtype").frame(width: 80, alignment: .leading)
                    Text("Nulls").frame(width: 60, alignment: .trailing)
                    Text("Min").frame(width: 78, alignment: .trailing)
                    Text("Mean").frame(width: 78, alignment: .trailing)
                    Text("Max").frame(width: 78, alignment: .trailing)
                    Spacer()
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(isDark ? 0.06 : 0.04))

                Divider().opacity(0.5)

                ForEach(Array(payload.columns.enumerated()), id: \.offset) { idx, col in
                    let st = payload.stats[col]
                    let isNum = st?.minVal != nil
                    HStack {
                        Text(col)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 135, alignment: .leading)
                        Text(payload.dtypes[col] ?? "-")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Text("\(st?.nullCount ?? 0)")
                            .foregroundColor((st?.nullCount ?? 0) > 0 ? .orange : .secondary)
                            .frame(width: 60, alignment: .trailing)
                        Text(st?.minVal.map(formatCompactNumber) ?? "-")
                            .frame(width: 78, alignment: .trailing)
                        Text(st?.meanVal.map(formatCompactNumber) ?? "-")
                            .frame(width: 78, alignment: .trailing)
                        Text(st?.maxVal.map(formatCompactNumber) ?? "-")
                            .frame(width: 78, alignment: .trailing)
                        Spacer()
                        if isNum {
                            Button(action: {
                                yColumn = col
                                chartKind = .histogram
                                activeTab = .chart
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Plot Histogram for \(col)")
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(idx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.02))
                }
            }
        }
        .frame(maxHeight: 210)
    }

    private func formatCompactNumber(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if abs(v) >= 10_000 { return String(format: "%.1fK", v / 1_000) }
        if floor(v) == v { return String(format: "%.0f", v) }
        return String(format: "%.3f", v)
    }

    private func buildCSVString() -> String {
        func esc(_ s: String) -> String {
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        var lines = [payload.columns.map(esc).joined(separator: ",")]
        for r in filteredAndSortedRows {
            lines.append(r.map(esc).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func copyAsCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildCSVString(), forType: .string)
        copiedCSV = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedCSV = false }
    }

    private func exportCSVToDisk() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(payload.variableName).csv"
        if panel.runModal() == .OK, let dest = panel.url {
            if let existing = payload.csvExportPath, FileManager.default.fileExists(atPath: existing) && filterText.isEmpty {
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: existing), to: dest)
            } else {
                try? buildCSVString().write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - 3. Live Kernel Variable & Unified/Metal Memory Inspector Drawer

struct NotebookVariableInspectorBar: View {
    let variables: [KernelVariableInfo]
    let rssBytes: Int64
    let metalBytes: Int64
    let isDark: Bool
    var onInspectVariable: (KernelVariableInfo) -> Void
    var onPinToSHM: (KernelVariableInfo) -> Void
    var onSendToAgent: (KernelVariableInfo) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.green)
                Text("Live Kernel Memory")
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(variables.count) vars")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                if rssBytes > 0 {
                    Text("RAM \(ByteCountFormatter.string(fromByteCount: rssBytes, countStyle: .memory))")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }

                if metalBytes > 0 {
                    Text("Metal GPU \(ByteCountFormatter.string(fromByteCount: metalBytes, countStyle: .memory))")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)

            Divider().opacity(0.55)

            if variables.isEmpty {
                Text("Run a Python cell to inspect live variables, DataFrames, tensors, and Apple Silicon unified memory.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(variables) { v in
                            variableCard(v)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
            }
        }
        .background(Color.primary.opacity(isDark ? 0.035 : 0.022))
    }

    @ViewBuilder
    private func variableCard(_ v: KernelVariableInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(v.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(v.typeName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.14))
                    .cornerRadius(3.5)
                Spacer(minLength: 4)
                Text(v.formattedMemory)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                if !v.shape.isEmpty {
                    Text(v.shape)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if v.numericSample.count >= 3 {
                    SparklineMiniCanvas(values: v.numericSample)
                        .frame(width: 64, height: 15)
                } else {
                    Text(v.preview.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .leading)
                }
            }

            HStack(spacing: 4) {
                miniVarBtn(icon: "eye", label: "Inspect") { onInspectVariable(v) }
                miniVarBtn(icon: "memorychip", label: "SHM") { onPinToSHM(v) }
                miniVarBtn(icon: "at", label: "Agent") { onSendToAgent(v) }
            }
        }
        .padding(.horizontal, 8.5)
        .padding(.vertical, 6)
        .frame(minWidth: 175, maxWidth: 220)
        .background(Color.primary.opacity(isDark ? 0.05 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.11 : 0.08), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func miniVarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2.5) {
                Image(systemName: icon)
                    .font(.system(size: 8.5))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.055))
            .cornerRadius(3.5)
        }
        .buttonStyle(.plain)
    }
}

struct SparklineMiniCanvas: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2,
                  let lo = values.min(),
                  let hi = values.max() else { return }
            let span = max(1e-9, hi - lo)
            var path = Path()
            for (idx, val) in values.enumerated() {
                let x = (CGFloat(idx) / CGFloat(values.count - 1)) * size.width
                let y = size.height - CGFloat((val - lo) / span) * (size.height - 2) - 1
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.green.opacity(0.85)), lineWidth: 1.3)
        }
    }
}

// MARK: - 4. Dual-Mode Rich Markdown + Math + Tables + `{{ variable }}` Interpolation Cell

struct RichMarkdownCellView: View {
    @Binding var text: String
    let liveVariables: [KernelVariableInfo]
    let isDark: Bool
    let forceRenderedOnly: Bool

    @State private var isEditing: Bool = false

    private enum Block {
        case heading(level: Int, text: String)
        case math(expr: String)
        case code(lang: String, body: String)
        case callout(kind: String, body: String)
        case bullet(text: String)
        case table(headers: [String], rows: [[String]])
        case divider
        case paragraph(text: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing && !forceRenderedOnly {
                HStack {
                    Text("Editing Markdown & LaTeX Math")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { isEditing = false }) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Render")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(Color.green.opacity(0.13))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $text)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 72, maxHeight: 240)
                    .background(Color.primary.opacity(isDark ? 0.045 : 0.03))
                    .cornerRadius(6)
            } else {
                ZStack(alignment: .topTrailing) {
                    renderedDocument
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if !forceRenderedOnly { isEditing = true }
                        }

                    if !forceRenderedOnly {
                        Button(action: { isEditing = true }) {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9))
                                Text("Edit")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.primary.opacity(isDark ? 0.06 : 0.04))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var renderedDocument: some View {
        let interpolated = interpolateVariables(in: text)
        let blocks = parseBlocks(interpolated)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private func interpolateVariables(in raw: String) -> String {
        guard raw.contains("{{") else { return raw }
        var out = raw
        for v in liveVariables {
            let token1 = "{{\(v.name)}}"
            let token2 = "{{ \(v.name) }}"
            let val = v.preview.components(separatedBy: "\n").first ?? v.preview
            if out.contains(token1) { out = out.replacingOccurrences(of: token1, with: val) }
            if out.contains(token2) { out = out.replacingOccurrences(of: token2, with: val) }
        }
        return out
    }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            let size: CGFloat = level == 1 ? 18 : (level == 2 ? 15 : (level == 3 ? 13.5 : 12.5))
            inlineMarkdownText(content)
                .font(.system(size: size, weight: .bold))
                .padding(.top, level <= 2 ? 3 : 1)

        case .math(let expr):
            HStack {
                Spacer(minLength: 8)
                Text(prettifyLatexSymbols(expr))
                    .font(.system(size: 13.5, weight: .medium, design: .serif))
                    .italic()
                    .foregroundColor(.primary.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(isDark ? 0.05 : 0.035))
                    .cornerRadius(6)
                Spacer(minLength: 8)
            }

        case .code(let lang, let body):
            VStack(alignment: .leading, spacing: 3) {
                if !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(body)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isDark ? 0.06 : 0.04))
            .cornerRadius(6)

        case .callout(let kind, let body):
            let accent: Color = kind.contains("WARN") || kind.contains("CAUTION") ? .orange : (kind.contains("IMPORTANT") ? .purple : .accentColor)
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .cornerRadius(1.5)
                inlineMarkdownText(body)
                    .font(.system(size: 12))
            }
            .padding(8)
            .background(accent.opacity(0.08))
            .cornerRadius(6)

        case .bullet(let item):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accentColor)
                inlineMarkdownText(item)
                    .font(.system(size: 12.5))
            }

        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                            Text(h)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(minWidth: 95, alignment: .leading)
                                .background(Color.primary.opacity(0.07))
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, r in
                        HStack(spacing: 0) {
                            ForEach(0..<headers.count, id: \.self) { cIdx in
                                Text(cIdx < r.count ? r[cIdx] : "")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(minWidth: 95, alignment: .leading)
                            }
                        }
                        .background(rIdx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.11), lineWidth: 0.7))
            }

        case .divider:
            Divider().padding(.vertical, 2)

        case .paragraph(let p):
            inlineMarkdownText(p)
                .font(.system(size: 12.5))
                .foregroundColor(.primary.opacity(0.92))
        }
    }

    private func inlineMarkdownText(_ s: String) -> Text {
        let mathReady = prettifyInlineDollarMath(s)
        if let attr = try? AttributedString(markdown: mathReady) {
            return Text(attr)
        }
        return Text(mathReady)
    }

    private func prettifyInlineDollarMath(_ s: String) -> String {
        guard s.contains("$") else { return s }
        let parts = s.components(separatedBy: "$")
        guard parts.count >= 3 else { return s }
        var out = ""
        for (i, seg) in parts.enumerated() {
            if i.isMultiple(of: 2) {
                out += seg
            } else {
                out += "*\(prettifyLatexSymbols(seg))*"
            }
        }
        return out
    }

    private func prettifyLatexSymbols(_ expr: String) -> String {
        let replacements: [(String, String)] = [
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\sigma", "σ"), ("\\mu", "μ"), ("\\lambda", "λ"), ("\\theta", "θ"),
            ("\\pi", "π"), ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"),
            ("\\sqrt", "√"), ("\\pm", "±"), ("\\times", "×"), ("\\cdot", "·"),
            ("\\leq", "≤"), ("\\geq", "≥"), ("\\neq", "≠"), ("\\approx", "≈"),
            ("\\rightarrow", "→"), ("\\infty", "∞"),
            ("^{-1}", "⁻¹"), ("^{-2}", "⁻²"), ("^{2}", "²"), ("^{3}", "³"),
            ("^2", "²"), ("^3", "³"), ("{", ""), ("}", "")
        ]
        var res = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        for (k, v) in replacements {
            res = res.replacingOccurrences(of: k, with: v)
        }
        return res
    }

    private func parseBlocks(_ src: String) -> [Block] {
        let lines = src.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Display Math `$$ ... $$`
            if trimmed.hasPrefix("$$") {
                if trimmed.count > 4 && trimmed.hasSuffix("$$") {
                    let inner = String(trimmed.dropFirst(2).dropLast(2))
                    blocks.append(.math(expr: inner))
                    i += 1
                    continue
                }
                var mathLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("$$") {
                    mathLines.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.math(expr: mathLines.joined(separator: "\n")))
                continue
            }

            // Fenced Code
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(lang: lang, body: codeLines.joined(separator: "\n")))
                continue
            }

            // Headings
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 4 && trimmed.dropFirst(hashes).first == " " {
                    blocks.append(.heading(level: hashes, text: String(trimmed.dropFirst(hashes + 1))))
                    i += 1
                    continue
                }
            }

            // Horizontal Rule
            if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // GFM Table
            if trimmed.hasPrefix("|") && i + 1 < lines.count && lines[i + 1].contains("|---") {
                let headers = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                i += 2
                var tRows: [[String]] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cols = lines[i].trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false)
                    let cleaned = cols.dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
                    tRows.append(cleaned)
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: tRows))
                continue
            }

            // Callout / Blockquote
            if trimmed.hasPrefix(">") {
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.callout(kind: body.uppercased(), body: body))
                i += 1
                continue
            }

            // Bullet / Numbered List
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            blocks.append(.paragraph(text: trimmed))
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(.paragraph(text: "Double-click to write Markdown, LaTeX math (`$$...$$`), or `{{ variable }}` templates…"))
        }
        return blocks
    }
}

// MARK: - 5. Native `# @param` Reactive Parameter Widget Bar

struct CellParamWidgetsBar: View {
    let specs: [CellParameterSpec]
    let language: String
    let isDark: Bool
    var onMutateCode: (_ spec: CellParameterSpec, _ newLiteral: String, _ shouldAutoRun: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(specs) { spec in
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9.5))
                        .foregroundColor(.accentColor)
                    Text(spec.name)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(minWidth: 95, alignment: .leading)

                    switch spec.kind {
                    case .sliderDouble(let lo, let hi, let step):
                        Slider(
                            value: Binding(
                                get: { spec.doubleValue },
                                set: { newVal in
                                    let snapped = (round((newVal - lo) / step) * step) + lo
                                    let formatted = String(format: step < 0.01 ? "%.4f" : "%.2f", min(max(snapped, lo), hi))
                                    onMutateCode(spec, formatted, false)
                                }
                            ),
                            in: lo...hi
                        ) { editing in
                            if !editing {
                                onMutateCode(spec, spec.stringValue, true)
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: 190)

                        Text(spec.stringValue)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .frame(width: 58, alignment: .trailing)

                    case .sliderInt(let lo, let hi, let step):
                        Slider(
                            value: Binding(
                                get: { spec.doubleValue },
                                set: { newVal in
                                    let snapped = Int(round(newVal / Double(max(1, step)))) * max(1, step)
                                    let clamped = min(max(snapped, lo), hi)
                                    onMutateCode(spec, "\(clamped)", false)
                                }
                            ),
                            in: Double(lo)...Double(hi)
                        ) { editing in
                            if !editing {
                                onMutateCode(spec, spec.stringValue, true)
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: 190)

                        Text(spec.stringValue)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .frame(width: 58, alignment: .trailing)

                    case .dropdown(let options):
                        HStack(spacing: 4) {
                            ForEach(options.prefix(5), id: \.self) { opt in
                                let sel = spec.stringValue == opt
                                Button(action: {
                                    onMutateCode(spec, "\"\(opt)\"", true)
                                }) {
                                    Text(opt)
                                        .font(.system(size: 10, weight: sel ? .semibold : .regular))
                                        .foregroundColor(sel ? .white : .primary.opacity(0.85))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(sel ? Color.accentColor : Color.primary.opacity(0.06))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                    case .toggle:
                        Button(action: {
                            let next = !spec.boolValue
                            let lit = language.lowercased() == "python" ? (next ? "True" : "False") : (next ? "true" : "false")
                            onMutateCode(spec, lit, true)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: spec.boolValue ? "checkmark.square.fill" : "square")
                                    .foregroundColor(spec.boolValue ? .green : .secondary)
                                Text(spec.boolValue ? "Enabled" : "Disabled")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)

                    case .text:
                        TextField(
                            spec.name,
                            text: Binding(
                                get: { spec.stringValue },
                                set: { v in onMutateCode(spec, "\"\(v)\"", false) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .frame(maxWidth: 180)
                        .onSubmit {
                            onMutateCode(spec, "\"\(spec.stringValue)\"", true)
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(isDark ? 0.065 : 0.045))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - 6. Inline AI Ghost-Diff Review Banner & Per-Cell Time-Travel History

struct CellInlineDiffBanner: View {
    let oldCode: String
    let newCode: String
    let sourceLabel: String
    let isDark: Bool
    var onAccept: () -> Void
    var onRevert: () -> Void

    @State private var showDiffLines: Bool = true

    private var diffSummaryLines: [(isAdded: Bool?, text: String)] {
        let oldLines = oldCode.components(separatedBy: "\n")
        let newLines = newCode.components(separatedBy: "\n")
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)
        var out: [(Bool?, String)] = []
        for l in oldLines where !newSet.contains(l) && !l.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((false, "- " + l))
            if out.count >= 14 { break }
        }
        for l in newLines where !oldSet.contains(l) && !l.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append((true, "+ " + l))
            if out.count >= 28 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text("\(sourceLabel) modified this cell")
                    .font(.system(size: 10.5, weight: .semibold))
                Button(action: { showDiffLines.toggle() }) {
                    Text(showDiffLines ? "Hide Diff" : "View Diff")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onRevert) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9))
                        Text("Revert")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: onAccept) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Accept")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Color.green.opacity(0.14))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            if showDiffLines && !diffSummaryLines.isEmpty {
                VStack(alignment: .leading, spacing: 1.5) {
                    ForEach(Array(diffSummaryLines.enumerated()), id: \.offset) { _, item in
                        Text(item.text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(item.isAdded == true ? .green : .red)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background((item.isAdded == true ? Color.green : Color.red).opacity(0.08))
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isDark ? 0.05 : 0.032))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.8)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct CellVersionHistoryButton: View {
    let snapshots: [CellVersionSnapshot]
    var onRestore: (CellVersionSnapshot) -> Void

    @State private var showPopover = false

    var body: some View {
        if !snapshots.isEmpty {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 2.5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8.5))
                    Text("v\(snapshots.last?.versionNumber ?? snapshots.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Cell Execution & Edit History (Time-Travel)")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cell Version Time-Travel")
                        .font(.system(size: 12, weight: .semibold))
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(snapshots.reversed()) { snap in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text("v\(snap.versionNumber)")
                                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                            Text(snap.sourceLabel)
                                                .font(.system(size: 10, weight: .medium))
                                            if let ms = snap.durationMs {
                                                Text(String(format: "· %.1fms", ms))
                                                    .font(.system(size: 9.5, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Text(snap.content.replacingOccurrences(of: "\n", with: " "))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button(action: {
                                        onRestore(snap)
                                        showPopover = false
                                    }) {
                                        Text("Restore")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.primary.opacity(0.09))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(6)
                                .background(Color.primary.opacity(0.035))
                                .cornerRadius(5)
                            }
                        }
                    }
                    .frame(maxHeight: 230)
                }
                .padding(12)
                .frame(width: 315)
            }
        }
    }
}

// MARK: - 7. 120FPS Virtualized Cell Output Log Viewer

struct VirtualizedCellOutputLogView: View {
    let output: String
    let hasError: Bool

    @State private var showFullUnbounded: Bool = false

    private let charWindowThreshold = 28_000

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let isTruncated = !showFullUnbounded && output.count > charWindowThreshold
            let displayString: String = {
                guard isTruncated else { return output }
                let head = String(output.prefix(8_000))
                let tail = String(output.suffix(16_000))
                let omitted = output.count - 24_000
                return head + "\n\n⋯ [\(omitted) characters hidden for 120FPS responsiveness] ⋯\n\n" + tail
            }()

            ScrollView {
                Text(displayString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(hasError ? .red : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)

            if output.count > charWindowThreshold {
                HStack(spacing: 8) {
                    Button(action: { showFullUnbounded.toggle() }) {
                        Text(showFullUnbounded ? "Compact Log Window" : "Show Full Output (\(ByteCountFormatter.string(fromByteCount: Int64(output.utf8.count), countStyle: .file)))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    Button(action: saveFullLog) {
                        Text("Save Log…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
    }

    private func saveFullLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "cell_output.log"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
