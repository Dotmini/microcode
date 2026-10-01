import Foundation

// MARK: - Datasheet-to-Code Engine (Phase 4)
// Hardware-Aware RAG that parses PDF datasheets, MCU register maps,
// and pinout tables to generate accurate driver code.

// MARK: - Hardware Context

struct HardwareContext: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String              // "STM32F407VG", "ESP32-S3", "nRF52840"
    let architecture: String      // "ARM Cortex-M4", "Xtensa LX7", "RISC-V"
    let manufacturer: String      // "STMicroelectronics", "Espressif", "Nordic"
    let registers: [RegisterMap]
    let pinout: [PinDefinition]
    let interrupts: [InterruptVector]
    let memoryMap: MemoryLayout
    let peripherals: [Peripheral]
    let clockConfig: ClockConfig?
    let datasheetPath: String?    // Local path to PDF
    
    struct RegisterMap: Identifiable, Equatable, Codable {
        let id: UUID
        let peripheral: String    // "GPIO", "USART", "SPI", "TIM"
        let name: String          // "GPIOA_MODER", "USART1_CR1"
        let address: UInt64       // 0x4002_0000
        let offset: UInt32        // 0x00
        let size: Int             // 32 bits
        let accessType: String    // "RW", "RO", "WO"
        let resetValue: UInt64
        let bitFields: [BitField]
        let description: String
    }
    
    struct BitField: Identifiable, Equatable, Codable {
        let id: UUID
        let name: String          // "MODE0", "OT0", "OSPEEDR0"
        let bitRange: String      // "1:0", "15:14"
        let description: String
        let values: [String: String] // "00": "Input", "01": "Output", etc.
    }
    
    struct PinDefinition: Identifiable, Equatable, Codable {
        let id: UUID
        let pin: String           // "PA0", "GPIO2", "P0.13"
        let functions: [String]   // ["GPIO", "ADC1_IN0", "TIM2_CH1"]
        let type: String          // "I/O", "Power", "GND"
        let notes: String
    }
    
    struct InterruptVector: Identifiable, Equatable, Codable {
        let id: UUID
        let name: String          // "USART1_IRQn"
        let number: Int           // 37
        let priority: Int?
        let description: String
    }
    
    struct MemoryLayout: Equatable, Codable {
        let flashStart: UInt64    // 0x0800_0000
        let flashSize: Int        // 1048576 (1MB)
        let sramStart: UInt64     // 0x2000_0000
        let sramSize: Int         // 196608 (192KB)
        let peripheralStart: UInt64 // 0x4000_0000
    }
    
    struct Peripheral: Identifiable, Equatable, Codable {
        let id: UUID
        let name: String          // "USART1", "SPI2", "I2C1"
        let type: String          // "USART", "SPI", "I2C"
        let baseAddress: UInt64
        let clockBus: String      // "APB2", "AHB1"
        let description: String
    }
    
    struct ClockConfig: Equatable, Codable {
        let maxFreqMHz: Int
        let oscillators: [String]  // ["HSI 16MHz", "HSE 8MHz"]
        let pllConfig: String?
    }
}

// MARK: - Hardware Pack

struct HardwarePack: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String              // "ARM Cortex-M Pack", "ESP32 Pack"
    let architectures: [String]   // ["ARM Cortex-M0", "ARM Cortex-M3", "ARM Cortex-M4"]
    let supportedMCUs: [String]   // ["STM32F1xx", "STM32F4xx", "STM32L0xx"]
    let version: String
    let description: String
    let datasheetPaths: [String]  // Local paths to indexed datasheets
    let contexts: [HardwareContext]
}

// MARK: - Datasheet Parser

final class DatasheetParser {
    
