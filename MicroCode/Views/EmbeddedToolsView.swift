//
//  EmbeddedToolsView.swift
//  MicroCode
//
//  100% Zero-Mock Native Hardware Inspection Views for Embed & IoT Studio:
//  1. EmbeddedELFMemoryProfilerView — Real `<arch>-size -A` & `<arch>-nm --size-sort -C` ELF Section & Symbol Profiler
//  2. EmbeddedBLEInspectorView — Real macOS `CoreBluetooth` BLE Scanner, GATT Read/Write/Notify & Nordic UART (NUS) Bridge
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import SwiftUI
import AppKit
import CoreBluetooth

// MARK: - 1. Real ELF Memory & Symbol Map Profiler View (Zero-Mock)

struct EmbeddedELFMemoryProfilerView: View {
    let selectedBoard: HardwareBoardTarget
    let isCompiling: Bool
    let isDark: Bool
    let onTriggerCompile: () -> Void

    @ObservedObject private var elfService = ELFMemoryAndDwarfService.shared
    @State private var symbolSearch: String = ""
    @State private var regionFilter: String = "ALL"

    private var bgColor: Color { isDark ? Color.black : Color(white: 0.98) }
    private var cardBg: Color { isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.03) }
    private var borderCol: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    private var primaryFg: Color { isDark ? Color.white : Color.black }
    private var secondaryFg: Color { isDark ? Color(white: 0.58) : Color(white: 0.42) }

    private var detectedSizeTool: String {
        if let p = ELFMemoryAndDwarfService.findBinutilsTool("size", board: selectedBoard) {
            return (p as NSString).lastPathComponent
        }
        return "Not installed"
    }

    private var detectedNmTool: String {
        if let p = ELFMemoryAndDwarfService.findBinutilsTool("nm", board: selectedBoard) {
            return (p as NSString).lastPathComponent
        }
        return "Not installed"
    }

    private func filteredSymbols(_ symbols: [ELFSymbolInfo]) -> [ELFSymbolInfo] {
        symbols.filter { sym in
            let matchesRegion: Bool = {
                switch regionFilter {
                case "SRAM": return sym.regionLabel.contains("SRAM")
                case "FLASH": return sym.regionLabel.contains("Flash")
                default: return true
                }
            }()
            guard matchesRegion else { return false }
            let q = symbolSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return sym.name.lowercased().contains(q) || sym.regionLabel.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Action & Toolchain Header
            HStack(spacing: 12) {
                Image(systemName: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryFg)

                VStack(alignment: .leading, spacing: 2) {
                    Text("REAL ELF MEMORY & SYMBOL MAP PROFILER")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(primaryFg)
                    Text("Target: \(selectedBoard.rawValue)  ·  size: \(detectedSizeTool)  ·  nm: \(detectedNmTool)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(secondaryFg)
                }

                Spacer()

                if let elfPath = elfService.latestELFPath {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: elfPath)])
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text((elfPath as NSString).lastPathComponent)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundColor(primaryFg.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cardBg)
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderCol, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal compiled .elf binary in Finder: \(elfPath)")
                }

                Button(action: onTriggerCompile) {
                    HStack(spacing: 6) {
                        if isCompiling {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9.5))
                        }
                        Text(isCompiling ? "LINKING ELF..." : "COMPILE & PROFILE ELF")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(isDark ? Color.white : Color.black)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(isCompiling)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isDark ? Color(white: 0.04) : Color(white: 0.94))

            Rectangle().fill(borderCol).frame(height: 1)

            if let report = elfService.latestReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Hardware Capacity Gauges
                        HStack(spacing: 12) {
                            capacityCard(
                                title: "FLASH PROGRAM + RODATA",
                                usedBytes: report.flashUsedBytes,
                                capacityBytes: report.flashCapacityBytes,
                                percent: report.flashPercent,
                                subtitle: "Application partition footprint"
                            )
                            capacityCard(
                                title: "STATIC SRAM (.DATA + .BSS + IRAM)",
                                usedBytes: report.ramUsedBytes,
                                capacityBytes: report.ramCapacityBytes,
                                percent: report.ramPercent,
                                subtitle: "\(formatBytes(max(0, report.ramCapacityBytes - report.ramUsedBytes))) free for FreeRTOS Heap/Stacks"
                            )
                            if report.iramUsedBytes > 0 {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("INTERNAL IRAM")
                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(secondaryFg)
                                    Text(formatBytes(report.iramUsedBytes))
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(primaryFg)
                                    Text("\(report.iramUsedBytes) exact bytes (ISR / fast exec)")
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundColor(secondaryFg)
                                }
                                .padding(12)
                                .frame(width: 200, alignment: .leading)
                                .background(cardBg)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderCol, lineWidth: 1))
                            }
                        }

                        // 2. ELF Section Breakdown (`size -A`)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("ELF LINKER SECTIONS (\(report.sections.count))")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(primaryFg)
                                Spacer()
                                Text(report.elfPath)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(secondaryFg)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            let maxSecBytes = max(1, report.sections.map(\.sizeBytes).max() ?? 1)
                            VStack(spacing: 4) {
                                ForEach(report.sections.prefix(16)) { sec in
                                    HStack(spacing: 10) {
                                        Text(sec.name)
                                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(primaryFg)
                                            .frame(width: 170, alignment: .leading)
                                            .lineLimit(1)

                                        Text(sec.addressHex)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(secondaryFg)
                                            .frame(width: 92, alignment: .leading)

                                        GeometryReader { geo in
                                            let ratio = CGFloat(sec.sizeBytes) / CGFloat(maxSecBytes)
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                                                    .frame(width: max(3, geo.size.width * ratio))
                                            }
                                        }
                                        .frame(height: 7)

                                        Text("\(sec.sizeBytes) B (\(formatBytes(sec.sizeBytes)))")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(primaryFg.opacity(0.88))
                                            .frame(width: 135, alignment: .trailing)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                        .padding(12)
                        .background(cardBg)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderCol, lineWidth: 1))

                        // 3. Top-25 RAM & Flash Symbol Consumers (`nm --size-sort -C`)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("TOP SYMBOL MEMORY CONSUMERS (DEMANGLED C++ / DWARF NM)")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(primaryFg)

                                Spacer()

                                ForEach(["ALL", "SRAM", "FLASH"], id: \.self) { tab in
                                    Button(action: { regionFilter = tab }) {
                                        Text(tab)
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(regionFilter == tab ? (isDark ? .black : .white) : secondaryFg)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(regionFilter == tab ? (isDark ? Color.white : Color.black) : Color.clear)
                                            .cornerRadius(3)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderCol, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }

                                TextField("Filter symbol...", text: $symbolSearch)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(width: 170)
                                    .background(isDark ? Color.white.opacity(0.05) : Color.white)
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(borderCol, lineWidth: 1))
                            }

                            let symbols = filteredSymbols(report.topSymbols)
                            if symbols.isEmpty {
                                Text("No matching symbols in ELF table.")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(secondaryFg)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(symbols) { sym in
                                    HStack(spacing: 10) {
                                        Text(sym.symbolType)
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(isDark ? .black : .white)
                                            .frame(width: 18, height: 18)
                                            .background(isDark ? Color.white.opacity(0.82) : Color.black.opacity(0.82))
                                            .cornerRadius(3)

                                        Text(sym.regionLabel)
                                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(secondaryFg)
                                            .frame(width: 132, alignment: .leading)

                                        Text(sym.name)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(primaryFg)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)

                                        Spacer()

                                        Text("\(sym.sizeBytes) B")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(primaryFg)
                                            .frame(width: 90, alignment: .trailing)
                                    }
                                    .padding(.vertical, 3)
                                    Divider().opacity(0.25)
                                }
                            }
                        }
                        .padding(12)
                        .background(cardBg)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderCol, lineWidth: 1))
                    }
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(secondaryFg.opacity(0.6))
                    Text("NO COMPILED .ELF ARTIFACT LOADED")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(primaryFg)
                    Text("Click 'COMPILE & PROFILE ELF' to run the real MCU cross-linker (\(selectedBoard.rawValue)) and inspect exact Flash/SRAM section & symbol byte usage.")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(secondaryFg)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button(action: onTriggerCompile) {
                        Text(isCompiling ? "COMPILING..." : "COMPILE & PROFILE ELF NOW")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(isDark ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isDark ? Color.white : Color.black)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCompiling)
                }
                Spacer()
            }
        }
        .background(bgColor)
    }

    private func capacityCard(title: String, usedBytes: Int, capacityBytes: Int, percent: Double, subtitle: String) -> some View {
        let barColor: Color = percent > 85 ? .red : (percent > 65 ? .orange : (isDark ? .white : .black))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(secondaryFg)
                Spacer()
                Text(String(format: "%.1f%%", percent))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(percent > 85 ? .red : primaryFg)
            }

            Text("\(formatBytes(usedBytes)) / \(formatBytes(capacityBytes))  (\(usedBytes) B)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(primaryFg)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1.0, percent / 100.0))))
                }
            }
            .frame(height: 7)

            Text(subtitle)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(secondaryFg)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderCol, lineWidth: 1))
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.2f MB", Double(bytes) / 1_048_576.0)
        }
        if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return "\(bytes) B"
    }
}

