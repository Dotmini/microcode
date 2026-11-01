//
//  EmbeddedHardwareServices.swift
//  MicroCode
//
//  100% Zero-Mock Native macOS Embedded & IoT Hardware Services:
//  1. IOKitUSBHotplugDaemon — Event-driven USB hotplug + VID:PID silicon fingerprinting + LocationID reconnect
//  2. EmbeddedToolchainService — Real cross-compilation & flashing (PlatformIO, Arduino CLI, ESP-IDF, UF2, DFU, Raw-REPL)
//  3. ELFMemoryAndDwarfService — Real ELF section profiler (size -A), Top-25 RAM/Flash symbols (nm), DWARF addr2line
//  4. IoTNetworkDiscoveryService — Real Network.framework NWBrowser mDNS discovery + Real ESPOTA UDP/TCP & HTTP OTA
//  5. BLEHardwareInspectorService — Real CoreBluetooth BLE scanner, GATT explorer, and Nordic UART (NUS) wireless bridge
//  6. PinConflictDRCAnalyzer & TelemetryFFTAnalyzer — Live GPIO electrical DRC + Apple Accelerate vDSP FFT + Cell Mode CSV bridge
//  7. EmbeddedStudioController & 6 Hardware-in-the-Loop (HIL) AgentTools
//
//  Copyright © 2025-2026 Dotmini Software. All rights reserved.
//

import Foundation
import AppKit
import Darwin
import IOKit
import IOKit.serial
import Network
import CoreBluetooth
import CryptoKit
import Accelerate
import Combine

// MARK: - 1. Silicon VID:PID Fingerprinting & Event-Driven IOKit USB Hotplug Daemon

struct USBHardwareDevice: Identifiable, Hashable {
    var id: String { calloutPath }
    let portName: String
    let calloutPath: String
    let vendorID: UInt16?
    let productID: UInt16?
    let locationID: UInt32?
    let serialNumber: String?
    let vendorName: String?
    let productName: String?
    let siliconSummary: String
    let suggestedBoard: HardwareBoardTarget?

    var vidPidHex: String? {
        guard let v = vendorID, let p = productID else { return nil }
        return String(format: "%04X:%04X", v, p)
    }

    var RealSerialPortValue: RealSerialPort {
        let badge = vidPidHex != nil ? " [\(vidPidHex!)]" : ""
        return RealSerialPort(
            name: portName,
            path: calloutPath,
            isUSB: true,
            driverDescription: siliconSummary + badge
        )
    }
}

struct MountedBootloaderVolume: Identifiable, Hashable {
    var id: String { path }
    let volumeName: String
    let path: String
    let boardFamily: String
}

@MainActor
final class IOKitUSBHotplugDaemon: ObservableObject {
    static let shared = IOKitUSBHotplugDaemon()

    @Published private(set) var devices: [USBHardwareDevice] = []
    @Published private(set) var bootloaderVolumes: [MountedBootloaderVolume] = []
    @Published private(set) var lastHotplugEvent: String = ""

    var onDevicesChanged: (([USBHardwareDevice]) -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private let notifyQueue = DispatchQueue(label: "com.dotmini.microcode.iokit.usb.hotplug")
    private var volumeObservers: [NSObjectProtocol] = []

    private init() {
        startHotplugNotifications()
        startVolumeMountNotifications()
        refreshNow()
    }

    private func startHotplugNotifications() {
        guard notifyPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, notifyQueue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let addedCallback: IOServiceMatchingCallback = { refcon, iterator in
            while case let svc = IOIteratorNext(iterator), svc != 0 {
                IOObjectRelease(svc)
            }
            guard let refcon else { return }
            let daemon = Unmanaged<IOKitUSBHotplugDaemon>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                daemon.lastHotplugEvent = "USB device connected"
                daemon.refreshNow()
            }
        }

        let removedCallback: IOServiceMatchingCallback = { refcon, iterator in
            while case let svc = IOIteratorNext(iterator), svc != 0 {
                IOObjectRelease(svc)
            }
            guard let refcon else { return }
            let daemon = Unmanaged<IOKitUSBHotplugDaemon>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                daemon.lastHotplugEvent = "USB device disconnected"
                daemon.refreshNow()
            }
        }

        if let matchAdd = IOServiceMatching(kIOSerialBSDServiceValue) {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                matchAdd,
                addedCallback,
                selfPtr,
                &addedIterator
            )
            if kr == KERN_SUCCESS {
                while case let svc = IOIteratorNext(addedIterator), svc != 0 {
                    IOObjectRelease(svc)
                }
            }
        }

        if let matchRem = IOServiceMatching(kIOSerialBSDServiceValue) {
            let kr = IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                matchRem,
                removedCallback,
                selfPtr,
                &removedIterator
            )
            if kr == KERN_SUCCESS {
                while case let svc = IOIteratorNext(removedIterator), svc != 0 {
                    IOObjectRelease(svc)
                }
            }
        }
    }

    private func startVolumeMountNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        let mountObs = ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scanBootloaderVolumes() }
        }
        let unmountObs = ws.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scanBootloaderVolumes() }
        }
        volumeObservers = [mountObs, unmountObs]
    }

    func refreshNow() {
        scanBootloaderVolumes()
        Task.detached(priority: .utility) {
            let scanned = Self.enumeratePhysicalUSBDevicesSync()
            await MainActor.run {
                self.devices = scanned
                self.onDevicesChanged?(scanned)
            }
        }
    }

    func scanBootloaderVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        var found: [MountedBootloaderVolume] = []
        for url in urls {
            let name = url.lastPathComponent.uppercased()
            let infoUf2 = url.appendingPathComponent("INFO_UF2.TXT").path
            let mbedHtm = url.appendingPathComponent("MBED.HTM").path
            if name.contains("RPI-RP2") || name.contains("RP2350") || FileManager.default.fileExists(atPath: infoUf2) {
                found.append(MountedBootloaderVolume(volumeName: url.lastPathComponent, path: url.path, boardFamily: "RP2040 / RP2350 UF2 Bootloader"))
            } else if name.contains("NOD_") || name.contains("NUCLEO") || FileManager.default.fileExists(atPath: mbedHtm) {
                found.append(MountedBootloaderVolume(volumeName: url.lastPathComponent, path: url.path, boardFamily: "STM32 ST-LINK Mass Storage"))
            }
        }
        bootloaderVolumes = found
    }

    nonisolated static func enumeratePhysicalUSBDevicesSync() -> [USBHardwareDevice] {
        var results: [USBHardwareDevice] = []
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return results }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let calloutPath = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String else {
                continue
            }

            let fileName = (calloutPath as NSString).lastPathComponent
            let lower = fileName.lowercased()
            if fileName == "cu.debug-console" || lower.contains("bluetooth") || lower.contains("wlan") || lower.contains("endos") {
                continue
            }

            var isPhysicalUSB = false
            var vendorID: UInt16?
            var productID: UInt16?
            var locationID: UInt32?
            var serialNum: String?
            var vendorName: String?
            var productName: String?

            var current = service
            IOObjectRetain(current)
            var parent: io_registry_entry_t = 0
            while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
                var classNameBuf = [CChar](repeating: 0, count: 128)
                IOObjectGetClass(parent, &classNameBuf)
                let cls = String(cString: classNameBuf)

                if cls.contains("USB") {
                    isPhysicalUSB = true
                    if vendorID == nil,
                       let num = IORegistryEntryCreateCFProperty(parent, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                        vendorID = num.uint16Value
                    }
                    if productID == nil,
                       let num = IORegistryEntryCreateCFProperty(parent, "idProduct" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                        productID = num.uint16Value
                    }
                    if locationID == nil,
                       let num = IORegistryEntryCreateCFProperty(parent, "locationID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                        locationID = num.uint32Value
                    }
                    if serialNum == nil,
                       let s = IORegistryEntryCreateCFProperty(parent, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                        serialNum = s
                    }
                    if productName == nil,
                       let s = IORegistryEntryCreateCFProperty(parent, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                        productName = s
                    }
                    if vendorName == nil,
                       let s = IORegistryEntryCreateCFProperty(parent, "USB Vendor Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                        vendorName = s
                    }
                }
                IOObjectRelease(current)
                current = parent
            }
            IOObjectRelease(current)

            let matchesUSBPrefix = lower.hasPrefix("cu.usbmodem")
                || lower.hasPrefix("cu.usbserial")
                || lower.hasPrefix("cu.wchusbserial")
                || lower.hasPrefix("cu.slab_usbto")
                || lower.hasPrefix("cu.cp210")
                || lower.hasPrefix("cu.ch34")

            guard isPhysicalUSB && matchesUSBPrefix else { continue }

            let (summary, suggestedBoard) = fingerprintSilicon(
                vid: vendorID,
                pid: productID,
                vendorName: vendorName,
                productName: productName,
                portName: lower
            )

            results.append(USBHardwareDevice(
                portName: fileName,
                calloutPath: calloutPath,
                vendorID: vendorID,
                productID: productID,
                locationID: locationID,
                serialNumber: serialNum,
                vendorName: vendorName,
                productName: productName,
                siliconSummary: summary,
                suggestedBoard: suggestedBoard
            ))
        }

        results.sort { $0.portName < $1.portName }
        return results
    }

    nonisolated private static func fingerprintSilicon(
        vid: UInt16?,
        pid: UInt16?,
        vendorName: String?,
        productName: String?,
        portName: String
    ) -> (String, HardwareBoardTarget?) {
        if let vid, let pid {
            switch (vid, pid) {
            case (0x303A, 0x1001):
                return ("Espressif Native USB-Serial/JTAG", .esp32s3)
            case (0x303A, 0x0002), (0x303A, 0x1002):
                return ("Espressif ESP32-S2/S3 USB-OTG CDC", .esp32s3)
            case (0x2E8A, 0x000A), (0x2E8A, 0x0005), (0x2E8A, 0x000F), (0x2E8A, 0xF00A):
                return ("Raspberry Pi RP2040/RP2350 USB CDC", .picoW)
            case (0x2341, 0x1002), (0x2341, 0x006D):
                return ("Arduino Uno R4 (RA4M1 / ESP32-S3 Bridge)", .arduinoUnoR4)
            case (0x2341, _):
                return ("Official Arduino USB Device", .arduinoUnoR4)
            case (0x0483, 0x374B), (0x0483, 0x374E), (0x0483, 0x3752), (0x0483, 0x5740):
                return ("STMicroelectronics ST-LINK / Virtual COM", .stm32f4)
            case (0x10C4, 0xEA60), (0x10C4, 0xEA70):
                return ("Silicon Labs CP210x UART Bridge", .esp32s3)
            case (0x1A86, 0x7523):
                return ("WCH CH340 USB-UART Bridge", .esp32c3)
            case (0x1A86, 0x55D4), (0x1A86, 0x55D3):
                return ("WCH CH9102/CH343 High-Speed UART", .esp32s3)
            case (0x0403, 0x6001), (0x0403, 0x6015):
                return ("FTDI FT232/FT-X UART Bridge", nil)
            case (0x1366, _):
                return ("SEGGER J-Link Debug Probe CDC", .stm32f4)
            default:
                break
            }
        }
        if let vend = vendorName, let prod = productName {
            return ("\(vend) \(prod)", nil)
        }
        if let prod = productName {
            return (prod, nil)
        }
        if portName.contains("wch") || portName.contains("ch34") {
            return ("WCH CH34x USB-UART", nil)
        }
        if portName.contains("usbmodem") {
            return ("Native USB CDC/ACM Microcontroller", nil)
        }
        return ("USB Serial Bridge", nil)
    }
}

// MARK: - 2. Real ELF Memory Section Profiler & DWARF Crash Symbolicator

struct ELFSectionInfo: Identifiable {
    let id = UUID()
    let name: String
    let sizeBytes: Int
    let addressHex: String
}

struct ELFSymbolInfo: Identifiable {
    let id = UUID()
    let name: String
    let sizeBytes: Int
    let symbolType: String
    let regionLabel: String
}

struct ELFMemoryReport {
    let elfPath: String
    let timestamp: Date
    let flashUsedBytes: Int
    let flashCapacityBytes: Int
    let ramUsedBytes: Int
    let ramCapacityBytes: Int
    let iramUsedBytes: Int
    let sections: [ELFSectionInfo]
    let topSymbols: [ELFSymbolInfo]

    var flashPercent: Double {
        guard flashCapacityBytes > 0 else { return 0 }
        return min(100.0, (Double(flashUsedBytes) / Double(flashCapacityBytes)) * 100.0)
    }

    var ramPercent: Double {
        guard ramCapacityBytes > 0 else { return 0 }
        return min(100.0, (Double(ramUsedBytes) / Double(ramCapacityBytes)) * 100.0)
    }
}