    /// Parse a register map table from extracted text
    func parseRegisterMap(text: String, peripheral: String) -> [HardwareContext.RegisterMap] {
        var registers: [HardwareContext.RegisterMap] = []
        
        // Pattern: "0xXXXX_XXXX | REG_NAME | RW | 0x00000000 | Description"
        let lines = text.components(separatedBy: "\n")
        let hexPattern = #"(0x[0-9A-Fa-f_]+)"#
        
        for line in lines {
            // Try to match register definition patterns
            guard let addressMatch = line.range(of: hexPattern, options: .regularExpression) else { continue }
            let addressStr = String(line[addressMatch]).replacingOccurrences(of: "_", with: "")
            guard let address = UInt64(addressStr.dropFirst(2), radix: 16) else { continue }
            
            // Extract register name (usually uppercase with underscores)
            let namePattern = #"[A-Z][A-Z0-9_]{2,}"#
            guard let nameMatch = line.range(of: namePattern, options: .regularExpression) else { continue }
            let name = String(line[nameMatch])
            
            // Detect access type
            let accessType: String
            if line.contains("RW") || line.contains("read/write") { accessType = "RW" }
            else if line.contains("RO") || line.contains("read-only") { accessType = "RO" }
            else if line.contains("WO") || line.contains("write-only") { accessType = "WO" }
            else { accessType = "RW" }
            
            registers.append(HardwareContext.RegisterMap(
                id: UUID(),
                peripheral: peripheral,
                name: name,
                address: address,
                offset: UInt32(address & 0xFFFF),
                size: 32,
                accessType: accessType,
                resetValue: 0,
                bitFields: [],
                description: line
            ))
        }
        
        return registers
    }
    
    /// Parse pin definitions from a pinout table
    func parsePinout(text: String) -> [HardwareContext.PinDefinition] {
        var pins: [HardwareContext.PinDefinition] = []
        
        // Pattern: "PA0 | I/O | ADC1_IN0, TIM2_CH1, USART2_CTS"
        let pinPattern = #"(P[A-Z]\d+|GPIO\d+|P\d+\.\d+)"#
        
        for line in text.components(separatedBy: "\n") {
            guard let pinMatch = line.range(of: pinPattern, options: .regularExpression) else { continue }
            let pin = String(line[pinMatch])
            
            // Extract alternate functions
            var functions: [String] = ["GPIO"]
            let altFuncPattern = #"(ADC|TIM|USART|SPI|I2C|DAC|CAN|ETH|USB|SDIO|FSMC)\w*"#
            let regex = try? NSRegularExpression(pattern: altFuncPattern)
            let nsLine = line as NSString
            let matches = regex?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? []
            for match in matches {
                functions.append(nsLine.substring(with: match.range))
            }
            
            let type: String
            if line.lowercased().contains("power") || line.contains("VDD") { type = "Power" }
            else if line.lowercased().contains("gnd") || line.contains("VSS") { type = "GND" }
            else { type = "I/O" }
            
            pins.append(HardwareContext.PinDefinition(
                id: UUID(),
                pin: pin,
                functions: functions,
                type: type,
                notes: ""
            ))
        }
        
        return pins
    }
}

// MARK: - Hardware RAG Service

@MainActor
final class HardwareRAGService: ObservableObject {
    static let shared = HardwareRAGService()
    
    // MARK: - Published State
    @Published private(set) var loadedPacks: [HardwarePack] = []
    @Published private(set) var activeContext: HardwareContext?
    @Published private(set) var indexedRegisters: Int = 0
    @Published private(set) var indexedPins: Int = 0
    @Published var isIndexing = false
    