// MARK: - 2. Real CoreBluetooth BLE GATT Explorer & Wireless NUS Bridge View (Zero-Mock)

struct EmbeddedBLEInspectorView: View {
    let isDark: Bool

    @ObservedObject private var ble = BLEHardwareInspectorService.shared
    @State private var writeDrafts: [String: String] = [:]
    @State private var writeHexFlags: [String: Bool] = [:]
    @State private var nusCommandText: String = ""
    @State private var nameFilter: String = ""

    private var bgColor: Color { isDark ? Color.black : Color(white: 0.98) }
    private var cardBg: Color { isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.03) }
    private var borderCol: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    private var primaryFg: Color { isDark ? Color.white : Color.black }
    private var secondaryFg: Color { isDark ? Color(white: 0.58) : Color(white: 0.42) }

    private var visiblePeripherals: [BLEPeripheralItem] {
        let q = nameFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ble.peripherals }
        return ble.peripherals.filter {
            $0.name.lowercased().contains(q)
                || $0.id.uuidString.lowercased().contains(q)
                || $0.advertisedServices.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Radio & Scan Control Bar
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(primaryFg)

                VStack(alignment: .leading, spacing: 2) {
                    Text("COREBLUETOOTH BLE GATT EXPLORER & NORDIC UART (NUS) BRIDGE")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(primaryFg)
                    Text("macOS Bluetooth Radio: \(ble.bluetoothStateText)  ·  Discovered: \(ble.peripherals.count) node(s)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(secondaryFg)
                }

                Spacer()

                Toggle(isOn: $ble.bridgeNUSToSerialPlotter) {
                    Text("NUS → SERIAL & PLOTTER")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(primaryFg)
                }
                .toggleStyle(.checkbox)
                .help("Pipe incoming Nordic UART (6E400003) BLE lines directly into the Serial Console and 60fps Oscilloscope")

                if ble.connectedPeripheral != nil {
                    Button(action: { ble.disconnect() }) {
                        Text("DISCONNECT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.82))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                }) {
                    HStack(spacing: 5) {
                        if ble.isScanning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.68)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 9.5))
                        }
                        Text(ble.isScanning ? "STOP SCAN" : "SCAN BLE PERIPHERALS")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(isDark ? Color.white : Color.black)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isDark ? Color(white: 0.04) : Color(white: 0.94))

            Rectangle().fill(borderCol).frame(height: 1)

            HSplitView {
                // LEFT: Live Discovered Peripherals List
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9.5))
                            .foregroundColor(secondaryFg)
                        TextField("Filter BLE device or UUID...", text: $nameFilter)
                            .textFieldStyle(.plain)
                            .font(.system(size: 9.5, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(cardBg)

                    Rectangle().fill(borderCol).frame(height: 1)

                    if visiblePeripherals.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Text(ble.isScanning ? "SCANNING PHYSICAL BLE SPECTRUM..." : "NO BLE PERIPHERALS LISTED")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryFg)
                            Text("Click 'SCAN BLE PERIPHERALS' to discover real ESP32, nRF52, STM32WB, or Pico W BLE devices.")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(secondaryFg)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 18)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(visiblePeripherals) { item in
                                    let isConn = ble.connectedPeripheral?.identifier == item.id
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(item.name)
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundColor(primaryFg)
                                                    .lineLimit(1)
                                                if isConn {
                                                    Text("CONNECTED")
                                                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                                        .foregroundColor(.green)
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 1.5)
                                                        .background(Color.green.opacity(0.15))
                                                        .cornerRadius(3)
                                                }
                                            }
                                            Text("RSSI: \(item.rssi) dBm  ·  \(item.id.uuidString.prefix(8))")
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .foregroundColor(secondaryFg)
                                            if !item.advertisedServices.isEmpty {
                                                Text("UUIDs: \(item.advertisedServices.joined(separator: ", "))")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(secondaryFg)
                                                    .lineLimit(1)
                                            }
                                            if !item.manufacturerHex.isEmpty {
                                                Text("MFG: \(item.manufacturerHex)")
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(secondaryFg)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        Button(action: {
                                            if isConn { ble.disconnect() } else { ble.connect(item) }
                                        }) {
                                            Text(isConn ? "DROP" : "CONNECT")
                                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(isConn ? .red : (isDark ? .black : .white))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(isConn ? Color.red.opacity(0.15) : (isDark ? Color.white : Color.black))
                                                .cornerRadius(3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(9)
                                    .background(cardBg)
                                    .cornerRadius(5)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(isConn ? Color.green.opacity(0.55) : borderCol, lineWidth: 1))
                                }
                            }
                            .padding(10)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                // RIGHT: Connected GATT Characteristics Explorer & Packet Console
                VStack(spacing: 0) {
                    if let connected = ble.connectedPeripheral {
                        HStack {
                            Text("GATT TABLE — \(connected.name ?? connected.identifier.uuidString) (\(ble.characteristics.count) chars)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryFg)
                            Spacer()
                            if ble.characteristics.contains(where: { $0.characteristic.uuid == BLEHardwareInspectorService.nusRXCharUUID }) {
                                Text("NORDIC UART (NUS) ACTIVE")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(cardBg)

                        Rectangle().fill(borderCol).frame(height: 1)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(ble.characteristics) { ch in
                                    characteristicCard(ch)
                                }
                            }
                            .padding(12)
                        }

                        // NUS Quick Command Bar if NUS RX exists
                        if ble.characteristics.contains(where: { $0.characteristic.uuid == BLEHardwareInspectorService.nusRXCharUUID }) {
                            Rectangle().fill(borderCol).frame(height: 1)
                            HStack(spacing: 8) {
                                Text("NUS TX:")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(secondaryFg)
                                TextField("Send wireless command over BLE Nordic UART...", text: $nusCommandText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 10, design: .monospaced))
                                    .onSubmit {
                                        guard !nusCommandText.isEmpty else { return }
                                        ble.sendNUSLine(nusCommandText)
                                        nusCommandText = ""
                                    }
                                Button("SEND") {
                                    guard !nusCommandText.isEmpty else { return }
                                    ble.sendNUSLine(nusCommandText)
                                    nusCommandText = ""
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(isDark ? .black : .white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(isDark ? Color.white : Color.black)
                                .cornerRadius(3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(cardBg)
                        }
                    } else {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "wave.3.right.circle")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(secondaryFg.opacity(0.6))
                            Text("SELECT A BLE PERIPHERAL TO INSPECT GATT SERVICES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryFg)
                            Text("Supports live GATT Characteristic Read, Write (UTF-8 / Raw Hex), Notify subscriptions, and automatic Nordic UART (6E400001) telemetry streaming.")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(secondaryFg)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                        Spacer()
                    }

                    Rectangle().fill(borderCol).frame(height: 1)

                    // Bottom Live GATT RX/TX Log
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("LIVE GATT PACKET LOG (\(ble.gattLog.count))")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(secondaryFg)
                            Spacer()
                        }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(ble.gattLog.suffix(60).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(primaryFg.opacity(0.85))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(height: 120)
                    .background(isDark ? Color(white: 0.025) : Color(white: 0.95))
                }
            }
        }
        .background(bgColor)
        .onAppear {
            if !ble.isScanning && ble.peripherals.isEmpty {
                ble.startScan()
            }
        }
    }

    @ViewBuilder
    private func characteristicCard(_ ch: BLEGATTCharacteristicItem) -> some View {
        let canRead = ch.characteristic.properties.contains(.read)
        let canNotify = ch.characteristic.properties.contains(.notify) || ch.characteristic.properties.contains(.indicate)
        let canWrite = ch.characteristic.properties.contains(.write) || ch.characteristic.properties.contains(.writeWithoutResponse)
        let asHex = writeHexFlags[ch.id] ?? false

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("SVC \(ch.serviceUUID)")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(secondaryFg)
                Text("·")
                    .foregroundColor(secondaryFg)
                Text("CHAR \(ch.characteristic.uuid.uuidString)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(primaryFg)
                    .textSelection(.enabled)

                Spacer()

                Text(ch.propertiesSummary)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(secondaryFg)

                if canRead {
                    Button("READ") { ble.readCharacteristic(ch) }
                        .buttonStyle(.plain)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(primaryFg)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(cardBg)
                        .cornerRadius(3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderCol, lineWidth: 1))
                }

                if canNotify {
                    Button(ch.isNotifying ? "NOTIFYING ●" : "NOTIFY") {
                        ble.toggleNotify(ch)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(ch.isNotifying ? .green : primaryFg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ch.isNotifying ? Color.green.opacity(0.14) : cardBg)
                    .cornerRadius(3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderCol, lineWidth: 1))
                }
            }

            if !ch.latestHex.isEmpty || !ch.latestUTF8.isEmpty {
                HStack(spacing: 12) {
                    if !ch.latestUTF8.isEmpty {
                        Text("UTF-8: \(ch.latestUTF8)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(primaryFg)
                            .textSelection(.enabled)
                    }
                    if !ch.latestHex.isEmpty {
                        Text("HEX: \(ch.latestHex)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(secondaryFg)
                            .textSelection(.enabled)
                    }
                }
            }

            if canWrite {
                HStack(spacing: 6) {
                    Button(action: { writeHexFlags[ch.id] = !asHex }) {
                        Text(asHex ? "HEX" : "UTF-8")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(primaryFg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(cardBg)
                            .cornerRadius(3)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderCol, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    TextField(asHex ? "Hex bytes (e.g. 01 FF 0A)..." : "UTF-8 payload...", text: Binding(
                        get: { writeDrafts[ch.id] ?? "" },
                        set: { writeDrafts[ch.id] = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 9.5, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(isDark ? Color.white.opacity(0.05) : Color.white)
                    .cornerRadius(3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderCol, lineWidth: 1))

                    Button("WRITE") {
                        let payload = writeDrafts[ch.id] ?? ""
                        guard !payload.isEmpty else { return }
                        ble.writeCharacteristic(ch, payload: payload, asHex: asHex)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isDark ? Color.white : Color.black)
                    .cornerRadius(3)
                }
            }
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(borderCol, lineWidth: 1))
    }
}

// MARK: - Standalone Sheet Wrapper (Zero-Mock Compatibility)

struct EmbeddedToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("MicroCode Embedded Hardware Inspector", systemImage: "cpu.fill")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            Divider()

            TabView {
                EmbeddedELFMemoryProfilerView(
                    selectedBoard: EmbeddedStudioController.shared.activeBoard,
                    isCompiling: false,
                    isDark: appState.appTheme.isDark,
                    onTriggerCompile: {
                        Task { _ = await EmbeddedStudioController.shared.triggerCompileUI?() }
                    }
                )
                .tabItem { Label("ELF Memory Profiler", systemImage: "memorychip") }

                EmbeddedBLEInspectorView(isDark: appState.appTheme.isDark)
                    .tabItem { Label("BLE GATT & NUS", systemImage: "dot.radiowaves.left.and.right") }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