struct DecodedStackFrame: Identifiable {
    let id = UUID()
    let index: Int
    let pcHex: String
    let spHex: String?
    let functionName: String
    let filePath: String?
    let lineNumber: Int?
    let memoryRegion: String
}

@MainActor
final class ELFMemoryAndDwarfService: ObservableObject {
    static let shared = ELFMemoryAndDwarfService()

    @Published var latestReport: ELFMemoryReport? = nil
    @Published var latestELFPath: String? = nil
    @Published var latestFirmwareBinPath: String? = nil
    @Published var latestDecodedFrames: [DecodedStackFrame] = []

    private init() {}

    static func boardCapacities(for board: HardwareBoardTarget) -> (flashBytes: Int, ramBytes: Int) {
        switch board {
        case .esp32s3:
            return (3_145_728, 327_680) // Standard 3MB app0 partition / 320KB usable internal DRAM
        case .esp32c3:
            return (1_310_720, 327_680) // Standard 1.25MB app0 / 320KB SRAM
        case .picoW:
            return (2_097_152, 270_336) // 2MB QSPI / 264KB SRAM
        case .arduinoUnoR4:
            return (262_144, 32_768)    // 256KB Flash / 32KB SRAM
        case .stm32f4:
            return (524_288, 131_072)   // 512KB Flash / 128KB SRAM
        }
    }

    nonisolated static func findBinutilsTool(_ suffix: String, board: HardwareBoardTarget) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let archPrefixes: [String]
        switch board {
        case .esp32s3:
            archPrefixes = ["xtensa-esp32s3-elf-", "xtensa-esp32-elf-"]
        case .esp32c3:
            archPrefixes = ["riscv32-esp-elf-", "riscv-none-embed-"]
        case .picoW, .arduinoUnoR4, .stm32f4:
            archPrefixes = ["arm-none-eabi-"]
        }

        let searchRoots = [
            "\(home)/.platformio/packages",
            "\(home)/.espressif/tools",
            "\(home)/Library/Arduino15/packages",
            "\(home)/.microcode/arduino15/packages",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]

        for prefix in archPrefixes {
            let targetBin = prefix + suffix
            for root in searchRoots {
                if root.hasSuffix("/bin") {
                    let candidate = "\(root)/\(targetBin)"
                    if fm.isExecutableFile(atPath: candidate) { return candidate }
                } else if fm.fileExists(atPath: root),
                          let enumerator = fm.enumerator(atPath: root) {
                    while let rel = enumerator.nextObject() as? String {
                        if rel.hasSuffix("/bin/\(targetBin)") || rel == targetBin {
                            let full = "\(root)/\(rel)"
                            if fm.isExecutableFile(atPath: full) { return full }
                        }
                    }
                }
            }
        }

        // LLVM universal ELF tools fallback (real DWARF/ELF parsers, never mocks)
        let llvmFallbacks: [String]
        switch suffix {
        case "size": llvmFallbacks = ["/opt/homebrew/opt/llvm/bin/llvm-size", "/usr/bin/size"]
        case "nm": llvmFallbacks = ["/opt/homebrew/opt/llvm/bin/llvm-nm", "/usr/bin/nm"]
        case "addr2line": llvmFallbacks = ["/opt/homebrew/opt/llvm/bin/llvm-addr2line", "/opt/homebrew/opt/llvm/bin/llvm-symbolizer"]
        default: llvmFallbacks = []
        }
        return llvmFallbacks.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    func inspectELF(at elfPath: String, board: HardwareBoardTarget) async -> ELFMemoryReport? {
        guard FileManager.default.fileExists(atPath: elfPath) else { return nil }
        let caps = Self.boardCapacities(for: board)

        let report: ELFMemoryReport? = await Task.detached(priority: .userInitiated) {
            guard let sizeTool = Self.findBinutilsTool("size", board: board) else { return nil }
            let sizeOut = Self.runProcessCapture(executable: sizeTool, args: ["-A", elfPath])

            var sections: [ELFSectionInfo] = []
            var flashBytes = 0
            var ramBytes = 0
            var iramBytes = 0

            for rawLine in sizeOut.components(separatedBy: .newlines) {
                let parts = rawLine.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard parts.count >= 2,
                      parts[0].hasPrefix("."),
                      let sz = Int(parts[1]),
                      sz > 0 else { continue }
                let secName = parts[0]
                let addrInt = parts.count >= 3 ? (UInt64(parts[2]) ?? 0) : 0
                let addrHex = String(format: "0x%08llX", addrInt)
                sections.append(ELFSectionInfo(name: secName, sizeBytes: sz, addressHex: addrHex))

                let lower = secName.lowercased()
                if lower.contains("debug") || lower.contains("comment") || lower.contains("xt.prop") || lower.contains("xt.lit") || lower.contains("attributes") {
                    continue
                }
                if lower.contains("iram") {
                    iramBytes += sz
                    flashBytes += sz
                    ramBytes += sz
                } else if lower.contains("flash") || lower == ".text" || lower == ".rodata" || lower.contains("ARM.exidx".lowercased()) || lower.contains("isr_vector") || lower.contains("boot2") {
                    flashBytes += sz
                } else if lower.contains("dram") || lower == ".data" || lower == ".bss" || lower.contains("noinit") {
                    ramBytes += sz
                    if lower.contains("data") {
                        flashBytes += sz
                    }
                }
            }

            // Parse top symbols via nm --size-sort
            var topSymbols: [ELFSymbolInfo] = []
            if let nmTool = Self.findBinutilsTool("nm", board: board),
               !nmTool.hasSuffix("/usr/bin/nm") {
                let nmOut = Self.runProcessCapture(
                    executable: nmTool,
                    args: ["--size-sort", "--print-size", "--radix=d", "-C", elfPath]
                )
                for line in nmOut.components(separatedBy: .newlines).reversed() {
                    let tokens = line.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }
                    guard tokens.count >= 4,
                          let symSize = Int(tokens[1]),
                          symSize > 0 else { continue }
                    let symType = tokens[2]
                    let symName = tokens.dropFirst(3).joined(separator: " ")
                    let region: String
                    switch symType {
                    case "B", "b": region = "SRAM (.bss)"
                    case "D", "d": region = "SRAM (.data)"
                    case "R", "r": region = "Flash (.rodata)"
                    case "T", "t": region = "Flash/IRAM (.text)"
                    default: region = "Section (\(symType))"
                    }
                    topSymbols.append(ELFSymbolInfo(
                        name: symName,
                        sizeBytes: symSize,
                        symbolType: symType,
                        regionLabel: region
                    ))
                    if topSymbols.count >= 25 { break }
                }
            }

            sections.sort { $0.sizeBytes > $1.sizeBytes }
            return ELFMemoryReport(
                elfPath: elfPath,
                timestamp: Date(),
                flashUsedBytes: flashBytes,
                flashCapacityBytes: caps.flashBytes,
                ramUsedBytes: ramBytes,
                ramCapacityBytes: caps.ramBytes,
                iramUsedBytes: iramBytes,
                sections: sections,
                topSymbols: topSymbols
            )
        }.value