    private let parser = DatasheetParser()
    private let storageDir: URL
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageDir = docs.appendingPathComponent("MicroCode/HardwarePacks")
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadSavedPacks()
    }
    
    // MARK: - Datasheet Indexing
    
    /// Index a PDF datasheet and extract hardware context
    func indexDatasheet(path: String, mcuName: String, architecture: String, manufacturer: String) async -> HardwareContext? {
        isIndexing = true
        defer { isIndexing = false }
        
        // Extract text from PDF using macOS built-in tools
        let extractedText = await extractPDFText(path: path)
        guard !extractedText.isEmpty else { return nil }
        
        // Parse hardware information
        let registers = parser.parseRegisterMap(text: extractedText, peripheral: "AUTO")
        let pins = parser.parsePinout(text: extractedText)
        
        let context = HardwareContext(
            id: UUID(),
            name: mcuName,
            architecture: architecture,
            manufacturer: manufacturer,
            registers: registers,
            pinout: pins,
            interrupts: [],
            memoryMap: HardwareContext.MemoryLayout(
                flashStart: 0x0800_0000,
                flashSize: 0,
                sramStart: 0x2000_0000,
                sramSize: 0,
                peripheralStart: 0x4000_0000
            ),
            peripherals: [],
            clockConfig: nil,
            datasheetPath: path
        )
        
        activeContext = context
        indexedRegisters = registers.count
        indexedPins = pins.count
        
        return context
    }
    
    // MARK: - Agent Context Generation
    
    /// Build hardware context string for AI agent prompts
    func buildAgentContext(forPeripheral peripheral: String? = nil) -> String {
        guard let ctx = activeContext else { return "" }
        
        var prompt = """
        ## Hardware Context
        - **MCU:** \(ctx.name)
        - **Architecture:** \(ctx.architecture)
        - **Manufacturer:** \(ctx.manufacturer)
        """
        
        // Filter registers for requested peripheral
        let regs = peripheral != nil
            ? ctx.registers.filter { $0.peripheral.lowercased().contains(peripheral!.lowercased()) }
            : ctx.registers
        
        if !regs.isEmpty {
            prompt += "\n\n### Register Map (\(regs.count) registers)\n"
            for reg in regs.prefix(50) {
                prompt += "- `\(reg.name)` @ `0x\(String(reg.address, radix: 16, uppercase: true))` "
                prompt += "[\(reg.accessType)] \(reg.description.prefix(80))\n"
            }
        }
        
        if !ctx.pinout.isEmpty {
            prompt += "\n\n### Pinout (\(ctx.pinout.count) pins)\n"
            for pin in ctx.pinout.prefix(30) {
                prompt += "- `\(pin.pin)`: \(pin.functions.joined(separator: ", ")) [\(pin.type)]\n"
            }
        }
        
        if !ctx.peripherals.isEmpty {
            prompt += "\n\n### Peripherals\n"
            for periph in ctx.peripherals {
                prompt += "- `\(periph.name)` @ `0x\(String(periph.baseAddress, radix: 16, uppercase: true))` "
                prompt += "[\(periph.clockBus)] \(periph.description)\n"
            }
        }
        
        prompt += "\n\n**IMPORTANT:** Use exact register addresses from this context. Do NOT guess addresses."
        
        return prompt
    }
    
    // MARK: - PDF Text Extraction
    
    private func extractPDFText(path: String) async -> String {
        // Use macOS CGPDFDocument for text extraction
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.extractTextFromPDF(path: path)
                continuation.resume(returning: result)
            }
        }
    }
    
    private nonisolated func extractTextFromPDF(path: String) -> String {
        // Use mdimport / textutil for basic PDF text extraction
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["textutil", "-convert", "txt", "-stdout", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    // MARK: - Pack Persistence
    
    private func loadSavedPacks() {
        let indexFile = storageDir.appendingPathComponent("packs_index.json")
        guard let data = try? Data(contentsOf: indexFile),
              let packs = try? JSONDecoder().decode([HardwarePack].self, from: data) else { return }
        loadedPacks = packs
    }
    
    func savePacks() {
        let indexFile = storageDir.appendingPathComponent("packs_index.json")
        guard let data = try? JSONEncoder().encode(loadedPacks) else { return }
        try? data.write(to: indexFile)
    }
    
    // MARK: - Built-in MCU Templates
    
    /// Pre-built templates for common MCU families
    static let builtInTemplates: [String: HardwareContext] = [
        "STM32F407": HardwareContext(
            id: UUID(),
            name: "STM32F407VG",
            architecture: "ARM Cortex-M4F",
            manufacturer: "STMicroelectronics",
            registers: [
                HardwareContext.RegisterMap(
                    id: UUID(), peripheral: "RCC", name: "RCC_CR",
                    address: 0x4002_3800, offset: 0x00, size: 32,
                    accessType: "RW", resetValue: 0x0000_0083, bitFields: [],
                    description: "Clock control register"
                ),
                HardwareContext.RegisterMap(
                    id: UUID(), peripheral: "RCC", name: "RCC_AHB1ENR",
                    address: 0x4002_3830, offset: 0x30, size: 32,
                    accessType: "RW", resetValue: 0x0010_0000, bitFields: [],
                    description: "AHB1 peripheral clock enable register"
                ),
                HardwareContext.RegisterMap(
                    id: UUID(), peripheral: "GPIOA", name: "GPIOA_MODER",
                    address: 0x4002_0000, offset: 0x00, size: 32,
                    accessType: "RW", resetValue: 0xA800_0000, bitFields: [],
                    description: "GPIO port mode register"
                ),
            ],
            pinout: [
                HardwareContext.PinDefinition(id: UUID(), pin: "PA0", functions: ["GPIO", "TIM2_CH1", "TIM5_CH1", "ADC1_IN0"], type: "I/O", notes: ""),
                HardwareContext.PinDefinition(id: UUID(), pin: "PA1", functions: ["GPIO", "TIM2_CH2", "TIM5_CH2", "ADC1_IN1"], type: "I/O", notes: ""),
                HardwareContext.PinDefinition(id: UUID(), pin: "PA5", functions: ["GPIO", "SPI1_SCK", "DAC_OUT2", "ADC1_IN5"], type: "I/O", notes: ""),
                HardwareContext.PinDefinition(id: UUID(), pin: "PA9", functions: ["GPIO", "USART1_TX", "TIM1_CH2"], type: "I/O", notes: ""),
                HardwareContext.PinDefinition(id: UUID(), pin: "PA10", functions: ["GPIO", "USART1_RX", "TIM1_CH3"], type: "I/O", notes: ""),
            ],
            interrupts: [
                HardwareContext.InterruptVector(id: UUID(), name: "USART1_IRQn", number: 37, priority: nil, description: "USART1 global interrupt"),
                HardwareContext.InterruptVector(id: UUID(), name: "TIM2_IRQn", number: 28, priority: nil, description: "TIM2 global interrupt"),
            ],
            memoryMap: HardwareContext.MemoryLayout(
                flashStart: 0x0800_0000, flashSize: 1_048_576,
                sramStart: 0x2000_0000, sramSize: 196_608,
                peripheralStart: 0x4000_0000
            ),
            peripherals: [
                HardwareContext.Peripheral(id: UUID(), name: "USART1", type: "USART", baseAddress: 0x4001_1000, clockBus: "APB2", description: "Universal synchronous asynchronous receiver transmitter 1"),
                HardwareContext.Peripheral(id: UUID(), name: "SPI1", type: "SPI", baseAddress: 0x4001_3000, clockBus: "APB2", description: "Serial peripheral interface 1"),
                HardwareContext.Peripheral(id: UUID(), name: "I2C1", type: "I2C", baseAddress: 0x4000_5400, clockBus: "APB1", description: "Inter-integrated circuit interface 1"),
            ],
            clockConfig: HardwareContext.ClockConfig(maxFreqMHz: 168, oscillators: ["HSI 16MHz", "HSE 8MHz"], pllConfig: "PLL_M=8, PLL_N=336, PLL_P=2"),
            datasheetPath: nil
        ),
    ]
}
