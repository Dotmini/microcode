//
//  EmbeddedEnvManager.swift
//  MicroCode
//
//  Hardware and Arduino Library / Toolchain Environment Manager
//  Modeled after Cell Mode's PythonEnvManager for seamless embedded package management.
//

import Foundation
import Combine

// MARK: - Embedded Library Model

public struct EmbeddedLibrary: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let version: String
    public let location: String
    public let descriptionText: String
    public let category: String
    public let author: String
    public var isInstalled: Bool
}

// MARK: - Toolchain Info Model

public struct EmbeddedToolchainInfo: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let binaryName: String
    public var path: String
    public var version: String
    public var isInstalled: Bool
    public let role: String
}

// MARK: - Popular Embedded Libraries Catalog

public struct PopularEmbeddedLibrary: Identifiable {
    public let id = UUID()
    public let name: String
    public let category: String
    public let headerInclude: String
    public let summary: String
    public let tags: [String]
}

// MARK: - Embedded Environment Manager

public final class EmbeddedEnvManager: ObservableObject {
    public static let shared = EmbeddedEnvManager()
    
    @Published public var installedLibraries: [EmbeddedLibrary] = []
    @Published public var detectedLibraries: [String] = []
    @Published public var searchResults: [EmbeddedLibrary] = []
    @Published public var isWorking: Bool = false
    @Published public var workingMessage: String = ""
    @Published public var consoleOutput: String = ""
    @Published public var toolchains: [EmbeddedToolchainInfo] = []
    
    // ESP-IDF & FreeRTOS Native Toolchain Engine
    @Published public var idfPath: String = ""
    @Published public var isEspIdfConfigured: Bool = false
    @Published public var detectedExportScript: String = ""
    @Published public var idfVersion: String = "Not Configured"
    @Published public var xtensaToolchainPath: String = ""
    @Published public var espIdfIncludePaths: [String] = []
    
    // Autonomous Fast Dependency & Library Auto-Installer
    @Published public var autoInstallLibraries: Bool = true
    @Published public var autoDepStatus: String = "ACTIVE"
    @Published public var lastResolvedLib: String = ""
    @Published public var lastResolveTimeMs: Double = 0.0
    // Popular Embedded Libraries Catalog (Instant 1-Click Install)
    public let popularCatalog: [PopularEmbeddedLibrary] = [
        PopularEmbeddedLibrary(
            name: "ArduinoJson",
            category: "Data & Serialization",
            headerInclude: "ArduinoJson.h",
            summary: "Efficient JSON parsing and serialization for embedded C++ microcontrollers.",
            tags: ["JSON", "REST", "Parser"]
        ),
        PopularEmbeddedLibrary(
            name: "Adafruit NeoPixel",
            category: "Displays & LEDs",
            headerInclude: "Adafruit_NeoPixel.h",
            summary: "Drive addressable RGB & RGBW WS2812B/SK6812 LED strips and rings.",
            tags: ["LED", "WS2812", "RGB"]
        ),
        PopularEmbeddedLibrary(
            name: "FastLED",
            category: "Displays & LEDs",
            headerInclude: "FastLED.h",
            summary: "High-performance LED animation library with Color palettes and HSV control.",
            tags: ["LED", "Animation", "Fast"]
        ),
        PopularEmbeddedLibrary(
            name: "PubSubClient",
            category: "IoT & Networking",
            headerInclude: "PubSubClient.h",
            summary: "Lightweight MQTT client for publish/subscribe telemetry on ESP32 & Arduino.",
            tags: ["MQTT", "Cloud", "Telemetry"]
        ),
        PopularEmbeddedLibrary(
            name: "Adafruit SSD1306",
            category: "Displays & OLED",
            headerInclude: "Adafruit_SSD1306.h",
            summary: "I2C and SPI driver for monochrome 128x64 and 128x32 OLED displays.",
            tags: ["OLED", "I2C", "Display"]
        ),
        PopularEmbeddedLibrary(
            name: "Adafruit GFX Library",
            category: "Displays & Graphics",
            headerInclude: "Adafruit_GFX.h",
            summary: "Core graphics library providing primitives (lines, circles, text, bitmaps).",
            tags: ["GFX", "Graphics", "Canvas"]
        ),
        PopularEmbeddedLibrary(
            name: "DHT sensor library",
            category: "Sensors & Environmental",
            headerInclude: "DHT.h",
            summary: "Reads temperature and humidity from DHT11, DHT22, and AM2302 sensors.",
            tags: ["Temp", "Humidity", "Sensor"]
        ),
        PopularEmbeddedLibrary(
            name: "TFT_eSPI",
            category: "Displays & High-Speed",
            headerInclude: "TFT_eSPI.h",
            summary: "Ultra-fast SPI graphics library tuned for ESP32 with DMA rendering.",
            tags: ["TFT", "DMA", "Fast"]
        ),
        PopularEmbeddedLibrary(
            name: "AsyncTCP",
            category: "IoT & Networking",
            headerInclude: "AsyncTCP.h",
            summary: "Asynchronous TCP library for ESP32 powering high-throughput web servers.",
            tags: ["Async", "TCP", "ESP32"]
        ),
        PopularEmbeddedLibrary(
            name: "ESPAsyncWebServer",
            category: "IoT & Networking",
            headerInclude: "ESPAsyncWebServer.h",
            summary: "Asynchronous HTTP and WebSocket server for ESP32 and ESP8266.",
            tags: ["HTTP", "WebSocket", "WebUI"]
        ),
        PopularEmbeddedLibrary(
            name: "ESP32Servo",
            category: "Motors & Actuators",
            headerInclude: "ESP32Servo.h",
            summary: "Precise hardware PWM timer control for standard RC servos on ESP32.",
            tags: ["Servo", "PWM", "Motor"]
        ),
        PopularEmbeddedLibrary(
            name: "TinyGPSPlus",
            category: "Sensors & GNSS",
            headerInclude: "TinyGPSPlus.h",
            summary: "NMEA parser for GPS and GNSS modules (NEO-6M, NEO-8M).",
            tags: ["GPS", "NMEA", "Nav"]
        )
    ]
    