        if let report {
            self.latestELFPath = elfPath
            self.latestReport = report
        }
        return report
    }

    func symbolicateCrash(rawInput: String, board: HardwareBoardTarget, explicitELFPath: String? = nil) async -> (formattedText: String, frames: [DecodedStackFrame]) {
        let elfCandidate = explicitELFPath ?? latestELFPath
        return await Task.detached(priority: .userInitiated) {
            var out = "================================================================\n"
            out += "  MICROCODE ZERO-MOCK DWARF / ELF CRASH SYMBOLICATOR\n"
            out += "================================================================\n\n"

            // 1. Decode Fault Reason
            if let range = rawInput.range(of: "Core\\s+\\d+\\s+panic'ed\\s*\\([^)]+\\)", options: .regularExpression) {
                let reason = String(rawInput[range])
                out += "▶ HARDWARE FAULT: \(reason)\n"
                if reason.contains("LoadProhibited") {
                    out += "  Cause: CPU attempted to read from an unmapped/NULL address (check EXCVADDR below).\n"
                } else if reason.contains("StoreProhibited") {
                    out += "  Cause: CPU attempted to write to a NULL pointer or read-only Flash address.\n"
                } else if reason.contains("InstrFetchProhibited") {
                    out += "  Cause: Corrupted function pointer or stack overflow jumped to non-executable memory.\n"
                } else if reason.contains("Interrupt wdt") || reason.contains("Task watchdog") {
                    out += "  Cause: Watchdog starvation — ISR or FreeRTOS task blocked without yielding.\n"
                }
                out += "\n"
            } else if rawInput.localizedCaseInsensitiveContains("HardFault") {
                out += "▶ HARDWARE FAULT: ARM Cortex-M HardFault Exception\n\n"
            }

            // 2. Extract PC:SP pairs
            var rawFrames: [(pc: String, sp: String?)] = []
            if let btRange = rawInput.range(of: "Backtrace:[^\\n]+", options: .regularExpression) {
                let btLine = String(rawInput[btRange])
                    .replacingOccurrences(of: "Backtrace:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                for token in btLine.components(separatedBy: .whitespaces) where !token.isEmpty {
                    let parts = token.components(separatedBy: ":")
                    if parts.count == 2 && parts[0].hasPrefix("0x") {
                        rawFrames.append((pc: Self.unmaskXtensaPC(parts[0], board: board), sp: parts[1]))
                    } else if parts[0].hasPrefix("0x") {
                        rawFrames.append((pc: Self.unmaskXtensaPC(parts[0], board: board), sp: nil))
                    }
                }
            }
            if rawFrames.isEmpty,
               let regex = try? NSRegularExpression(pattern: "0x[0-9a-fA-F]{8}") {
                let ns = rawInput as NSString
                for m in regex.matches(in: rawInput, range: NSRange(location: 0, length: ns.length)).prefix(12) {
                    let addr = ns.substring(with: m.range)
                    rawFrames.append((pc: Self.unmaskXtensaPC(addr, board: board), sp: nil))
                }
            }

            var decodedFrames: [DecodedStackFrame] = []
            let validELF = (elfCandidate != nil && FileManager.default.fileExists(atPath: elfCandidate!)) ? elfCandidate : nil
            let addr2line = Self.findBinutilsTool("addr2line", board: board)

            if let elf = validELF, let tool = addr2line, !rawFrames.isEmpty {
                out += "▶ ELF BINARY : \(elf)\n"
                out += "▶ SYMBOLIZER : \((tool as NSString).lastPathComponent)\n\n"

                let pcs = rawFrames.map(\.pc)
                let args: [String]
                if tool.hasSuffix("llvm-symbolizer") {
                    args = ["--obj=\(elf)", "--functions", "--inlining=false", "--demangle"] + pcs
                } else {
                    args = ["-pfiaC", "-e", elf] + pcs
                }
                let symOut = Self.runProcessCapture(executable: tool, args: args)
                let symLines = symOut.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                for (idx, frame) in rawFrames.enumerated() {
                    let lineStr = idx < symLines.count ? symLines[idx] : ""
                    let parsed = Self.parseAddr2LineOutput(lineStr)
                    let region = Self.classifyAddressRegion(frame.pc)
                    decodedFrames.append(DecodedStackFrame(
                        index: idx,
                        pcHex: frame.pc,
                        spHex: frame.sp,
                        functionName: parsed.function,
                        filePath: parsed.file,
                        lineNumber: parsed.line,
                        memoryRegion: region
                    ))
                    let locStr = parsed.file != nil ? "\(parsed.file!):\(parsed.line ?? 0)" : region
                    out += String(format: "  #%-2d %@  %@\n      at %@\n", idx, frame.pc, parsed.function, locStr)
                }
            } else {
                if validELF == nil {
                    out += "▶ NOTE: No compiled .elf artifact yet. Compile the project once ('COMPILE ONLY') so DWARF line numbers are available.\n\n"
                } else if addr2line == nil {
                    out += "▶ NOTE: Toolchain addr2line binary not found on disk; showing physical memory map classification.\n\n"
                }
                for (idx, frame) in rawFrames.enumerated() {
                    let region = Self.classifyAddressRegion(frame.pc)
                    decodedFrames.append(DecodedStackFrame(
                        index: idx,
                        pcHex: frame.pc,
                        spHex: frame.sp,
                        functionName: "(Compile .elf to resolve C++ symbol)",
                        filePath: nil,
                        lineNumber: nil,
                        memoryRegion: region
                    ))
                    out += String(format: "  #%-2d %@  [%@]\n", idx, frame.pc, region)
                }
            }

            return (out, decodedFrames)
        }.value
    }

    nonisolated private static func unmaskXtensaPC(_ hex: String, board: HardwareBoardTarget) -> String {
        guard board == .esp32s3,
              let val = UInt32(hex.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
            return hex
        }
        // Xtensa Windowed ABI stores 2-bit window increment in top 2 bits of return address
        if (val & 0xC000_0000) != 0x4000_0000 && (val & 0x3FFF_FFFF) >= 0x0000_1000 {
            let candidate = (val & 0x3FFF_FFFF) | 0x4000_0000
            return String(format: "0x%08X", candidate)
        }
        return String(format: "0x%08X", val)
    }

    nonisolated private static func parseAddr2LineOutput(_ raw: String) -> (function: String, file: String?, line: Int?) {
        // Format: "0x42001a3c: setup() at /path/src/main.cpp:42"
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colonRange = cleaned.range(of: "^0x[0-9a-fA-F]+:\\s*", options: .regularExpression) {
            cleaned.removeSubrange(colonRange)
        }
        let parts = cleaned.components(separatedBy: " at ")
        let fn = parts.first?.trimmingCharacters(in: .whitespaces) ?? "??"
        guard parts.count >= 2 else {
            return (fn == "??" ? "(Boot ROM / Unknown Symbol)" : fn, nil, nil)
        }
        let locPart = parts.dropFirst().joined(separator: " at ")
            .replacingOccurrences(of: " (discriminator.*)", with: "", options: .regularExpression)
        if let lastColon = locPart.lastIndex(of: ":") {
            let fileStr = String(locPart[..<lastColon]).trimmingCharacters(in: .whitespaces)
            let lineStr = String(locPart[locPart.index(after: lastColon)...]).trimmingCharacters(in: .whitespaces)
            if fileStr != "??", let ln = Int(lineStr) {
                return (fn, fileStr, ln)
            }
        }
        return (fn, nil, nil)
    }

    nonisolated private static func classifyAddressRegion(_ hex: String) -> String {
        guard let addr = UInt32(hex.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
            return "Unknown Address Space"
        }
        switch addr {
        case 0x0800_0000..<0x0820_0000: return "STM32 Internal Flash (.text)"
        case 0x1000_0000..<0x1100_0000: return "RP2040/RP2350 XIP QSPI Flash"
        case 0x2000_0000..<0x2010_0000: return "ARM Cortex-M Internal SRAM"
        case 0x4000_0000..<0x4007_0000: return "ESP32 Mask Boot ROM"
        case 0x4008_0000..<0x400A_0000, 0x4037_0000..<0x403E_0000: return "ESP32 Internal IRAM (ISR / Fast Code)"
        case 0x400D_0000..<0x4040_0000, 0x4200_0000..<0x4400_0000: return "ESP32 SPI Flash IROM (Application Firmware)"
        case 0x3F40_0000..<0x3F80_0000, 0x3C00_0000..<0x3E00_0000: return "ESP32 SPI Flash DROM (Read-Only Data)"
        case 0x3FC8_0000..<0x4000_0000: return "ESP32 Internal DRAM (Heap / Task Stack)"
        default: return "Mapped Peripheral / External PSRAM"
        }
    }

    nonisolated fileprivate static func runProcessCapture(executable: String, args: [String], env: [String: String]? = nil) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let env { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

// MARK: - 3. Real Cross-Toolchain Firmware Build & Flash Service (Zero-Mock)

enum EmbeddedToolchainBackend: String {
    case espIdf = "ESP-IDF (idf.py)"
    case platformIO = "PlatformIO (pio)"
    case arduinoCLI = "Arduino CLI"
    case microPythonREPL = "MicroPython Raw-REPL"
}

struct FirmwareCompileOutcome {
    let success: Bool
    let backend: EmbeddedToolchainBackend?
    let elfPath: String?
    let binaryPath: String?
    let memoryReport: ELFMemoryReport?
    let missingToolchainHint: String?
    let fullLog: String
}

@MainActor
final class EmbeddedToolchainService: ObservableObject {
    static let shared = EmbeddedToolchainService()

    @Published private(set) var detectedPioPath: String?
    @Published private(set) var detectedArduinoCliPath: String?
    @Published private(set) var detectedEsptoolPath: String?
    @Published private(set) var detectedDfuUtilPath: String?
    @Published private(set) var detectedPicotoolPath: String?
    @Published private(set) var detectedOpenOcdPath: String?
    @Published var isInstallingCore: Bool = false

    private init() {
        refreshToolchains()
    }

    func refreshToolchains() {
        detectedPioPath = Self.locateExecutable(names: ["pio", "platformio"], extraDirs: [
            "\(NSHomeDirectory())/.platformio/penv/bin"
        ])
        detectedArduinoCliPath = Self.locateExecutable(names: ["arduino-cli"], extraDirs: [])
        detectedEsptoolPath = Self.locateExecutable(names: ["esptool.py", "esptool"], extraDirs: [
            "\(NSHomeDirectory())/.platformio/penv/bin"
        ])
        detectedDfuUtilPath = Self.locateExecutable(names: ["dfu-util"], extraDirs: [])
        detectedPicotoolPath = Self.locateExecutable(names: ["picotool"], extraDirs: [])
        detectedOpenOcdPath = Self.locateExecutable(names: ["openocd"], extraDirs: [])
    }

    nonisolated static func locateExecutable(names: [String], extraDirs: [String]) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = extraDirs + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/usr/bin"
        ]
        // Also search Arduino15 & PlatformIO package bin folders for esptool/openocd/dfu-util
        for pkgRoot in ["\(home)/.platformio/packages", "\(home)/Library/Arduino15/packages", "\(home)/.microcode/arduino15/packages"] {
            if fm.fileExists(atPath: pkgRoot),
               let items = try? fm.contentsOfDirectory(atPath: pkgRoot) {
                for item in items {
                    dirs.append("\(pkgRoot)/\(item)/bin")
                }
            }
        }
        for name in names {
            for dir in dirs {
                let full = "\(dir)/\(name)"
                if fm.isExecutableFile(atPath: full) {
                    return full
                }
            }
        }
        return nil
    }

    /// Ensures `arduino-cli` never crashes if `~/Library/Arduino15` is an unmounted external drive symlink.
    nonisolated static func buildSubprocessEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.platformio/penv/bin:\(home)/.cargo/bin:\(existingPath)"

        let defaultArduino15 = "\(home)/Library/Arduino15"
        var isDir: ObjCBool = false
        let existsAndWritable = FileManager.default.fileExists(atPath: defaultArduino15, isDirectory: &isDir) && isDir.boolValue
        if !existsAndWritable {
            let fallbackDir = "\(home)/.microcode/arduino15"
            try? FileManager.default.createDirectory(atPath: fallbackDir, withIntermediateDirectories: true)
            env["ARDUINO_DIRECTORIES_DATA"] = fallbackDir
            env["ARDUINO_DIRECTORIES_DOWNLOADS"] = "\(fallbackDir)/staging"
            env["ARDUINO_DIRECTORIES_USER"] = "\(home)/Documents/MicroCodeEmbedded/ArduinoLibraries"
        }
        return env
    }

    static func boardParameters(for board: HardwareBoardTarget) -> (pioPlatform: String, pioBoard: String, arduinoCore: String, arduinoFQBN: String, boardUrl: String?) {
        switch board {
        case .esp32s3:
            return (
                "espressif32",
                "esp32-s3-devkitc-1",
                "esp32:esp32",
                "esp32:esp32:esp32s3",
                "https://espressif.github.io/arduino-esp32/package_esp32_index.json"
            )
        case .esp32c3:
            return (
                "espressif32",
                "esp32-c3-devkitm-1",
                "esp32:esp32",
                "esp32:esp32:esp32c3",
                "https://espressif.github.io/arduino-esp32/package_esp32_index.json"
            )
        case .picoW:
            return (
                "raspberrypi",
                "pico",
                "rp2040:rp2040",
                "rp2040:rp2040:rpipicow",
                "https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json"
            )
        case .arduinoUnoR4:
            return (
                "renesas-ra",
                "uno_r4_wifi",
                "arduino:renesas_uno",
                "arduino:renesas_uno:unor4wifi",
                nil
            )
        case .stm32f4:
            return (
                "ststm32",
                "nucleo_f446re",
                "STMicroelectronics:stm32",
                "STMicroelectronics:stm32:GenF4",
                "https://github.com/stm32duino/BoardManagerFiles/raw/main/package_stmicroelectronics_index.json"
            )
        }
    }

    /// Resolves either the user's real Embedded workspace folder or a persistent project directory under `~/Documents/MicroCodeEmbedded/<board>/`.
    func prepareRealProjectDirectory(
        sourceCode: String,
        language: EmbeddedSourceLanguage,
        board: HardwareBoardTarget,
        workspaceURL: URL?
    ) throws -> URL {
        let fm = FileManager.default
        let params = Self.boardParameters(for: board)

        // Check if active MicroCode Workspace is already a real PlatformIO / ESP-IDF / Arduino project
        if let ws = workspaceURL {
            let pioIni = ws.appendingPathComponent("platformio.ini")
            let idfCmake = ws.appendingPathComponent("CMakeLists.txt")
            if fm.fileExists(atPath: pioIni.path) {
                let srcMain = ws.appendingPathComponent("src/main.\(language == .c ? "c" : "cpp")")
                try fm.createDirectory(at: ws.appendingPathComponent("src"), withIntermediateDirectories: true)
                try sourceCode.write(to: srcMain, atomically: true, encoding: .utf8)
                return ws
            }
            if fm.fileExists(atPath: idfCmake.path),
               let cmakeText = try? String(contentsOf: idfCmake),
               cmakeText.contains("project.cmake") {
                let mainFile = ws.appendingPathComponent("main/main.\(language == .c ? "c" : "cpp")")
                try fm.createDirectory(at: ws.appendingPathComponent("main"), withIntermediateDirectories: true)
                try sourceCode.write(to: mainFile, atomically: true, encoding: .utf8)
                return ws
            }
        }

        // Persistent multi-file Embedded project directory (never ephemeral /tmp synthetic stubs)
        let slug = params.pioBoard.replacingOccurrences(of: "_", with: "-")
        let rootDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MicroCodeEmbedded/\(slug)", isDirectory: true)
        let srcDir = rootDir.appendingPathComponent("src", isDirectory: true)
        let sketchDir = rootDir.appendingPathComponent(slug, isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sketchDir, withIntermediateDirectories: true)

        if language == .micropython {
            let pyFile = rootDir.appendingPathComponent("main.py")
            try sourceCode.write(to: pyFile, atomically: true, encoding: .utf8)
            return rootDir
        }

        // Write PlatformIO configuration
        let pioIniContent = """
        ; MicroCode Zero-Mock Embedded Project (\(board.rawValue))
        [env:\(params.pioBoard)]
        platform = \(params.pioPlatform)
        board = \(params.pioBoard)
        framework = arduino
        monitor_speed = 115200
        """
        try pioIniContent.write(to: rootDir.appendingPathComponent("platformio.ini"), atomically: true, encoding: .utf8)

        // Ensure `#include <Arduino.h>` is present for C++ Arduino framework builds if user omitted it
        let normalizedCpp: String
        if (language == .arduino || language == .cpp) && !sourceCode.contains("Arduino.h") && (sourceCode.contains("void setup") || sourceCode.contains("Serial.")) {
            normalizedCpp = "#include <Arduino.h>\n" + sourceCode
        } else {
            normalizedCpp = sourceCode
        }
        try normalizedCpp.write(to: srcDir.appendingPathComponent("main.cpp"), atomically: true, encoding: .utf8)
        try normalizedCpp.write(to: sketchDir.appendingPathComponent("\(slug).ino"), atomically: true, encoding: .utf8)

        return rootDir
    }

    // MARK: Real Cross-Compilation (Zero-Mock)

    func compileFirmware(
        sourceCode: String,
        language: EmbeddedSourceLanguage,
        board: HardwareBoardTarget,
        workspaceURL: URL?,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> FirmwareCompileOutcome {
        refreshToolchains()
        var fullLog = ""
        let emit: @MainActor (String) -> Void = { chunk in
            fullLog += chunk
            onLog(chunk)
        }

        let projectDir: URL
        do {
            projectDir = try prepareRealProjectDirectory(
                sourceCode: sourceCode,
                language: language,
                board: board,
                workspaceURL: workspaceURL
            )
            emit("[PROJECT] Synced real firmware workspace: \(projectDir.path)\n")
        } catch {
            let msg = "[ERROR] Failed to prepare project directory: \(error.localizedDescription)\n"
            emit(msg)
            return FirmwareCompileOutcome(success: false, backend: nil, elfPath: nil, binaryPath: nil, memoryReport: nil, missingToolchainHint: nil, fullLog: fullLog)
        }

        // 1. MicroPython Real Bytecode Verification
        if language == .micropython {
            let pyExec = Self.locateExecutable(names: ["python3"], extraDirs: []) ?? "/usr/bin/python3"
            let pyFile = projectDir.appendingPathComponent("main.py").path
            emit("[MICROPYTHON] Validating bytecode AST via \(pyExec) -m py_compile...\n")
            let (exitCode, out) = await Self.streamProcess(
                executable: pyExec,
                args: ["-m", "py_compile", pyFile],
                cwd: projectDir,
                env: Self.buildSubprocessEnvironment(),
                onChunk: emit
            )
            if exitCode == 0 {
                emit("[SUCCESS] MicroPython script verified (\(sourceCode.utf8.count) bytes). Ready for Raw-REPL hardware transfer.\n")
                return FirmwareCompileOutcome(success: true, backend: .microPythonREPL, elfPath: nil, binaryPath: pyFile, memoryReport: nil, missingToolchainHint: nil, fullLog: fullLog)
            } else {
                emit("[ERROR] MicroPython syntax error:\n\(out)\n")
                return FirmwareCompileOutcome(success: false, backend: .microPythonREPL, elfPath: nil, binaryPath: nil, memoryReport: nil, missingToolchainHint: nil, fullLog: fullLog)
            }
        }

        let params = Self.boardParameters(for: board)
        let env = Self.buildSubprocessEnvironment()

        // 2. Native ESP-IDF (if configured)
        if board.isEsp32Family && EmbeddedEnvManager.shared.isEspIdfConfigured && (language == .cpp || language == .c) {
            let target = board.idfTarget ?? "esp32s3"
            emit("[TOOLCHAIN] Using real ESP-IDF (\(EmbeddedEnvManager.shared.idfPath)) target=\(target)\n")
            let idfDir = EmbeddedEnvManager.shared.generateTransientEspIdfProject(sourceCode: sourceCode, targetBoard: target)
            let ok: Bool = await withCheckedContinuation { cont in
                EmbeddedEnvManager.shared.buildEspIdfProject(projectDir: idfDir, targetBoard: target, onOutput: { chunk in
                    Task { @MainActor in emit(chunk) }
                }, completion: { success, _ in
                    cont.resume(returning: success)
                })
            }
            let elfPath = "\(idfDir)/build/microcode_sketch.elf"
            let binPath = "\(idfDir)/build/microcode_sketch.bin"
            var report: ELFMemoryReport? = nil
            if ok {
                ELFMemoryAndDwarfService.shared.latestFirmwareBinPath = binPath
                report = await ELFMemoryAndDwarfService.shared.inspectELF(at: elfPath, board: board)
                if let r = report {
                    emit(Self.formatMemoryBanner(r))
                }
            }
            return FirmwareCompileOutcome(success: ok, backend: .espIdf, elfPath: ok ? elfPath : nil, binaryPath: ok ? binPath : nil, memoryReport: report, missingToolchainHint: nil, fullLog: fullLog)
        }

        // 3. Arduino CLI (if corresponding core is already installed)
        if let arduinoCli = detectedArduinoCliPath {
            let coreCheck = ELFMemoryAndDwarfService.runProcessCapture(
                executable: arduinoCli,
                args: ["core", "list"],
                env: env
            )
            if coreCheck.contains(params.arduinoCore) {
                let slug = params.pioBoard.replacingOccurrences(of: "_", with: "-")
                let sketchDir = projectDir.appendingPathComponent(slug)
                let buildDir = projectDir.appendingPathComponent("build-arduino")
                try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)

                emit("[TOOLCHAIN] Arduino CLI (\(arduinoCli)) → FQBN: \(params.arduinoFQBN)\n")
                let (code, _) = await Self.streamProcess(
                    executable: arduinoCli,
                    args: ["compile", "--fqbn", params.arduinoFQBN, "--build-path", buildDir.path, "--export-binaries", sketchDir.path],
                    cwd: projectDir,
                    env: env,
                    onChunk: emit
                )
                let (elf, bin) = Self.findCompiledArtifacts(in: buildDir)
                var report: ELFMemoryReport? = nil
                if code == 0, let elf {
                    if let bin { ELFMemoryAndDwarfService.shared.latestFirmwareBinPath = bin }
                    report = await ELFMemoryAndDwarfService.shared.inspectELF(at: elf, board: board)
                    if let r = report { emit(Self.formatMemoryBanner(r)) }
                }
                return FirmwareCompileOutcome(
                    success: code == 0,
                    backend: .arduinoCLI,
                    elfPath: elf,
                    binaryPath: bin,
                    memoryReport: report,
                    missingToolchainHint: nil,
                    fullLog: fullLog
                )
            }
        }

        // 4. PlatformIO (`pio run`) — Real Cross-Compiler & Linker
        if let pio = detectedPioPath {
            emit("[TOOLCHAIN] PlatformIO Core (\(pio)) → env:\(params.pioBoard) (\(params.pioPlatform))\n")
            let (code, _) = await Self.streamProcess(
                executable: pio,
                args: ["run", "-e", params.pioBoard],
                cwd: projectDir,
                env: env,
                onChunk: emit
            )
            let pioBuildDir = projectDir.appendingPathComponent(".pio/build/\(params.pioBoard)")
            let (elf, bin) = Self.findCompiledArtifacts(in: pioBuildDir)
            var report: ELFMemoryReport? = nil
            if code == 0 {
                if let bin { ELFMemoryAndDwarfService.shared.latestFirmwareBinPath = bin }
                if let elf {
                    report = await ELFMemoryAndDwarfService.shared.inspectELF(at: elf, board: board)
                    if let r = report { emit(Self.formatMemoryBanner(r)) }
                }
                emit("\n[SUCCESS] Real target MCU firmware linked: \(bin ?? elf ?? pioBuildDir.path)\n")
            } else {
                emit("\n[FAILED] Cross-compilation exited with status \(code).\n")
            }
            return FirmwareCompileOutcome(
                success: code == 0,
                backend: .platformIO,
                elfPath: elf,
                binaryPath: bin,
                memoryReport: report,
                missingToolchainHint: nil,
                fullLog: fullLog
            )
        }

        // 5. Arduino CLI present, but target core not yet installed — report honestly (ZERO MOCK!)
        if detectedArduinoCliPath != nil {
            let hint = "Arduino core '\(params.arduinoCore)' for \(board.rawValue) is not installed yet. Click 'INSTALL \(params.arduinoCore.uppercased()) CORE' to download the real cross-compiler."
            emit("\n[TOOLCHAIN MISSING] \(hint)\n")
            emit("[ZERO-MOCK POLICY] Host macOS clang syntax-only fallback is disabled; real MCU cross-compiler is required to produce a flashable firmware image.\n")
            return FirmwareCompileOutcome(
                success: false,
                backend: nil,
                elfPath: nil,
                binaryPath: nil,
                memoryReport: nil,
                missingToolchainHint: hint,
                fullLog: fullLog
            )
        }

        let hint = "No MCU cross-toolchain (pio / arduino-cli / idf.py) found for \(board.rawValue). Install via 'brew install platformio' or 'brew install arduino-cli'."
        emit("\n[TOOLCHAIN MISSING] \(hint)\n")
        return FirmwareCompileOutcome(
            success: false,
            backend: nil,
            elfPath: nil,
            binaryPath: nil,
            memoryReport: nil,
            missingToolchainHint: hint,
            fullLog: fullLog
        )
    }

    // MARK: 1-Click Real Core Bootstrapper

    func installToolchainCore(
        for board: HardwareBoardTarget,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        refreshToolchains()
        let params = Self.boardParameters(for: board)
        let env = Self.buildSubprocessEnvironment()
        isInstallingCore = true
        defer { isInstallingCore = false }

        if let arduinoCli = detectedArduinoCliPath {
            onLog("[BOOTSTRAP] Installing real Arduino core '\(params.arduinoCore)' via \(arduinoCli)...\n")
            var indexArgs = ["core", "update-index"]
            if let url = params.boardUrl {
                indexArgs += ["--additional-urls", url]
            }
            _ = await Self.streamProcess(executable: arduinoCli, args: indexArgs, cwd: nil, env: env, onChunk: onLog)

            var installArgs = ["core", "install", params.arduinoCore]
            if let url = params.boardUrl {
                installArgs += ["--additional-urls", url]
            }
            let (code, _) = await Self.streamProcess(executable: arduinoCli, args: installArgs, cwd: nil, env: env, onChunk: onLog)
            onLog(code == 0 ? "\n[SUCCESS] Installed real cross-compiler core '\(params.arduinoCore)'.\n" : "\n[ERROR] Core install exited with \(code).\n")
            return code == 0
        }

        if let pio = detectedPioPath {
            onLog("[BOOTSTRAP] Installing real PlatformIO platform '\(params.pioPlatform)' via \(pio)...\n")
            let (code, _) = await Self.streamProcess(executable: pio, args: ["pkg", "install", "-g", "-p", params.pioPlatform], cwd: nil, env: env, onChunk: onLog)
            return code == 0
        }

        onLog("[ERROR] Neither arduino-cli nor pio is installed. Run `brew install arduino-cli` or `brew install platformio`.\n")
        return false
    }

    // MARK: Real Hardware Flashing (Zero-Mock)

    func flashToBoard(
        sourceCode: String,
        language: EmbeddedSourceLanguage,
        board: HardwareBoardTarget,
        portPath: String,
        workspaceURL: URL?,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        // Step 1: Always perform a real cross-compile first
        let compileResult = await compileFirmware(
            sourceCode: sourceCode,
            language: language,
            board: board,
            workspaceURL: workspaceURL,
            onLog: onLog
        )
        guard compileResult.success else {
            onLog("\n[ABORTED] Flash cancelled because real firmware compilation did not succeed.\n")
            return false
        }

        let params = Self.boardParameters(for: board)
        let env = Self.buildSubprocessEnvironment()
        let projectDir = try? prepareRealProjectDirectory(sourceCode: sourceCode, language: language, board: board, workspaceURL: workspaceURL)

        // Step 2: Route to real hardware uploader matching the backend
        switch compileResult.backend {
        case .microPythonREPL:
            onLog("\n[RAW-REPL] Uploading main.py directly to MicroPython flash filesystem on \(portPath)...\n")
            return await Self.uploadMicroPythonViaRawREPL(script: sourceCode, portPath: portPath, onLog: onLog)

        case .espIdf:
            let target = board.idfTarget ?? "esp32s3"
            let idfDir = EmbeddedEnvManager.shared.generateTransientEspIdfProject(sourceCode: sourceCode, targetBoard: target)
            return await withCheckedContinuation { cont in
                EmbeddedEnvManager.shared.flashEspIdfProject(projectDir: idfDir, port: portPath, baud: "460800", onOutput: { chunk in
                    Task { @MainActor in onLog(chunk) }
                }, completion: { ok, _ in
                    cont.resume(returning: ok)
                })
            }

        case .arduinoCLI:
            guard let arduinoCli = detectedArduinoCliPath, let projectDir else { return false }
            let slug = params.pioBoard.replacingOccurrences(of: "_", with: "-")
            let sketchDir = projectDir.appendingPathComponent(slug)
            let buildDir = projectDir.appendingPathComponent("build-arduino")
            onLog("\n[UPLOAD] Flashing real binary via arduino-cli upload → \(portPath)...\n")
            let (code, _) = await Self.streamProcess(
                executable: arduinoCli,
                args: ["upload", "-p", portPath, "--fqbn", params.arduinoFQBN, "--input-dir", buildDir.path, sketchDir.path],
                cwd: projectDir,
                env: env,
                onChunk: onLog
            )
            return code == 0

        case .platformIO:
            guard let pio = detectedPioPath, let projectDir else { return false }
            // Check RP2040 UF2 BOOTSEL volume shortcut if Pico is already in BOOTSEL or needs 1200bps touch
            if board == .picoW, let uf2 = compileResult.binaryPath, uf2.hasSuffix(".uf2") {
                onLog("\n[RP2040] Triggering 1200-baud BOOTSEL reset on \(portPath) and deploying UF2...\n")
                if await Self.deployUF2ToPico(uf2Path: uf2, serialPortPath: portPath, onLog: onLog) {
                    return true
                }
            }
            onLog("\n[UPLOAD] Flashing real firmware via PlatformIO → \(portPath)...\n")
            let (code, _) = await Self.streamProcess(
                executable: pio,
                args: ["run", "-e", params.pioBoard, "-t", "upload", "--upload-port", portPath],
                cwd: projectDir,
                env: env,
                onChunk: onLog
            )
            return code == 0

        case .none:
            return false
        }
    }

    // MARK: Real RP2040 / RP2350 1200-Baud Touch + UF2 Mass-Storage Deployer

    nonisolated private static func deployUF2ToPico(
        uf2Path: String,
        serialPortPath: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: uf2Path) else { return false }

        // If BOOTSEL drive isn't mounted yet, perform real 1200-baud DTR touch
        func findUF2Mount() -> URL? {
            let vols = fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
            return vols.first { url in
                let n = url.lastPathComponent.uppercased()
                return n.contains("RPI-RP2") || n.contains("RP2350") || fm.fileExists(atPath: url.appendingPathComponent("INFO_UF2.TXT").path)
            }
        }

        if findUF2Mount() == nil {
            let fd = Darwin.open(serialPortPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
            if fd >= 0 {
                var opts = termios()
                tcgetattr(fd, &opts)
                cfsetspeed(&opts, speed_t(B1200))
                tcsetattr(fd, TCSANOW, &opts)
                usleep(40_000)
                Darwin.close(fd)
            }
            for _ in 0..<20 {
                if findUF2Mount() != nil { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        guard let mountURL = findUF2Mount() else { return false }
        let dest = mountURL.appendingPathComponent((uf2Path as NSString).lastPathComponent)
        do {
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.copyItem(at: URL(fileURLWithPath: uf2Path), to: dest)
            await MainActor.run {
                onLog("[UF2] Copied \((uf2Path as NSString).lastPathComponent) directly to \(mountURL.path). Board is rebooting into new firmware.\n")
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Real MicroPython POSIX Raw-REPL (`0x01` / `0x04`) Flash Uploader

    nonisolated private static func uploadMicroPythonViaRawREPL(
        script: String,
        portPath: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        let fd = Darwin.open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let errText = String(cString: strerror(errno))
            await MainActor.run { onLog("[ERROR] Cannot open \(portPath): \(errText)\n") }
            return false
        }
        defer { Darwin.close(fd) }

        var options = termios()
        tcgetattr(fd, &options)
        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB)
        tcsetattr(fd, TCSANOW, &options)

        func writeBytes(_ bytes: [UInt8]) {
            bytes.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = Darwin.write(fd, base, bytes.count)
                }
            }
        }

        func readUntil(contains token: String, timeoutMs: Int) -> String {
            var collected = Data()
            var buf = [UInt8](repeating: 0, count: 256)
            let steps = max(1, timeoutMs / 20)
            for _ in 0..<steps {
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 {
                    collected.append(contentsOf: buf[0..<n])
                    let str = String(decoding: collected, as: UTF8.self)
                    if str.contains(token) { return str }
                } else {
                    usleep(20_000)
                }
            }
            return String(decoding: collected, as: UTF8.self)
        }

        // Ctrl-C twice to interrupt running user program, then Ctrl-A (0x01) for Raw REPL
        writeBytes([0x03, 0x03])
        usleep(80_000)
        _ = readUntil(contains: ">>>", timeoutMs: 400)
        writeBytes([0x01])
        let banner = readUntil(contains: "raw REPL; CTRL-B to exit", timeoutMs: 1500)
        guard banner.contains("raw REPL") else {
            await MainActor.run {
                onLog("[ERROR] Target on \(portPath) did not respond to MicroPython Raw-REPL handshake (0x01). Verify MicroPython firmware is flashed on the board.\n")
            }
            return false
        }

        let b64 = Data(script.utf8).base64EncodedString()
        let writerPy = """
        import ubinascii
        f = open('main.py', 'wb')
        f.write(ubinascii.a2b_base64('\(b64)'))
        f.close()
        print('MC_SYNC_OK')
        """
        writeBytes(Array(writerPy.utf8))
        writeBytes([0x04]) // Execute in Raw REPL
        let execResp = readUntil(contains: "MC_SYNC_OK", timeoutMs: 3000)
        guard execResp.contains("MC_SYNC_OK") else {
            await MainActor.run {
                onLog("[ERROR] Raw-REPL write failed: \(execResp)\n")
            }
            return false
        }

        // Exit Raw REPL (0x02) and trigger soft reset (0x04) so main.py boots immediately
        writeBytes([0x02])
        usleep(40_000)
        writeBytes([0x04])
        await MainActor.run {
            onLog("[SUCCESS] Wrote main.py (\(script.utf8.count) bytes) via real Raw-REPL and soft-rebooted target.\n")
        }
        return true
    }

    nonisolated private static func findCompiledArtifacts(in dir: URL) -> (elf: String?, binary: String?) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return (nil, nil) }
        var elf: String?
        var bin: String?
        for item in items {
            let full = dir.appendingPathComponent(item).path
            if item.hasSuffix(".elf") {
                elf = full
            } else if item.hasSuffix(".uf2") {
                bin = full
            } else if item == "firmware.bin" || (item.hasSuffix(".bin") && !item.contains("bootloader") && !item.contains("partitions")) {
                if bin == nil { bin = full }
            } else if item.hasSuffix(".hex") && bin == nil {
                bin = full
            }
        }
        return (elf, bin)
    }

    private static func formatMemoryBanner(_ report: ELFMemoryReport) -> String {
        let flashKB = String(format: "%.1f KB", Double(report.flashUsedBytes) / 1024.0)
        let flashMaxKB = String(format: "%.0f KB", Double(report.flashCapacityBytes) / 1024.0)
        let ramKB = String(format: "%.1f KB", Double(report.ramUsedBytes) / 1024.0)
        let ramMaxKB = String(format: "%.0f KB", Double(report.ramCapacityBytes) / 1024.0)
        var text = "\n[ELF MEMORY] Flash: \(flashKB) / \(flashMaxKB) (\(String(format: "%.1f%%", report.flashPercent)))"
        text += " | Static RAM: \(ramKB) / \(ramMaxKB) (\(String(format: "%.1f%%", report.ramPercent)))"
        if report.iramUsedBytes > 0 {
            text += " | IRAM: \(String(format: "%.1f KB", Double(report.iramUsedBytes) / 1024.0))"
        }
        text += "\n"
        return text
    }

    nonisolated static func streamProcess(
        executable: String,
        args: [String],
        cwd: URL?,
        env: [String: String],
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> (Int32, String) {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            proc.environment = env
            if let cwd { proc.currentDirectoryURL = cwd }

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            let handle = pipe.fileHandleForReading

            var totalOutput = ""
            do {
                try proc.run()
                while proc.isRunning {
                    let data = handle.availableData
                    if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                        totalOutput += str
                        await MainActor.run { onChunk(str) }
                    } else {
                        usleep(20_000)
                    }
                }
                let rem = handle.readDataToEndOfFile()
                if !rem.isEmpty, let str = String(data: rem, encoding: .utf8) {
                    totalOutput += str
                    await MainActor.run { onChunk(str) }
                }
                proc.waitUntilExit()
                return (proc.terminationStatus, totalOutput)
            } catch {
                let err = "[EXEC ERROR] \(error.localizedDescription)\n"
                await MainActor.run { onChunk(err) }
                return (-1, err)
            }
        }.value
    }
}