    private let userLibrariesDir: URL
    
    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        self.userLibrariesDir = docs.appendingPathComponent("Arduino/libraries")
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            DispatchQueue.main.async {
                self?.detectEspIdf()
                self?.detectAllToolchains()
                self?.refreshInstalledLibraries()
            }
        }
    }
    
    // MARK: - Toolchain Detection
    
    public func detectAllToolchains() {
        var list: [EmbeddedToolchainInfo] = []
        
        let toolchainDefs: [(name: String, bin: String, role: String, candidates: [String])] = [
            ("arduino-cli", "arduino-cli", "Arduino Core & Library Manager", [
                "/opt/homebrew/bin/arduino-cli",
                "/usr/local/bin/arduino-cli",
                "\(NSHomeDirectory())/.arduino15/bin/arduino-cli"
            ]),
            ("ESP-IDF idf.py", "idf.py", "Espressif Native CMake Orchestrator", [
                "/opt/homebrew/bin/idf.py",
                "\(NSHomeDirectory())/esp/esp-idf/tools/idf.py",
                "\(NSHomeDirectory())/.espressif/python_env/idf5.3_py3.11_env/bin/idf.py",
                "\(NSHomeDirectory())/.espressif/python_env/idf5.2_py3.11_env/bin/idf.py",
                "\(NSHomeDirectory())/.espressif/python_env/idf5.1_py3.11_env/bin/idf.py"
            ]),
            ("Xtensa GCC", "xtensa-esp32s3-elf-g++", "ESP32-S3 Native Cross-Compiler", [
                "\(NSHomeDirectory())/.espressif/tools/xtensa-esp-elf/esp-13.2.0_20230928/xtensa-esp-elf/bin/xtensa-esp32s3-elf-g++",
                "\(NSHomeDirectory())/.espressif/tools/xtensa-esp32s3-elf/esp-12.2.0_20230208/xtensa-esp32s3-elf/bin/xtensa-esp32s3-elf-g++",
                "/opt/homebrew/bin/xtensa-esp32s3-elf-g++"
            ]),
            ("esptool.py", "esptool.py", "ESP32 ROM Bootloader & Flasher", [
                "/opt/homebrew/bin/esptool.py",
                "/usr/local/bin/esptool.py",
                "/opt/homebrew/bin/python3 -m esptool",
                "\(NSHomeDirectory())/Library/Python/3.14/bin/esptool.py",
                "\(NSHomeDirectory())/Library/Python/3.12/bin/esptool.py",
                "\(NSHomeDirectory())/Library/Python/3.11/bin/esptool.py"
            ]),
            ("LLVM Clang++", "clang++", "Native Syntax Verification & Compiler", [
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swiftly/bin/clang++",
                "/opt/homebrew/opt/llvm/bin/clang++",
                "/usr/bin/clang++"
            ]),
            ("PlatformIO Core", "pio", "Multi-Target Embedded Toolchain", [
                "/opt/homebrew/bin/pio",
                "/usr/local/bin/pio",
                "\(NSHomeDirectory())/.platformio/penv/bin/pio"
            ])
        ]
        
        let fm = FileManager.default
        for def in toolchainDefs {
            var foundPath = ""
            var isInst = false
            for c in def.candidates {
                let cleanPath = c.components(separatedBy: " ").first ?? c
                if fm.isExecutableFile(atPath: cleanPath) {
                    foundPath = cleanPath
                    isInst = true
                    break
                }
            }
            
            list.append(EmbeddedToolchainInfo(
                name: def.name,
                binaryName: def.bin,
                path: isInst ? foundPath : "Not detected",
                version: isInst ? "Installed" : "Missing",
                isInstalled: isInst,
                role: def.role
            ))
        }
        
        self.toolchains = list
    }
    
    // MARK: - ESP-IDF & FreeRTOS Environment Detection
    
    public func detectEspIdf() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        var candidatePaths: [String] = []
        if let custom = UserDefaults.standard.string(forKey: "microcode.idf_path"), !custom.isEmpty {
            candidatePaths.append(custom)
        }
        if let envIdf = ProcessInfo.processInfo.environment["IDF_PATH"], !envIdf.isEmpty {
            candidatePaths.append(envIdf)
        }
        
        candidatePaths.append(contentsOf: [
            "\(home)/esp/esp-idf",
            "\(home)/esp/v5.3/esp-idf",
            "\(home)/esp/v5.2/esp-idf",
            "\(home)/esp/v5.1/esp-idf",
            "\(home)/esp/v5.0/esp-idf",
            "\(home)/.espressif/esp-idf",
            "/opt/esp-idf",
            "/usr/local/esp-idf",
            "/opt/homebrew/opt/esp-idf"
        ])
        
        var resolvedPath = ""
        var resolvedExport = ""
        
        for cand in candidatePaths {
            let exportScript = (cand as NSString).appendingPathComponent("export.sh")
            let idfPy = (cand as NSString).appendingPathComponent("tools/idf.py")
            if fm.fileExists(atPath: exportScript) || fm.fileExists(atPath: idfPy) {
                resolvedPath = cand
                resolvedExport = exportScript
                break
            }
        }
        
        if !resolvedPath.isEmpty {
            self.idfPath = resolvedPath
            self.detectedExportScript = resolvedExport
            self.isEspIdfConfigured = true
            self.idfVersion = "ESP-IDF (Auto-Detected)"
            
            let verFile = (resolvedPath as NSString).appendingPathComponent("version.txt")
            if let verStr = try? String(contentsOfFile: verFile, encoding: .utf8) {
                self.idfVersion = "ESP-IDF " + verStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            self.espIdfIncludePaths = computeEspIdfIncludePaths(base: resolvedPath)
        } else {
            self.idfPath = UserDefaults.standard.string(forKey: "microcode.idf_path") ?? ""
            self.detectedExportScript = ""
            self.isEspIdfConfigured = false
            self.idfVersion = "Not Configured"
            self.espIdfIncludePaths = []
        }
    }
    
    public func saveCustomIdfPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "microcode.idf_path")
        detectEspIdf()
        detectAllToolchains()
        appendLog("[CONFIG] Updated ESP-IDF path: '\(trimmed)'. Status: \(isEspIdfConfigured ? "VALID" : "UNCONFIGURED")")
    }
    
    public func computeEspIdfIncludePaths(base: String) -> [String] {
        let subpaths = [
            "components/freertos/FreeRTOS-Kernel/include",
            "components/freertos/FreeRTOS-Kernel/portable/xtensa/include",
            "components/freertos/esp_additions/include",
            "components/freertos/esp_additions/include/freertos",
            "components/esp_system/include",
            "components/esp_common/include",
            "components/esp_hw_support/include",
            "components/esp_rom/include",
            "components/driver/gpio/include",
            "components/driver/include",
            "components/log/include",
            "components/soc/esp32s3/include",
            "components/soc/include",
            "components/hal/include",
            "components/nvs_flash/include",
            "components/esp_event/include",
            "components/esp_netif/include",
            "components/esp_wifi/include"
        ]
        let fm = FileManager.default
        var results: [String] = []
        for p in subpaths {
            let full = (base as NSString).appendingPathComponent(p)
            if fm.fileExists(atPath: full) {
                results.append(full)
            }
        }
        return results
    }
    
    public func getEspIdfIncludeFlags() -> [String] {
        if espIdfIncludePaths.isEmpty && !idfPath.isEmpty {
            espIdfIncludePaths = computeEspIdfIncludePaths(base: idfPath)
        }
        return espIdfIncludePaths.map { "-I\($0)" }
    }
    
    /// Resolves persistent Arduino15 data directory (auto-redirects to `~/.microcode/arduino15` if `~/Library/Arduino15` is an unmounted external drive symlink).
    private var arduinoDataEnvPrefix: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultDir = "\(home)/Library/Arduino15"
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: defaultDir, isDirectory: &isDir) && isDir.boolValue {
            return ""
        }
        let fallback = "\(home)/.microcode/arduino15"
        try? FileManager.default.createDirectory(atPath: fallback, withIntermediateDirectories: true)
        return "ARDUINO_DIRECTORIES_DATA=\"\(fallback)\" ARDUINO_DIRECTORIES_DOWNLOADS=\"\(fallback)/staging\" "
    }
    
    // MARK: - ESP-IDF Transient Project Generation & Orchestration
    
    public func generateTransientEspIdfProject(sourceCode: String, targetBoard: String = "esp32s3") -> URL {
        let fm = FileManager.default
        let projectDir = URL(fileURLWithPath: "/tmp/microcode_esp_idf_project")
        let mainDir = projectDir.appendingPathComponent("main")
        try? fm.createDirectory(at: mainDir, withIntermediateDirectories: true)
        
        // 1. Root CMakeLists.txt
        let rootCMake = """
        cmake_minimum_required(VERSION 3.16)
        include($ENV{IDF_PATH}/tools/cmake/project.cmake)
        project(microcode_sketch)
        """
        try? rootCMake.write(to: projectDir.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
        
        // 2. main/CMakeLists.txt
        let mainCMake = """
        idf_component_register(SRCS "main.cpp"
                               INCLUDE_DIRS "."
                               REQUIRES freertos esp_system driver nvs_flash log)
        """
        try? mainCMake.write(to: mainDir.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
        
        // 3. sdkconfig.defaults
        let sdkDefaults = """
        CONFIG_IDF_TARGET="\(targetBoard)"
        CONFIG_FREERTOS_HZ=1000
        CONFIG_ESP_SYSTEM_PANIC_PRINT_REBOOT=y
        CONFIG_ESP_CONSOLE_UART_DEFAULT=y
        CONFIG_ESP_CONSOLE_UART_BAUDRATE=115200
        """
        try? sdkDefaults.write(to: projectDir.appendingPathComponent("sdkconfig.defaults"), atomically: true, encoding: .utf8)
        
        // 4. main/main.cpp
        var finalSource = sourceCode
        if finalSource.contains("setup()") && finalSource.contains("loop()") && !finalSource.contains("app_main") {
            finalSource += """

            // MicroCode Auto-Generated ESP-IDF FreeRTOS Main Trampoline
            extern "C" void app_main(void) {
                setup();
                while (true) {
                    loop();
                    vTaskDelay(1);
                }
            }
            """
        }
        try? finalSource.write(to: mainDir.appendingPathComponent("main.cpp"), atomically: true, encoding: .utf8)
        
        return projectDir
    }
    
    public func buildEspIdfProject(
        projectDir: URL,
        targetBoard: String,
        onOutput: @escaping (String) -> Void,
        completion: @escaping (Bool, Int32) -> Void
    ) {
        let exportScript = detectedExportScript.isEmpty ? "\(idfPath)/export.sh" : detectedExportScript
        let shellScript = """
        export IDF_PATH="\(idfPath)"
        if [ -f "\(exportScript)" ]; then
            . "\(exportScript)" >/dev/null 2>&1
        fi
        cd "\(projectDir.path)"
        idf.py set-target \(targetBoard)
        idf.py build
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", shellScript]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                onOutput(str)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                fileHandle.readabilityHandler = nil
                
                let rem = fileHandle.readDataToEndOfFile()
                if let str = String(data: rem, encoding: .utf8), !str.isEmpty {
                    onOutput(str)
                }
                let success = process.terminationStatus == 0
                completion(success, process.terminationStatus)
            } catch {
                fileHandle.readabilityHandler = nil
                onOutput("[ERROR] Failed to execute idf.py: \(error.localizedDescription)\n")
                completion(false, -1)
            }
        }
    }
    
    public func flashEspIdfProject(
        projectDir: URL,
        port: String,
        baud: String = "460800",
        onOutput: @escaping (String) -> Void,
        completion: @escaping (Bool, Int32) -> Void
    ) {
        let exportScript = detectedExportScript.isEmpty ? "\(idfPath)/export.sh" : detectedExportScript
        let shellScript = """
        export IDF_PATH="\(idfPath)"
        if [ -f "\(exportScript)" ]; then
            . "\(exportScript)" >/dev/null 2>&1
        fi
        cd "\(projectDir.path)"
        idf.py -p "\(port)" -b \(baud) flash
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", shellScript]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                onOutput(str)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                fileHandle.readabilityHandler = nil
                
                let rem = fileHandle.readDataToEndOfFile()
                if let str = String(data: rem, encoding: .utf8), !str.isEmpty {
                    onOutput(str)
                }
                let success = process.terminationStatus == 0
                completion(success, process.terminationStatus)
            } catch {
                fileHandle.readabilityHandler = nil
                onOutput("[ERROR] Failed to flash via idf.py: \(error.localizedDescription)\n")
                completion(false, -1)
            }
        }
    }

    
    // MARK: - Scan Installed Libraries
    
    public func refreshInstalledLibraries() {
        var libs: [EmbeddedLibrary] = []
        let fm = FileManager.default
        
        // 1. Scan filesystem: ~/Documents/Arduino/libraries
        if fm.fileExists(atPath: userLibrariesDir.path) {
            if let items = try? fm.contentsOfDirectory(atPath: userLibrariesDir.path) {
                for folder in items where !folder.hasPrefix(".") {
                    let folderPath = userLibrariesDir.appendingPathComponent(folder)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: folderPath.path, isDirectory: &isDir), isDir.boolValue {
                        let propFile = folderPath.appendingPathComponent("library.properties")
                        var version = "Installed"
                        var desc = "Local Arduino Library"
                        var author = "Arduino Developer"
                        var cat = "User Library"
                        
                        if let content = try? String(contentsOf: propFile, encoding: .utf8) {
                            for line in content.components(separatedBy: "\n") {
                                if line.hasPrefix("version=") {
                                    version = line.replacingOccurrences(of: "version=", with: "").trimmingCharacters(in: .whitespaces)
                                } else if line.hasPrefix("sentence=") {
                                    desc = line.replacingOccurrences(of: "sentence=", with: "").trimmingCharacters(in: .whitespaces)
                                } else if line.hasPrefix("author=") {
                                    author = line.replacingOccurrences(of: "author=", with: "").trimmingCharacters(in: .whitespaces)
                                } else if line.hasPrefix("category=") {
                                    cat = line.replacingOccurrences(of: "category=", with: "").trimmingCharacters(in: .whitespaces)
                                }
                            }
                        }
                        
                        libs.append(EmbeddedLibrary(
                            name: folder,
                            version: version,
                            location: "user (\(folderPath.lastPathComponent))",
                            descriptionText: desc,
                            category: cat,
                            author: author,
                            isInstalled: true
                        ))
                    }
                }
            }
        }
        
        // 2. Query arduino-cli in background if available
        let cliPath = toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "/opt/homebrew/bin/arduino-cli"
        if fm.isExecutableFile(atPath: cliPath) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", "\(self?.arduinoDataEnvPrefix ?? "")\(cliPath) lib list --format json 2>/dev/null || \(self?.arduinoDataEnvPrefix ?? "")\(cliPath) lib list"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    
                    // Case A: JSON decoding
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let list = json["installed_libraries"] as? [[String: Any]] {
                        var cliLibs: [EmbeddedLibrary] = []
                        for item in list {
                            if let libDict = item["library"] as? [String: Any],
                               let name = libDict["name"] as? String, !name.isEmpty {
                                let ver = libDict["version"] as? String ?? "-"
                                let loc = libDict["location"] as? String ?? "user"
                                let sentence = libDict["sentence"] as? String ?? "Managed by arduino-cli"
                                let cat = libDict["category"] as? String ?? "Arduino Library"
                                let author = libDict["author"] as? String ?? "Arduino Registry"
                                cliLibs.append(EmbeddedLibrary(
                                    name: name,
                                    version: ver,
                                    location: loc,
                                    descriptionText: sentence,
                                    category: cat,
                                    author: author,
                                    isInstalled: true
                                ))
                            }
                        }
                        
                        if !cliLibs.isEmpty {
                            DispatchQueue.main.async {
                                var merged = libs
                                for cl in cliLibs {
                                    if let idx = merged.firstIndex(where: { $0.name.lowercased() == cl.name.lowercased() }) {
                                        merged[idx] = cl
                                    } else {
                                        merged.append(cl)
                                    }
                                }
                                self?.installedLibraries = merged.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
                            }
                            return
                        }
                    }
                    
                    // Case B: Fallback plain text parsing (e.g. "ESP32Servo 3.2.1 user")
                    if let rawStr = String(data: data, encoding: .utf8), !rawStr.isEmpty {
                        let lines = rawStr.components(separatedBy: "\n")
                        var cliLibs: [EmbeddedLibrary] = []
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            // Exclude JSON tokens and headers
                            if trimmed.hasPrefix("{") || trimmed.hasPrefix("}") || trimmed.hasPrefix("\"") || trimmed.hasPrefix("Name") || trimmed.contains("---") {
                                continue
                            }
                            let parts = trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                            if parts.count >= 2 {
                                let name = parts[0]
                                let ver = parts[1]
                                let loc = parts.count > 3 ? parts[3] : "user"
                                cliLibs.append(EmbeddedLibrary(
                                    name: name,
                                    version: ver,
                                    location: loc,
                                    descriptionText: "Managed by arduino-cli",
                                    category: "Arduino Library",
                                    author: "Arduino Registry",
                                    isInstalled: true
                                ))
                            }
                        }
                        
                        if !cliLibs.isEmpty {
                            DispatchQueue.main.async {
                                var merged = libs
                                for cl in cliLibs {
                                    if !merged.contains(where: { $0.name.lowercased() == cl.name.lowercased() }) {
                                        merged.append(cl)
                                    }
                                }
                                self?.installedLibraries = merged.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
                            }
                            return
                        }
                    }
                } catch {}
            }
        }
        
        self.installedLibraries = libs.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
    }
    
    // MARK: - Analyze Includes in Code
    
    public func analyzeIncludes(code: String) {
        var detected: [String] = []
        let lines = code.components(separatedBy: "\n")
        
        let headerMapping: [(header: String, libName: String)] = [
            ("WiFi.h", "WiFi"),
            ("ArduinoJson.h", "ArduinoJson"),
            ("Adafruit_NeoPixel.h", "Adafruit NeoPixel"),
            ("FastLED.h", "FastLED"),
            ("PubSubClient.h", "PubSubClient"),
            ("Adafruit_SSD1306.h", "Adafruit SSD1306"),
            ("Adafruit_GFX.h", "Adafruit GFX Library"),
            ("DHT.h", "DHT sensor library"),
            ("DHT_U.h", "DHT sensor library"),
            ("Adafruit_Sensor.h", "Adafruit Unified Sensor"),
            ("LiquidCrystal_I2C.h", "LiquidCrystal I2C"),
            ("TFT_eSPI.h", "TFT_eSPI"),
            ("AsyncTCP.h", "AsyncTCP"),
            ("ESPAsyncWebServer.h", "ESPAsyncWebServer"),
            ("ESP32Servo.h", "ESP32Servo"),
            ("Servo.h", "Servo"),
            ("TinyGPSPlus.h", "TinyGPSPlus"),
            ("TinyGPS++.h", "TinyGPSPlus"),
            ("MPU6050.h", "MPU6050_light"),
            ("Adafruit_BME280.h", "Adafruit BME280 Library"),
            ("Wire.h", "Wire (I2C)"),
            ("SPI.h", "SPI (Bus)"),
            ("Preferences.h", "Preferences (NVS)"),
            ("BLEDevice.h", "ESP32 BLE Arduino"),
            ("BLEServer.h", "ESP32 BLE Arduino"),
            ("BLEUtils.h", "ESP32 BLE Arduino")
        ]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#include") {
                for item in headerMapping {
                    if trimmed.contains(item.header) {
                        if !detected.contains(item.libName) {
                            detected.append(item.libName)
                        }
                    }
                }
                
                // Generic detection: #include <XYZ.h>
                if let openBracket = trimmed.firstIndex(of: "<"),
                   let closeBracket = trimmed.firstIndex(of: ">"),
                   openBracket < closeBracket {
                    let header = String(trimmed[trimmed.index(after: openBracket)..<closeBracket])
                    let baseName = header.replacingOccurrences(of: ".h", with: "")
                    if !header.contains("Arduino.h") && !detected.contains(baseName) && !headerMapping.contains(where: { $0.header == header }) {
                        detected.append(baseName)
                    }
                }
            }
        }
        
        self.detectedLibraries = detected
        
        if autoInstallLibraries && !detected.isEmpty {
            autoResolveAndInstallDependencies(code: code)
        }
    }
    
    // MARK: - Autonomous Ultra-Fast Dependency Resolution & Auto-Installer
    
    public func autoResolveAndInstallDependencies(code: String, completion: ((String) -> Void)? = nil) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let detected = self.detectedLibraries
        guard !detected.isEmpty else {
            DispatchQueue.main.async {
                self.autoDepStatus = "ACTIVE"
                completion?("No external dependencies detected.")
            }
            return
        }
        
        // Find missing libraries (not in installedLibraries and not built-in)
        let installedNames = Set(self.installedLibraries.map { $0.name.lowercased() })
        let missing = detected.filter { lib in
            let lower = lib.lowercased()
            if lower.contains("(i2c)") || lower.contains("(bus)") || lower.contains("(nvs)") || lower == "wire" || lower == "spi" || lower == "wifi" || lower == "freertos" {
                return false
            }
            return !installedNames.contains(lower)
        }
        
        let elapsedMs = max(0.2, (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0)
        self.lastResolveTimeMs = elapsedMs
        
        if missing.isEmpty {
            DispatchQueue.main.async {
                self.autoDepStatus = "ALL SATISFIED (\(String(format: "%.1f", elapsedMs))ms)"
                completion?("All \(detected.count) dependencies satisfied.")
            }
            return
        }
        
        let resolvedSummary = missing.joined(separator: ", ")
        DispatchQueue.main.async {
            self.lastResolvedLib = resolvedSummary
            self.autoDepStatus = self.autoInstallLibraries ? "INSTALLING (\(missing.count))" : "MISSING (\(missing.count))"
        }
        
        // Real background library installation via arduino-cli (no synthetic stub headers!)
        if autoInstallLibraries {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                for lib in missing {
                    self.installLibraryFast(name: lib)
                }
                DispatchQueue.main.async {
                    self.autoDepStatus = "INSTALLED (\(missing.count))"
                }
            }
        }
        
        completion?("Queued real installation of \(missing.count) library dependencies: \(resolvedSummary)")
    }
    
    /// Ultra-fast background library installer utilizing ~/.microcode/libraries_cache/
    public func installLibraryFast(name: String, completion: ((Bool) -> Void)? = nil) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let cacheDir = "\(home)/.microcode/libraries_cache"
        let arduinoLibDir = "\(home)/Documents/Arduino/libraries"
        try? fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: arduinoLibDir, withIntermediateDirectories: true)
        
        let safeName = name.replacingOccurrences(of: " ", with: "_")
        let cachedPath = "\(cacheDir)/\(safeName)"
        let targetPath = "\(arduinoLibDir)/\(safeName)"
        
        // Check cache for instant 0-second copy
        if fm.fileExists(atPath: cachedPath) && !fm.fileExists(atPath: targetPath) {
            try? fm.copyItem(atPath: cachedPath, toPath: targetPath)
            DispatchQueue.main.async { [weak self] in
                self?.refreshInstalledLibraries()
                self?.lastResolvedLib = "\(name) (cached)"
                completion?(true)
            }
            return
        }
        
        // Otherwise use arduino-cli in background
        let cliPath = toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "/opt/homebrew/bin/arduino-cli"
        guard fm.fileExists(atPath: cliPath) else {
            completion?(false)
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "\(self.arduinoDataEnvPrefix)\(cliPath) lib install \"\(name)\""]
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                // Populate cache
                if fm.fileExists(atPath: targetPath) && !fm.fileExists(atPath: cachedPath) {
                    try? fm.copyItem(atPath: targetPath, toPath: cachedPath)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.refreshInstalledLibraries()
                    completion?(true)
                }
            } else {
                completion?(false)
            }
        } catch {
            completion?(false)
        }
    }
    
    // MARK: - Install Library via arduino-cli
    
    public func installLibrary(name: String, completion: @escaping (Bool, String) -> Void) {
        isWorking = true
        workingMessage = "Installing '\(name)' via arduino-cli..."
        appendLog("[INSTALL] Starting installation of '\(name)'...")
        
        let cliPath = toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "/opt/homebrew/bin/arduino-cli"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            let script = "\(self?.arduinoDataEnvPrefix ?? "")\(cliPath) lib install \"\(name)\""
            process.arguments = ["-c", script]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if let str = String(data: chunk, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        self?.appendLog(str)
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                fileHandle.readabilityHandler = nil
                
                let success = process.terminationStatus == 0
                DispatchQueue.main.async {
                    self?.isWorking = false
                    self?.workingMessage = ""
                    if success {
                        self?.appendLog("[SUCCESS] Library '\(name)' installed successfully!\n")
                        self?.refreshInstalledLibraries()
                        completion(true, "Successfully installed \(name)")
                    } else {
                        self?.appendLog("[ERROR] Failed to install '\(name)'. Exit code: \(process.terminationStatus)\n")
                        completion(false, "Installation failed with code \(process.terminationStatus)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isWorking = false
                    self?.workingMessage = ""
                    self?.appendLog("[EXCEPTION] \(error.localizedDescription)\n")
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Install Multiple Detected Libraries
    
    public func installMultipleLibraries(names: [String]) {
        guard !names.isEmpty else { return }
        
        // Filter out built-in libraries
        let installable = names.filter { !$0.contains("(I2C)") && !$0.contains("(Bus)") && !$0.contains("(NVS)") }
        guard !installable.isEmpty else {
            appendLog("[INFO] All detected libraries are built-in hardware headers (Wire/SPI/Preferences).\n")
            return
        }
        
        isWorking = true
        workingMessage = "Installing \(installable.count) libraries..."
        appendLog("[BATCH] Installing detected dependencies: \(installable.joined(separator: ", "))...\n")
        
        var remaining = installable
        func stepNext() {
            guard !remaining.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.isWorking = false
                    self?.workingMessage = ""
                    self?.appendLog("[BATCH COMPLETE] All detected libraries installed!\n")
                    self?.refreshInstalledLibraries()
                }
                return
            }
            
            let nextLib = remaining.removeFirst()
            self.installLibrary(name: nextLib) { _, _ in
                stepNext()
            }
        }
        
        stepNext()
    }
    
    // MARK: - Uninstall Library
    
    public func uninstallLibrary(name: String, completion: @escaping (Bool, String) -> Void) {
        isWorking = true
        workingMessage = "Uninstalling '\(name)'..."
        appendLog("[UNINSTALL] Removing '\(name)'...")
        
        let cliPath = toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "/opt/homebrew/bin/arduino-cli"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            let script = "\(self?.arduinoDataEnvPrefix ?? "")\(cliPath) lib uninstall \"\(name)\""
            process.arguments = ["-c", script]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Also check if directory in ~/Documents/Arduino/libraries still exists, remove it
                if let self = self {
                    let targetFolder = self.userLibrariesDir.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: targetFolder.path) {
                        try? FileManager.default.removeItem(at: targetFolder)
                    }
                }
                
                DispatchQueue.main.async {
                    self?.isWorking = false
                    self?.workingMessage = ""
                    self?.appendLog("[SUCCESS] Library '\(name)' removed.\n")
                    self?.refreshInstalledLibraries()
                    completion(true, "Uninstalled \(name)")
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isWorking = false
                    self?.workingMessage = ""
                    self?.appendLog("[ERROR] Failed to uninstall: \(error.localizedDescription)\n")
                    completion(false, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Search Registry
    
    public func searchLibraries(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        isWorking = true
        workingMessage = "Searching Arduino Registry for '\(trimmed)'..."
        let cliPath = toolchains.first(where: { $0.binaryName == "arduino-cli" })?.path ?? "/opt/homebrew/bin/arduino-cli"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            let script = "\(self?.arduinoDataEnvPrefix ?? "")\(cliPath) lib search \"\(trimmed)\" --names"
            process.arguments = ["-c", script]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    var results: [EmbeddedLibrary] = []
                    let lines = str.components(separatedBy: "\n")
                    for line in lines {
                        if line.hasPrefix("Name: ") {
                            let name = line.replacingOccurrences(of: "Name: ", with: "")
                                .replacingOccurrences(of: "\"", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            let isInst = self?.installedLibraries.contains(where: { $0.name.lowercased() == name.lowercased() }) ?? false
                            results.append(EmbeddedLibrary(
                                name: name,
                                version: isInst ? "Installed" : "Available",
                                location: "Arduino Registry",
                                descriptionText: "Official library from Arduino index",
                                category: "Registry",
                                author: "Open Source",
                                isInstalled: isInst
                            ))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self?.isWorking = false
                        self?.workingMessage = ""
                        self?.searchResults = results
                    }
                    return
                }
            } catch {}
            
            DispatchQueue.main.async {
                self?.isWorking = false
                self?.workingMessage = ""
            }
        }
    }
    
    private func appendLog(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        consoleOutput += "[\(timestamp.suffix(12).prefix(8))] \(text)\n"
    }
}