// MARK: - 4. Real Network.framework Bonjour/mDNS Discovery & Real ESPOTA / HTTP OTA Service

struct DiscoveredIoTNode: Identifiable, Hashable {
    var id: String { "\(serviceName)|\(serviceType)|\(ipAddress):\(port)" }
    let serviceName: String
    let serviceType: String
    let hostname: String
    let ipAddress: String
    let port: Int
    let boardHint: String
    let authRequired: Bool
    let txtRecords: [String: String]

    var wirelessOtaNode: WirelessOtaNode {
        WirelessOtaNode(
            name: serviceName,
            ip: ipAddress,
            port: port,
            board: boardHint,
            rssi: 0,
            status: authRequired ? "AUTH REQUIRED" : "ONLINE (\(serviceType))"
        )
    }
}

@MainActor
final class IoTNetworkDiscoveryService: NSObject, ObservableObject, NetServiceDelegate {
    static let shared = IoTNetworkDiscoveryService()

    @Published private(set) var discoveredNodes: [DiscoveredIoTNode] = []
    @Published private(set) var isBrowsing: Bool = false

    private var browsers: [NWBrowser] = []
    private var resolvingServices: [NetService] = []
    private let browserQueue = DispatchQueue(label: "com.dotmini.microcode.mdns.browser")
    private var onScanLog: ((String) -> Void)?

    private let serviceTypes = [
        "_arduino._tcp",
        "_esphomelib._tcp",
        "_mqtt._tcp",
        "_http._tcp"
    ]

    func startRealDiscovery(durationSeconds: Double = 4.0, onLog: @escaping (String) -> Void) {
        stopDiscovery()
        discoveredNodes.removeAll()
        resolvingServices.removeAll()
        onScanLog = onLog
        isBrowsing = true

        onLog("[mDNS] Starting real Apple Network.framework NWBrowser across \(serviceTypes.joined(separator: ", ")) on local. domain...\n")

        for type in serviceTypes {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: params)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    self?.handleBrowseResults(results, serviceType: type)
                }
            }
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    Task { @MainActor in
                        self?.onScanLog?("[mDNS WARN] \(type) browser error: \(err.localizedDescription)\n")
                    }
                }
            }
            browser.start(queue: browserQueue)
            browsers.append(browser)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            if self.isBrowsing {
                self.stopDiscovery()
                onLog("[mDNS] Discovery complete: \(self.discoveredNodes.count) real network node(s) responded on local subnet.\n")
            }
        }
    }

    func stopDiscovery() {
        for b in browsers { b.cancel() }
        browsers.removeAll()
        for s in resolvingServices { s.stop() }
        resolvingServices.removeAll()
        isBrowsing = false
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, serviceType: String) {
        for res in results {
            guard case let .service(name, type, domain, _) = res.endpoint else { continue }
            var txtMap: [String: String] = [:]
            if case let .bonjour(txtRecord) = res.metadata {
                for (key, entry) in txtRecord.dictionary {
                    txtMap[key] = entry
                }
            }
            let alreadyQueued = resolvingServices.contains { $0.name == name && $0.type.hasPrefix(type) }
            if !alreadyQueued {
                let ns = NetService(domain: domain, type: type.hasSuffix(".") ? type : "\(type).", name: name)
                ns.delegate = self
                resolvingServices.append(ns)
                ns.resolve(withTimeout: 3.0)
                if !txtMap.isEmpty {
                    pendingTXTRecords["\(name)|\(type)"] = txtMap
                }
            }
        }
    }

    private var pendingTXTRecords: [String: [String: String]] = [:]

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let rawType = sender.type.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let hostName = sender.hostName ?? "\(name).local"
        let port = sender.port
        let addresses = sender.addresses ?? []
        let txtData = sender.txtRecordData()

        var ipv4: String?
        for addrData in addresses {
            addrData.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                if family == sa_family_t(AF_INET) {
                    var sin = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                    var strBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &sin.sin_addr, &strBuf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        ipv4 = String(cString: strBuf)
                    }
                }
            }
            if ipv4 != nil { break }
        }

        var decodedTXT: [String: String] = [:]
        if let txtData {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            for (k, v) in dict {
                decodedTXT[k] = String(data: v, encoding: .utf8) ?? ""
            }
        }

        guard let resolvedIP = ipv4, port > 0 else { return }

        Task { @MainActor in
            let mergedTXT = self.pendingTXTRecords["\(name)|\(rawType)"]?.merging(decodedTXT) { _, new in new } ?? decodedTXT
            let board = mergedTXT["board"] ?? mergedTXT["platform"] ?? (rawType.contains("arduino") ? "ArduinoOTA Node" : rawType)
            let auth = (mergedTXT["auth_upload"] == "yes")
            let node = DiscoveredIoTNode(
                serviceName: name,
                serviceType: rawType,
                hostname: hostName,
                ipAddress: resolvedIP,
                port: port,
                boardHint: board,
                authRequired: auth,
                txtRecords: mergedTXT
            )
            if !self.discoveredNodes.contains(where: { $0.ipAddress == node.ipAddress && $0.port == node.port }) {
                self.discoveredNodes.append(node)
                self.onScanLog?("[FOUND] \(name) (\(board)) at \(resolvedIP):\(port)\n")
            }
        }
    }

    // MARK: Real Wireless OTA Upload (ESPOTA UDP+TCP & HTTP Multipart POST /update)

    func performRealWirelessOTA(
        binaryPath: String,
        targetHost: String,
        targetPort: Int,
        password: String,
        useHTTPMultipart: Bool = false,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: binaryPath),
              let firmwareData = try? Data(contentsOf: URL(fileURLWithPath: binaryPath)),
              !firmwareData.isEmpty else {
            onLog("[OTA ERROR] Firmware file does not exist or is empty: \(binaryPath)\n")
            return false
        }

        let md5Hex = Insecure.MD5.hash(data: firmwareData).map { String(format: "%02x", $0) }.joined()
        let sha256Hex = SHA256.hash(data: firmwareData).map { String(format: "%02x", $0) }.joined()
        onLog("[OTA] Loaded real firmware image (\(firmwareData.count) bytes)\n")
        onLog("[OTA] MD5: \(md5Hex) | SHA256: \(sha256Hex.prefix(16))...\n")

        if useHTTPMultipart || targetPort == 80 || targetPort == 8080 {
            return await uploadHTTPMultipartOTA(
                firmwareData: firmwareData,
                fileName: (binaryPath as NSString).lastPathComponent,
                md5Hex: md5Hex,
                host: targetHost,
                port: targetPort,
                password: password,
                onLog: onLog
            )
        }

        // Prefer real espota.py if present in Arduino15 / PlatformIO packages, otherwise native POSIX ESPOTA protocol
        if let espotaPy = Self.findEspotaPyScript() {
            let pyExec = EmbeddedToolchainService.locateExecutable(names: ["python3"], extraDirs: []) ?? "/usr/bin/python3"
            onLog("[ESPOTA] Executing real toolchain uploader: \(espotaPy) → \(targetHost):\(targetPort)\n")
            var args = [espotaPy, "-i", targetHost, "-p", "\(targetPort)", "-f", binaryPath, "-d"]
            if !password.isEmpty {
                args += ["-a", password]
            }
            let (code, _) = await EmbeddedToolchainService.streamProcess(
                executable: pyExec,
                args: args,
                cwd: nil,
                env: EmbeddedToolchainService.buildSubprocessEnvironment(),
                onChunk: onLog
            )
            return code == 0
        }

        return await uploadNativeESPOTA(
            firmwareData: firmwareData,
            md5Hex: md5Hex,
            host: targetHost,
            port: UInt16(clamping: targetPort),
            password: password,
            onLog: onLog
        )
    }

    nonisolated private static func findEspotaPyScript() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        for root in ["\(home)/.platformio/packages", "\(home)/Library/Arduino15/packages", "\(home)/.microcode/arduino15/packages"] {
            guard fm.fileExists(atPath: root),
                  let enumerator = fm.enumerator(atPath: root) else { continue }
            while let rel = enumerator.nextObject() as? String {
                if rel.hasSuffix("espota.py") {
                    return "\(root)/\(rel)"
                }
            }
        }
        return nil
    }

    private func uploadHTTPMultipartOTA(
        firmwareData: Data,
        fileName: String,
        md5Hex: String,
        host: String,
        port: Int,
        password: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/update") else {
            onLog("[HTTP OTA ERROR] Invalid URL http://\(host):\(port)/update\n")
            return false
        }
        let boundary = "MicroCodeOTABoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(md5Hex, forHTTPHeaderField: "x-MD5")
        if !password.isEmpty, let basic = "admin:\(password)".data(using: .utf8)?.base64EncodedString() {
            req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"MD5\"\r\n\r\n\(md5Hex)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"update\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(firmwareData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        onLog("[HTTP OTA] Uploading \(firmwareData.count) bytes to \(url.absoluteString)...\n")
        let start = CACurrentMediaTime()
        do {
            let (respData, resp) = try await URLSession.shared.upload(for: req, from: body)
            let elapsed = max(0.001, CACurrentMediaTime() - start)
            let kbps = (Double(firmwareData.count) / 1024.0) / elapsed
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let respText = String(data: respData, encoding: .utf8) ?? ""
            onLog("[HTTP OTA] Response HTTP \(status) (\(String(format: "%.1f KB/s", kbps))): \(respText)\n")
            return (200..<300).contains(status)
        } catch {
            onLog("[HTTP OTA ERROR] \(error.localizedDescription)\n")
            return false
        }
    }

    nonisolated private func uploadNativeESPOTA(
        firmwareData: Data,
        md5Hex: String,
        host: String,
        port: UInt16,
        password: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            // 1. Bind real ephemeral TCP server socket to accept board's firmware pull connection
            let listenFD = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard listenFD >= 0 else {
                await MainActor.run { onLog("[ESPOTA ERROR] Failed to allocate TCP socket.\n") }
                return false
            }
            defer { Darwin.close(listenFD) }

            var reuse: Int32 = 1
            setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var localAddr = sockaddr_in()
            localAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            localAddr.sin_family = sa_family_t(AF_INET)
            localAddr.sin_port = 0
            localAddr.sin_addr.s_addr = INADDR_ANY

            let bindRes = withUnsafePointer(to: &localAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindRes == 0, Darwin.listen(listenFD, 1) == 0 else {
                await MainActor.run { onLog("[ESPOTA ERROR] Failed to bind local TCP listener.\n") }
                return false
            }

            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &localAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(listenFD, $0, &len)
                }
            }
            let localTCPPort = UInt16(bigEndian: localAddr.sin_port)

            // 2. Send real UDP ESPOTA Invitation: "0 <localPort> <size> <md5>\n"
            let udpFD = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard udpFD >= 0 else { return false }
            defer { Darwin.close(udpFD) }

            var tv = timeval(tv_sec: 6, tv_usec: 0)
            setsockopt(udpFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var remoteAddr = sockaddr_in()
            remoteAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            remoteAddr.sin_family = sa_family_t(AF_INET)
            remoteAddr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &remoteAddr.sin_addr) == 1 else {
                await MainActor.run { onLog("[ESPOTA ERROR] Invalid IPv4 address: \(host)\n") }
                return false
            }

            let invite = "0 \(localTCPPort) \(firmwareData.count) \(md5Hex)\n"
            await MainActor.run {
                onLog("[ESPOTA] Sending UDP invitation to \(host):\(port) (TCP callback port \(localTCPPort))...\n")
            }

            _ = invite.withCString { cstr in
                withUnsafePointer(to: &remoteAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.sendto(udpFD, cstr, strlen(cstr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            var rxBuf = [UInt8](repeating: 0, count: 256)
            let rxLen = Darwin.recv(udpFD, &rxBuf, rxBuf.count, 0)
            guard rxLen > 0 else {
                await MainActor.run {
                    onLog("[ESPOTA ERROR] Timeout waiting for UDP response from \(host):\(port). Verify the device is powered on, connected to the same Wi-Fi, and running ArduinoOTA.\n")
                }
                return false
            }

            var respStr = String(decoding: rxBuf[0..<rxLen], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            // Handle real ESPOTA Challenge-Response MD5 Authentication ("AUTH <nonce>")
            if respStr.hasPrefix("AUTH ") {
                guard !password.isEmpty else {
                    await MainActor.run { onLog("[ESPOTA ERROR] Device requires OTA password (received AUTH challenge), but password field is empty.\n") }
                    return false
                }
                let nonce = String(respStr.dropFirst(5))
                let passMD5 = Insecure.MD5.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
                let cnonce = Insecure.MD5.hash(data: Data(UUID().uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
                let challenge = "\(passMD5):\(nonce):\(cnonce)"
                let responseHash = Insecure.MD5.hash(data: Data(challenge.utf8)).map { String(format: "%02x", $0) }.joined()
                let authPacket = "200 \(cnonce) \(responseHash)\n"
                _ = authPacket.withCString { cstr in
                    withUnsafePointer(to: &remoteAddr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            Darwin.sendto(udpFD, cstr, strlen(cstr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                let authRx = Darwin.recv(udpFD, &rxBuf, rxBuf.count, 0)
                guard authRx > 0 else {
                    await MainActor.run { onLog("[ESPOTA ERROR] Timeout during OTA authentication.\n") }
                    return false
                }
                respStr = String(decoding: rxBuf[0..<authRx], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let finalResp = respStr
            guard finalResp == "OK" else {
                await MainActor.run { onLog("[ESPOTA ERROR] Device rejected invitation: \(finalResp)\n") }
                return false
            }

            await MainActor.run { onLog("[ESPOTA] Handshake accepted (OK). Waiting for device TCP connection on port \(localTCPPort)...\n") }

            // 3. Accept incoming TCP connection from board (10s timeout via poll)
            var pfd = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&pfd, 1, 10_000) > 0 else {
                await MainActor.run { onLog("[ESPOTA ERROR] Device did not open TCP connection back to Mac (check macOS Firewall).\n") }
                return false
            }

            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let connFD = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listenFD, $0, &clientLen)
                }
            }
            guard connFD >= 0 else { return false }
            defer { Darwin.close(connFD) }

            var tcpTimeout = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(connFD, SOL_SOCKET, SO_RCVTIMEO, &tcpTimeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(connFD, SOL_SOCKET, SO_SNDTIMEO, &tcpTimeout, socklen_t(MemoryLayout<timeval>.size))

            // 4. Stream real 1460-byte firmware chunks and measure real throughput
            let chunkSize = 1460
            var offset = 0
            let startTime = CACurrentMediaTime()
            var lastReportedDecile = -1

            while offset < firmwareData.count {
                let end = min(offset + chunkSize, firmwareData.count)
                let slice = firmwareData[offset..<end]
                let written = slice.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return -1 }
                    return Darwin.send(connFD, base, slice.count, 0)
                }
                guard written > 0 else {
                    let interruptedOffset = offset
                    await MainActor.run { onLog("[ESPOTA ERROR] TCP write interrupted at byte \(interruptedOffset).\n") }
                    return false
                }
                offset += written
                _ = Darwin.recv(connFD, &rxBuf, rxBuf.count, MSG_DONTWAIT)

                let decile = (offset * 10) / firmwareData.count
                if decile > lastReportedDecile {
                    lastReportedDecile = decile
                    let elapsed = max(0.001, CACurrentMediaTime() - startTime)
                    let sentBytes = offset
                    let kbps = (Double(sentBytes) / 1024.0) / elapsed
                    let pct = decile * 10
                    await MainActor.run {
                        onLog(String(format: "[ESPOTA] Transmitted %d / %d bytes (%d%% @ %.1f KB/s)\n", sentBytes, firmwareData.count, pct, kbps))
                    }
                }
            }

            // Wait for final "OK" confirmation from board after MD5 flash verification
            let finalSentBytes = offset
            let finalLen = Darwin.recv(connFD, &rxBuf, rxBuf.count, 0)
            let finalStr = finalLen > 0 ? String(decoding: rxBuf[0..<finalLen], as: UTF8.self) : ""
            if finalStr.contains("OK") {
                await MainActor.run {
                    onLog("[ESPOTA SUCCESS] Board verified MD5 (\(md5Hex)) and rebooted into new firmware slot.\n")
                }
                return true
            } else {
                await MainActor.run {
                    onLog("[ESPOTA WARN] Upload finished (\(finalSentBytes) bytes), final board status: \(finalStr.isEmpty ? "socket closed on reboot" : finalStr)\n")
                }
                return finalSentBytes == firmwareData.count
            }
        }.value
    }
}

// MARK: - 5. Native macOS CoreBluetooth BLE GATT Explorer & Wireless NUS Serial Bridge

struct BLEPeripheralItem: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: Int
    var advertisedServices: [String]
    var manufacturerHex: String
    var lastSeen: Date
}

struct BLEGATTCharacteristicItem: Identifiable {
    var id: String { "\(serviceUUID)|\(characteristic.uuid.uuidString)" }
    let serviceUUID: String
    let characteristic: CBCharacteristic
    var propertiesSummary: String
    var isNotifying: Bool
    var latestHex: String
    var latestUTF8: String
}

@MainActor
final class BLEHardwareInspectorService: NSObject, ObservableObject {
    static let shared = BLEHardwareInspectorService()

    nonisolated static let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated static let nusRXCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write to peripheral
    nonisolated static let nusTXCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify from peripheral

    @Published private(set) var bluetoothStateText: String = "Idle"
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var peripherals: [BLEPeripheralItem] = []
    @Published private(set) var connectedPeripheral: CBPeripheral?
    @Published private(set) var characteristics: [BLEGATTCharacteristicItem] = []
    @Published private(set) var gattLog: [String] = []
    @Published var bridgeNUSToSerialPlotter: Bool = true

    var onNUSLineReceived: ((String) -> Void)?

    private var central: CBCentralManager?
    private var nusPartialLine: String = ""

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func startScan() {
        ensureCentral()
        guard let central else { return }
        if central.state == .poweredOn {
            peripherals.removeAll()
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            isScanning = true
            appendLog("[BLE] Scanning real macOS CoreBluetooth peripherals...")
        } else {
            appendLog("[BLE] Waiting for Bluetooth radio state (\(bluetoothStateText))...")
        }
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ item: BLEPeripheralItem) {
        stopScan()
        characteristics.removeAll()
        appendLog("[BLE] Connecting to \(item.name) [\(item.id.uuidString.prefix(8))]...")
        central?.connect(item.peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral {
            central?.cancelPeripheralConnection(p)
        }
        connectedPeripheral = nil
        characteristics.removeAll()
    }

    func readCharacteristic(_ item: BLEGATTCharacteristicItem) {
        connectedPeripheral?.readValue(for: item.characteristic)
    }

    func toggleNotify(_ item: BLEGATTCharacteristicItem) {
        connectedPeripheral?.setNotifyValue(!item.isNotifying, for: item.characteristic)
    }

    func writeCharacteristic(_ item: BLEGATTCharacteristicItem, payload: String, asHex: Bool) {
        guard let p = connectedPeripheral else { return }
        let data: Data
        if asHex {
            let clean = payload.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "")
            var bytes: [UInt8] = []
            var idx = clean.startIndex
            while idx < clean.endIndex {
                let next = clean.index(idx, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
                if let b = UInt8(clean[idx..<next], radix: 16) { bytes.append(b) }
                idx = next
            }
            data = Data(bytes)
        } else {
            data = Data(payload.utf8)
        }
        guard !data.isEmpty else { return }
        let writeType: CBCharacteristicWriteType = item.characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(data, for: item.characteristic, type: writeType)
        appendLog("[TX → \(item.characteristic.uuid.uuidString.prefix(8))] \(data.count) bytes")
    }

    func sendNUSLine(_ text: String) {
        guard let rxItem = characteristics.first(where: { $0.characteristic.uuid == Self.nusRXCharUUID }) else {
            appendLog("[NUS] Connected device does not expose Nordic UART RX characteristic (6E400002).")
            return
        }
        writeCharacteristic(rxItem, payload: text + "\r\n", asHex: false)
    }

    private func appendLog(_ line: String) {
        gattLog.append(line)
        if gattLog.count > 400 {
            gattLog.removeFirst(gattLog.count - 400)
        }
    }
}

extension BLEHardwareInspectorService: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateDesc: String
        switch central.state {
        case .poweredOn: stateDesc = "Powered On"
        case .poweredOff: stateDesc = "Powered Off"
        case .unauthorized: stateDesc = "Unauthorized (Grant Bluetooth in macOS Settings)"
        case .unsupported: stateDesc = "Unsupported"
        case .resetting: stateDesc = "Resetting"
        default: stateDesc = "Unknown"
        }
        Task { @MainActor in
            self.bluetoothStateText = stateDesc
            if central.state == .poweredOn && !self.isScanning && self.peripherals.isEmpty {
                self.startScan()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiInt = RSSI.intValue
        guard rssiInt != 127 else { return } // 127 = unavailable in CoreBluetooth spec
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unnamed BLE Node"
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let mfgHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
            .map { String(format: "%02X", $0) }.joined(separator: " ") ?? ""

        Task { @MainActor in
            if let idx = self.peripherals.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.peripherals[idx].rssi = rssiInt
                self.peripherals[idx].lastSeen = Date()
                if self.peripherals[idx].name == "Unnamed BLE Node" && advName != "Unnamed BLE Node" {
                    self.peripherals[idx].name = advName
                }
            } else {
                self.peripherals.append(BLEPeripheralItem(
                    id: peripheral.identifier,
                    peripheral: peripheral,
                    name: advName,
                    rssi: rssiInt,
                    advertisedServices: uuids,
                    manufacturerHex: mfgHex,
                    lastSeen: Date()
                ))
                self.peripherals.sort { $0.rssi > $1.rssi }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            self.appendLog("[BLE] Connected to \(peripheral.name ?? peripheral.identifier.uuidString). Discovering GATT services...")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.appendLog("[BLE] Disconnected from \(peripheral.name ?? "peripheral").")
            if self.connectedPeripheral?.identifier == peripheral.identifier {
                self.connectedPeripheral = nil
                self.characteristics.removeAll()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services {
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        let svcUUID = service.uuid.uuidString
        Task { @MainActor in
            for ch in chars {
                var props: [String] = []
                if ch.properties.contains(.read) { props.append("READ") }
                if ch.properties.contains(.write) { props.append("WRITE") }
                if ch.properties.contains(.writeWithoutResponse) { props.append("WRITE_NR") }
                if ch.properties.contains(.notify) { props.append("NOTIFY") }
                if ch.properties.contains(.indicate) { props.append("INDICATE") }

                let item = BLEGATTCharacteristicItem(
                    serviceUUID: svcUUID,
                    characteristic: ch,
                    propertiesSummary: props.joined(separator: " | "),
                    isNotifying: ch.isNotifying,
                    latestHex: "",
                    latestUTF8: ""
                )
                if !self.characteristics.contains(where: { $0.id == item.id }) {
                    self.characteristics.append(item)
                }
                if ch.properties.contains(.read) {
                    peripheral.readValue(for: ch)
                }
                // Auto-subscribe to Nordic UART TX notify stream
                if ch.uuid == Self.nusTXCharUUID && ch.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: ch)
                    self.appendLog("[NUS] Subscribed to Nordic UART wireless serial TX stream!")
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let cid = "\(characteristic.service?.uuid.uuidString ?? "")|\(characteristic.uuid.uuidString)"
        let notifying = characteristic.isNotifying
        Task { @MainActor in
            if let idx = self.characteristics.firstIndex(where: { $0.id == cid }) {
                self.characteristics[idx].isNotifying = notifying
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let cid = "\(characteristic.service?.uuid.uuidString ?? "")|\(characteristic.uuid.uuidString)"
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let utf8 = (String(data: data, encoding: .utf8) ?? "").replacingOccurrences(of: "\0", with: "")
        let isNUS = characteristic.uuid == Self.nusTXCharUUID

        Task { @MainActor in
            if let idx = self.characteristics.firstIndex(where: { $0.id == cid }) {
                self.characteristics[idx].latestHex = hex
                self.characteristics[idx].latestUTF8 = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            self.appendLog("[RX ← \(characteristic.uuid.uuidString.prefix(8))] \(utf8.isEmpty ? hex : utf8.trimmingCharacters(in: .whitespacesAndNewlines))")

            if isNUS && self.bridgeNUSToSerialPlotter {
                self.nusPartialLine += utf8
                while let nl = self.nusPartialLine.firstIndex(of: "\n") {
                    let line = String(self.nusPartialLine[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.nusPartialLine = String(self.nusPartialLine[self.nusPartialLine.index(after: nl)...])
                    if !line.isEmpty {
                        self.onNUSLineReceived?(line)
                    }
                }
            }
        }
    }
}

// MARK: - 6. Live Source-to-Pinout Electrical DRC & Apple Accelerate vDSP FFT Analyzer

struct PinDRCWarning: Identifiable {
    let id = UUID()
    let severity: String // "CRITICAL" or "WARN"
    let gpio: Int
    let message: String
}

struct PinDRCReport {
    let activeGPIOs: [Int: [String]] // gpio -> list of usages e.g. ["OUTPUT", "I2C_SDA"]
    let warnings: [PinDRCWarning]
}

enum PinConflictDRCAnalyzer {
    static func analyze(code: String, board: HardwareBoardTarget) -> PinDRCReport {
        // 1. Resolve `#define NAME <num>` and `const int/uint8_t NAME = <num>`
        var macroMap: [String: Int] = [:]
        if let defRegex = try? NSRegularExpression(pattern: #"#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(\d+)"#) {
            let ns = code as NSString
            for m in defRegex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                if let val = Int(ns.substring(with: m.range(at: 2))) { macroMap[name] = val }
            }
        }
        if let constRegex = try? NSRegularExpression(pattern: #"(?:const|constexpr|static)\s+[A-Za-z0-9_]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)"#) {
            let ns = code as NSString
            for m in constRegex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                if let val = Int(ns.substring(with: m.range(at: 2))) { macroMap[name] = val }
            }
        }

        func resolvePin(_ token: String) -> Int? {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "GPIO_NUM_", with: "")
            if let direct = Int(t) { return direct }
            return macroMap[t]
        }

        var usages: [Int: [String]] = [:]
        func addUsage(_ pin: Int?, _ role: String) {
            guard let p = pin, p >= 0 && p <= 54 else { return }
            if !(usages[p]?.contains(role) ?? false) {
                usages[p, default: []].append(role)
            }
        }

        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        let patterns: [(String, String)] = [
            (#"pinMode\s*\(\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*\)"#, "GPIO"),
            (#"analogRead\s*\(\s*([A-Za-z0-9_]+)\s*\)"#, "ADC"),
            (#"ledcAttach(?:Pin)?\s*\(\s*([A-Za-z0-9_]+)"#, "PWM"),
            (#"gpio_set_direction\s*\(\s*([A-Za-z0-9_]+)"#, "IDF_GPIO"),
            (#"machine\.Pin\s*\(\s*(\d+)"#, "MPY_PIN")
        ]

        for (pat, label) in patterns {
            if let rx = try? NSRegularExpression(pattern: pat) {
                for m in rx.matches(in: code, range: fullRange) {
                    addUsage(resolvePin(ns.substring(with: m.range(at: 1))), label)
                }
            }
        }

        if let wireRx = try? NSRegularExpression(pattern: #"Wire\.begin\s*\(\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)"#) {
            for m in wireRx.matches(in: code, range: fullRange) {
                addUsage(resolvePin(ns.substring(with: m.range(at: 1))), "I2C_SDA")
                addUsage(resolvePin(ns.substring(with: m.range(at: 2))), "I2C_SCL")
            }
        }

        var warnings: [PinDRCWarning] = []
        let usesWiFi = code.contains("WiFi.h") || code.contains("esp_wifi.h") || code.contains("network.WLAN")

        for (gpio, roles) in usages.sorted(by: { $0.key < $1.key }) {
            // Duplicate conflicting bus roles
            let busRoles = roles.filter { $0.hasPrefix("I2C") || $0 == "ADC" || $0 == "PWM" }
            if busRoles.count > 1 || (roles.contains("I2C_SDA") && roles.contains("GPIO")) {
                warnings.append(PinDRCWarning(
                    severity: "CRITICAL",
                    gpio: gpio,
                    message: "GPIO \(gpio) assigned to multiple peripheral roles simultaneously: \(roles.joined(separator: " + "))"
                ))
            }

            if board == .esp32s3 {
                if gpio == 19 || gpio == 20 {
                    warnings.append(PinDRCWarning(
                        severity: "CRITICAL",
                        gpio: gpio,
                        message: "GPIO \(gpio) is Native USB D-/D+ / JTAG! Reassigning it disconnects USB Serial immediately."
                    ))
                }
                if (35...37).contains(gpio) {
                    warnings.append(PinDRCWarning(
                        severity: "CRITICAL",
                        gpio: gpio,
                        message: "GPIO \(gpio) is wired internally to Octal SPI PSRAM/Flash on ESP32-S3 N8R8/N16R8 modules."
                    ))
                }
                if [0, 3, 45, 46].contains(gpio) {
                    warnings.append(PinDRCWarning(
                        severity: "WARN",
                        gpio: gpio,
                        message: "GPIO \(gpio) is an ESP32-S3 Boot Strapping Pin. External pull-ups/downs can block SPI Flash boot."
                    ))
                }
                let s3ADC2Pins: Set<Int> = [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
                if usesWiFi && roles.contains("ADC") && s3ADC2Pins.contains(gpio) {
                    warnings.append(PinDRCWarning(
                        severity: "CRITICAL",
                        gpio: gpio,
                        message: "GPIO \(gpio) uses SAR ADC2, which cannot be read while ESP32 Wi-Fi radio is active (move to ADC1 GPIO 1-10)."
                    ))
                }
            } else if board == .esp32c3 {
                if gpio == 18 || gpio == 19 {
                    warnings.append(PinDRCWarning(
                        severity: "CRITICAL",
                        gpio: gpio,
                        message: "GPIO \(gpio) is ESP32-C3 Native USB Serial/JTAG D-/D+."
                    ))
                }
                if [2, 8, 9].contains(gpio) {
                    warnings.append(PinDRCWarning(
                        severity: "WARN",
                        gpio: gpio,
                        message: "GPIO \(gpio) is an ESP32-C3 Boot Strapping Pin."
                    ))
                }
            }
        }

        return PinDRCReport(activeGPIOs: usages, warnings: warnings)
    }
}

struct FFTSpectrumSummary {
    let dominantFrequencyHz: Double
    let dominantMagnitude: Double
    let rms: Double
    let bins: [(hz: Double, magnitude: Double)]
}

enum TelemetryFFTAnalyzer {
    /// Real Apple Silicon `Accelerate` (`vDSP`) Hanning-windowed FFT spectrum computation.
    static func computeSpectrum(samples: [Double], sampleRateHz: Double) -> FFTSpectrumSummary? {
        guard samples.count >= 32, sampleRateHz > 0 else { return nil }
        let log2n = vDSP_Length(floor(log2(Double(min(samples.count, 512)))))
        let n = Int(1 << log2n)
        guard n >= 32 else { return nil }

        let tail = Array(samples.suffix(n))
        var rmsVal: Double = 0
        vDSP_rmsqvD(tail, 1, &rmsVal, vDSP_Length(n))

        // Remove DC mean & apply real Hanning window before FFT
        var meanVal: Double = 0
        vDSP_meanvD(tail, 1, &meanVal, vDSP_Length(n))
        var zeroMean = [Double](repeating: 0, count: n)
        var negMean = -meanVal
        vDSP_vsaddD(tail, 1, &negMean, &zeroMean, 1, vDSP_Length(n))

        var window = [Double](repeating: 0, count: n)
        vDSP_hann_windowD(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        var windowed = [Double](repeating: 0, count: n)
        vDSP_vmulD(zeroMean, 1, window, 1, &windowed, 1, vDSP_Length(n))

        let halfN = n / 2
        var realp = [Double](repeating: 0, count: halfN)
        var imagp = [Double](repeating: 0, count: halfN)

        guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        var magnitudes = [Double](repeating: 0, count: halfN)
        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPDoubleSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                windowed.withUnsafeBytes { rawBytes in
                    let complexPtr = rawBytes.bindMemory(to: DSPDoubleComplex.self)
                    vDSP_ctozD(complexPtr.baseAddress!, 2, &split, 1, vDSP_Length(halfN))
                }
                vDSP_fft_zripD(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabsD(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        let scale = 2.0 / Double(n)
        var bins: [(hz: Double, magnitude: Double)] = []
        var peakHz = 0.0
        var peakMag = 0.0

        for k in 1..<halfN {
            let hz = (Double(k) * sampleRateHz) / Double(n)
            let mag = magnitudes[k] * scale
            bins.append((hz: hz, magnitude: mag))
            if mag > peakMag {
                peakMag = mag
                peakHz = hz
            }
        }

        return FFTSpectrumSummary(
            dominantFrequencyHz: peakHz,
            dominantMagnitude: peakMag,
            rms: rmsVal,
            bins: bins
        )
    }
}

// MARK: - 7. Shared Hardware-in-the-Loop (HIL) Coordinator & 6 Real AgentToolBox Tools

@MainActor
final class EmbeddedStudioController: ObservableObject {
    static let shared = EmbeddedStudioController()

    var activeBoard: HardwareBoardTarget = .esp32s3
    var activeLanguage: EmbeddedSourceLanguage = .cpp
    var activePortPath: String? = nil

    var getSourceCode: (() -> String)?
    var setSourceCode: ((String) -> Void)?
    var getRecentSerialLines: ((Int) -> [String])?
    var sendSerialLine: ((String) -> Bool)?
    var triggerCompileUI: (() async -> FirmwareCompileOutcome)?
    var triggerFlashUI: (() async -> Bool)?

    private init() {}
}

struct EmbeddedListHardwareTool: AgentTool {
    let name = "embedded_list_hardware"
    let description = "Lists all real physical USB microcontrollers connected to macOS (IOKit VID:PID, /dev/cu.* port, silicon fingerprint), mounted UF2/BOOTSEL volumes, discovered mDNS LAN nodes, and BLE peripherals."
    let parameters: [ToolParameter] = []

    func execute(params: [String: Any]) async throws -> String {
        let usbDevices = IOKitUSBHotplugDaemon.enumeratePhysicalUSBDevicesSync()
        return await MainActor.run {
            IOKitUSBHotplugDaemon.shared.scanBootloaderVolumes()
            let vols = IOKitUSBHotplugDaemon.shared.bootloaderVolumes
            let mdns = IoTNetworkDiscoveryService.shared.discoveredNodes
            let ble = BLEHardwareInspectorService.shared.peripherals

            var out = "### Connected Physical Embedded Hardware (Zero-Mock IOKit & Network Scan)\n"
            out += "- Active Target Board in Studio: \(EmbeddedStudioController.shared.activeBoard.rawValue)\n"
            out += "- Selected Serial Port: \(EmbeddedStudioController.shared.activePortPath ?? "None")\n\n"

            if usbDevices.isEmpty {
                out += "**USB Serial Microcontrollers:** 0 physical devices connected.\n"
            } else {
                out += "**USB Serial Microcontrollers (\(usbDevices.count)):**\n"
                for d in usbDevices {
                    out += "- `\(d.calloutPath)` — \(d.siliconSummary) (VID:PID `\(d.vidPidHex ?? "N/A")`, SN: `\(d.serialNumber ?? "N/A")`, Suggested: \(d.suggestedBoard?.rawValue ?? "Generic"))\n"
                }
            }

            if !vols.isEmpty {
                out += "\n**Mounted Bootloader Volumes:**\n"
                for v in vols {
                    out += "- `\(v.path)` (\(v.boardFamily))\n"
                }
            }

            if !mdns.isEmpty {
                out += "\n**Discovered LAN mDNS Nodes (\(mdns.count)):**\n"
                for n in mdns {
                    out += "- `\(n.ipAddress):\(n.port)` — \(n.serviceName) (\(n.boardHint))\n"
                }
            }

            if !ble.isEmpty {
                out += "\n**Nearby BLE Peripherals (\(ble.count)):**\n"
                for p in ble.prefix(10) {
                    out += "- `\(p.name)` (RSSI \(p.rssi) dBm, UUID `\(p.id.uuidString)`)\n"
                }
            }
            return out
        }
    }
}

struct EmbeddedCompileTool: AgentTool {
    let name = "embedded_compile"
    let description = "Updates (optional) and cross-compiles the real embedded firmware for the target MCU using PlatformIO, Arduino CLI, ESP-IDF, or MicroPython py_compile. Returns compiler diagnostics, Pin DRC warnings, and exact ELF Flash/RAM byte usage."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "code", type: "string", description: "Optional updated firmware source code to write into the Embedded Studio editor before compiling.", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let newCode = params["code"] as? String
        let (codeToBuild, board, lang, ws) = await MainActor.run {
            let ctrl = EmbeddedStudioController.shared
            if let newCode, !newCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ctrl.setSourceCode?(newCode)
            }
            let src = newCode ?? ctrl.getSourceCode?() ?? ""
            return (src, ctrl.activeBoard, ctrl.activeLanguage, AppState.shared?.workspaceFolder)
        }

        guard !codeToBuild.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: Firmware source code is empty."
        }

        let drc = PinConflictDRCAnalyzer.analyze(code: codeToBuild, board: board)
        let outcome: FirmwareCompileOutcome
        if let uiTrigger = await MainActor.run(body: { EmbeddedStudioController.shared.triggerCompileUI }), newCode == nil {
            outcome = await uiTrigger()
        } else {
            outcome = await EmbeddedToolchainService.shared.compileFirmware(
                sourceCode: codeToBuild,
                language: lang,
                board: board,
                workspaceURL: ws,
                onLog: { _ in }
            )
        }

        var summary = "### Embedded Compilation Result: \(outcome.success ? "SUCCESS" : "FAILED")\n"
        summary += "- Target Board: \(board.rawValue)\n"
        summary += "- Toolchain Backend: \(outcome.backend?.rawValue ?? "None")\n"
        if let elf = outcome.elfPath { summary += "- ELF Artifact: `\(elf)`\n" }
        if let bin = outcome.binaryPath { summary += "- Firmware Binary: `\(bin)`\n" }
        if let r = outcome.memoryReport {
            summary += "- Real ELF Flash: \(r.flashUsedBytes) / \(r.flashCapacityBytes) bytes (\(String(format: "%.1f%%", r.flashPercent)))\n"
            summary += "- Real ELF Static RAM: \(r.ramUsedBytes) / \(r.ramCapacityBytes) bytes (\(String(format: "%.1f%%", r.ramPercent)))\n"
        }
        if !drc.warnings.isEmpty {
            summary += "\n**Pin Electrical DRC Warnings:**\n"
            for w in drc.warnings {
                summary += "- [\(w.severity)] GPIO \(w.gpio): \(w.message)\n"
            }
        }
        if let hint = outcome.missingToolchainHint {
            summary += "\n**Missing Toolchain:** \(hint)\n"
        }
        let logTail = String(outcome.fullLog.suffix(2500))
        summary += "\n**Build Output Tail:**\n```\n\(logTail)\n```"
        return summary
    }
}

struct EmbeddedFlashTool: AgentTool {
    let name = "embedded_flash"
    let description = "Compiles and flashes the real firmware binary directly onto the connected physical microcontroller via Smart Port Arbiter."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "port", type: "string", description: "Optional /dev/cu.* port override. Defaults to active port in Embedded Studio.", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        if let uiFlash = await MainActor.run(body: { EmbeddedStudioController.shared.triggerFlashUI }), params["port"] == nil {
            let ok = await uiFlash()
            return ok
                ? "SUCCESS: Firmware compiled, flashed to physical board, and Serial Monitor reconnected."
                : "FAILED: Firmware flash failed. Inspect build log or verify physical USB connection."
        }

        let explicitPort = params["port"] as? String
        let detected = IOKitUSBHotplugDaemon.enumeratePhysicalUSBDevicesSync().first?.calloutPath
        let (src, board, lang, activePort, ws) = await MainActor.run {
            let c = EmbeddedStudioController.shared
            return (c.getSourceCode?() ?? "", c.activeBoard, c.activeLanguage, c.activePortPath, AppState.shared?.workspaceFolder)
        }
        guard let port = explicitPort ?? activePort ?? detected else {
            return "FAILED: No physical USB microcontroller detected on macOS. Connect a board via USB first."
        }

        var log = ""
        let ok = await EmbeddedToolchainService.shared.flashToBoard(
            sourceCode: src,
            language: lang,
            board: board,
            portPath: port,
            workspaceURL: ws,
            onLog: { log += $0 }
        )
        return "Flash to `\(port)` \(ok ? "SUCCEEDED" : "FAILED"):\n```\n\(log.suffix(2000))\n```"
    }
}

struct EmbeddedSerialCaptureTool: AgentTool {
    let name = "embedded_serial_capture"
    let description = "Captures real live UART serial output from the connected microcontroller for `duration_ms` (or until `stop_pattern` appears)."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "duration_ms", type: "integer", description: "Duration to observe serial output in milliseconds (default 2500, max 15000).", required: false),
        ToolParameter(name: "stop_pattern", type: "string", description: "Optional substring that ends capture early as soon as it appears.", required: false)
    ]

    func execute(params: [String: Any]) async throws -> String {
        let durationMs = min(max((params["duration_ms"] as? Int) ?? 2500, 300), 15000)
        let stopPattern = params["stop_pattern"] as? String

        let startLines = await MainActor.run { EmbeddedStudioController.shared.getRecentSerialLines?(200) ?? [] }
        let steps = max(1, durationMs / 150)
        var latestLines = startLines

        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: 150_000_000)
            latestLines = await MainActor.run { EmbeddedStudioController.shared.getRecentSerialLines?(200) ?? [] }
            if let pat = stopPattern, !pat.isEmpty {
                let newSlice = latestLines.suffix(max(0, latestLines.count - startLines.count))
                if newSlice.contains(where: { $0.contains(pat) }) {
                    break
                }
            }
        }

        if latestLines.isEmpty {
            return "No serial lines received. Ensure a physical board is connected and transmitting at the configured baud rate."
        }
        return "### Captured Real Serial Output (last \(min(60, latestLines.count)) lines)\n```\n\(latestLines.suffix(60).joined(separator: "\n"))\n```"
    }
}

struct EmbeddedSerialSendTool: AgentTool {
    let name = "embedded_serial_send"
    let description = "Sends a real UTF-8 command line over POSIX UART serial to the connected microcontroller."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "command", type: "string", description: "Command string to transmit to the board.", required: true)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let cmd = params["command"] as? String, !cmd.isEmpty else {
            return "Error: Missing `command` parameter."
        }
        let sent = await MainActor.run { EmbeddedStudioController.shared.sendSerialLine?(cmd) ?? false }
        return sent
            ? "Transmitted `\(cmd)` over physical serial port."
            : "Failed to transmit: Serial Monitor is not connected to an open USB port."
    }
}

struct EmbeddedDecodeCrashTool: AgentTool {
    let name = "embedded_decode_crash"
    let description = "Symbolicates a real MCU panic/crash dump (ESP32 Guru Meditation Backtrace or ARM Cortex-M HardFault) into exact C++ functions and file:line numbers using DWARF addr2line against the compiled .elf binary."
    let parameters: [ToolParameter] = [
        ToolParameter(name: "backtrace", type: "string", description: "Raw crash log or Backtrace: 0x...:0x... line.", required: true)
    ]

    func execute(params: [String: Any]) async throws -> String {
        guard let trace = params["backtrace"] as? String, !trace.isEmpty else {
            return "Error: Missing `backtrace` parameter."
        }
        let board = await MainActor.run { EmbeddedStudioController.shared.activeBoard }
        let res = await ELFMemoryAndDwarfService.shared.symbolicateCrash(rawInput: trace, board: board)
        return "```\n\(res.formattedText)\n```"
    }
}
