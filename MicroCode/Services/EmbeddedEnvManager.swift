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
        
        detectEspIdf()
        detectAllToolchains()
        refreshInstalledLibraries()
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
                "/Users/dotmini/.swiftly/bin/clang++",
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
    
    // MARK: - Synthetic Embedded Stubs Deployment (Zero 'file not found' Guarantee)
    
    public func deploySyntheticEmbeddedHeaders(into dir: String = "/tmp/microcode_sketch") {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let freertosDir = (dir as NSString).appendingPathComponent("freertos")
        let driverDir = (dir as NSString).appendingPathComponent("driver")
        try? fm.createDirectory(atPath: freertosDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: driverDir, withIntermediateDirectories: true)
        
        // 1. Arduino.h
        let arduinoHeader = """
        #pragma once
        #include <stdio.h>
        #include <stdint.h>
        #include <stdbool.h>
        #include <math.h>

        #define HIGH 1
        #define LOW 0
        #define INPUT 0
        #define OUTPUT 1
        #define LED_BUILTIN 2

        inline void pinMode(uint8_t pin, uint8_t mode) {}
        inline void digitalWrite(uint8_t pin, uint8_t val) {}
        inline int digitalRead(uint8_t pin) { return 0; }
        inline void delay(uint32_t ms) {}
        inline uint32_t millis() { return 0; }

        struct HardwareSerial {
            void begin(unsigned long baud) {}
            void print(const char* s) {}
            void print(double v) {}
            void println(const char* s) {}
            void println(double v) {}
            template<typename... Args>
            void printf(const char* fmt, Args... args) { ::printf(fmt, args...); }
            explicit operator bool() const { return true; }
        };
        inline HardwareSerial Serial;
        """
        try? arduinoHeader.write(toFile: "\(dir)/Arduino.h", atomically: true, encoding: .utf8)
        
        // 2. freertos/FreeRTOS.h
        let freeRTOSHeader = """
        #pragma once
        #include <stdint.h>
        #include <stddef.h>
        #include <stdbool.h>

        typedef uint32_t TickType_t;
        typedef long BaseType_t;
        typedef unsigned long UBaseType_t;
        typedef void* TaskHandle_t;
        typedef void* QueueHandle_t;
        typedef void* SemaphoreHandle_t;
        typedef void (*TaskFunction_t)(void *);

        #define portMAX_DELAY (TickType_t)0xffffffffUL
        #define pdTRUE  ((BaseType_t) 1)
        #define pdFALSE ((BaseType_t) 0)
        #define pdPASS  (pdTRUE)
        #define pdFAIL  (pdFALSE)
        #define portTICK_PERIOD_MS ((TickType_t) 1)
        #define pdMS_TO_TICKS(ms) ((TickType_t)(ms))
        #define configMAX_PRIORITIES 25
        #define tskNO_AFFINITY 0x7FFFFFFF
        """
        try? freeRTOSHeader.write(toFile: "\(freertosDir)/FreeRTOS.h", atomically: true, encoding: .utf8)
        
        // 3. freertos/task.h
        let taskHeader = """
        #pragma once
        #include "FreeRTOS.h"

        #ifdef __cplusplus
        extern "C" {
        #endif

        inline BaseType_t xTaskCreate(TaskFunction_t pxTaskCode, const char * const pcName, const uint32_t usStackDepth, void * const pvParameters, UBaseType_t uxPriority, TaskHandle_t * const pxCreatedTask) { return pdPASS; }
        inline BaseType_t xTaskCreatePinnedToCore(TaskFunction_t pxTaskCode, const char * const pcName, const uint32_t usStackDepth, void * const pvParameters, UBaseType_t uxPriority, TaskHandle_t * const pxCreatedTask, const BaseType_t xCoreID) { return pdPASS; }
        inline void vTaskDelay(const TickType_t xTicksToDelay) {}
        inline void vTaskDelayUntil(TickType_t * const pxPreviousWakeTime, const TickType_t xTimeIncrement) {}
        inline void vTaskDelete(TaskHandle_t xTaskToDelete) {}
        inline TickType_t xTaskGetTickCount(void) { return 0; }
        inline UBaseType_t uxTaskPriorityGet(const TaskHandle_t xTask) { return 1; }
        inline void vTaskPrioritySet(TaskHandle_t xTask, UBaseType_t uxNewPriority) {}
        inline void vTaskSuspend(TaskHandle_t xTaskToSuspend) {}
        inline void vTaskResume(TaskHandle_t xTaskToResume) {}

        #ifdef __cplusplus
        }
        #endif
        """
        try? taskHeader.write(toFile: "\(freertosDir)/task.h", atomically: true, encoding: .utf8)
        
        // 4. freertos/queue.h
        let queueHeader = """
        #pragma once
        #include "FreeRTOS.h"

        #ifdef __cplusplus
        extern "C" {
        #endif

        inline QueueHandle_t xQueueCreate(const UBaseType_t uxQueueLength, const UBaseType_t uxItemSize) { return (QueueHandle_t)1; }
        inline BaseType_t xQueueSend(QueueHandle_t xQueue, const void * const pvItemToQueue, TickType_t xTicksToWait) { return pdPASS; }
        inline BaseType_t xQueueReceive(QueueHandle_t xQueue, void * const pvBuffer, TickType_t xTicksToWait) { return pdPASS; }
        inline void vQueueDelete(QueueHandle_t xQueue) {}
        inline UBaseType_t uxQueueMessagesWaiting(const QueueHandle_t xQueue) { return 0; }

        #ifdef __cplusplus
        }
        #endif
        """
        try? queueHeader.write(toFile: "\(freertosDir)/queue.h", atomically: true, encoding: .utf8)
        
        // 5. freertos/semphr.h
        let semphrHeader = """
        #pragma once
        #include "FreeRTOS.h"
        #include "queue.h"

        #ifdef __cplusplus
        extern "C" {
        #endif

        inline SemaphoreHandle_t xSemaphoreCreateBinary(void) { return (SemaphoreHandle_t)1; }
        inline SemaphoreHandle_t xSemaphoreCreateMutex(void) { return (SemaphoreHandle_t)1; }
        inline BaseType_t xSemaphoreTake(SemaphoreHandle_t xSemaphore, TickType_t xBlockTime) { return pdPASS; }
        inline BaseType_t xSemaphoreGive(SemaphoreHandle_t xSemaphore) { return pdPASS; }
        inline void vSemaphoreDelete(SemaphoreHandle_t xSemaphore) {}

        #ifdef __cplusplus
        }
        #endif
        """
        try? semphrHeader.write(toFile: "\(freertosDir)/semphr.h", atomically: true, encoding: .utf8)
        
        // 6. esp_err.h
        let espErrHeader = """
        #pragma once
        #include <stdint.h>

        typedef int32_t esp_err_t;
        #define ESP_OK 0
        #define ESP_FAIL -1
        #define ESP_ERR_NO_MEM 0x101
        #define ESP_ERR_INVALID_ARG 0x102
        #define ESP_ERR_INVALID_STATE 0x103
        #define ESP_ERR_INVALID_SIZE 0x104
        #define ESP_ERR_NOT_FOUND 0x105
        #define ESP_ERR_TIMEOUT 0x107
        inline const char* esp_err_to_name(esp_err_t code) { return "ESP_OK"; }
        """
        try? espErrHeader.write(toFile: "\(dir)/esp_err.h", atomically: true, encoding: .utf8)
        
        // 7. esp_system.h
        let espSystemHeader = """
        #pragma once
        #include "esp_err.h"
        #include <stdint.h>

        #ifdef __cplusplus
        extern "C" {
        #endif

        inline void esp_restart(void) {}
        inline uint32_t esp_random(void) { return 0; }
        inline uint32_t esp_get_free_heap_size(void) { return 320000; }
        inline uint32_t esp_get_minimum_free_heap_size(void) { return 280000; }

        #ifdef __cplusplus
        }
        #endif
        """
        try? espSystemHeader.write(toFile: "\(dir)/esp_system.h", atomically: true, encoding: .utf8)
        
        // 8. esp_log.h
        let espLogHeader = """
        #pragma once
        #include <stdio.h>

        #define ESP_LOGE(tag, format, ...) printf("[E][%s] " format "\\n", tag, ##__VA_ARGS__)
        #define ESP_LOGW(tag, format, ...) printf("[W][%s] " format "\\n", tag, ##__VA_ARGS__)
        #define ESP_LOGI(tag, format, ...) printf("[I][%s] " format "\\n", tag, ##__VA_ARGS__)
        #define ESP_LOGD(tag, format, ...) printf("[D][%s] " format "\\n", tag, ##__VA_ARGS__)
        #define ESP_LOGV(tag, format, ...) printf("[V][%s] " format "\\n", tag, ##__VA_ARGS__)
        """
        try? espLogHeader.write(toFile: "\(dir)/esp_log.h", atomically: true, encoding: .utf8)
        
        // 9. driver/gpio.h
        let gpioHeader = """
        #pragma once
        #include "esp_err.h"
        #include <stdint.h>

        #ifdef __cplusplus
        extern "C" {
        #endif

        typedef enum {
            GPIO_NUM_NC = -1,
            GPIO_NUM_0 = 0,
            GPIO_NUM_1 = 1,
            GPIO_NUM_2 = 2,
            GPIO_NUM_3 = 3,
            GPIO_NUM_4 = 4,
            GPIO_NUM_5 = 5,
            GPIO_NUM_6 = 6,
            GPIO_NUM_7 = 7,
            GPIO_NUM_8 = 8,
            GPIO_NUM_9 = 9,
            GPIO_NUM_10 = 10,
            GPIO_NUM_11 = 11,
            GPIO_NUM_12 = 12,
            GPIO_NUM_13 = 13,
            GPIO_NUM_14 = 14,
            GPIO_NUM_15 = 15,
            GPIO_NUM_16 = 16,
            GPIO_NUM_17 = 17,
            GPIO_NUM_18 = 18,
            GPIO_NUM_19 = 19,
            GPIO_NUM_20 = 20,
            GPIO_NUM_21 = 21,
            GPIO_NUM_35 = 35,
            GPIO_NUM_36 = 36,
            GPIO_NUM_37 = 37,
            GPIO_NUM_38 = 38,
            GPIO_NUM_47 = 47,
            GPIO_NUM_48 = 48,
            GPIO_NUM_MAX
        } gpio_num_t;

        typedef enum {
            GPIO_MODE_DISABLE = 0,
            GPIO_MODE_INPUT = 1,
            GPIO_MODE_OUTPUT = 2,
            GPIO_MODE_OUTPUT_OD = 3,
            GPIO_MODE_INPUT_OUTPUT_OD = 4,
            GPIO_MODE_INPUT_OUTPUT = 5
        } gpio_mode_t;

        typedef enum {
            GPIO_PULLUP_DISABLE = 0,
            GPIO_PULLUP_ENABLE = 1
        } gpio_pullup_t;

        typedef enum {
            GPIO_PULLDOWN_DISABLE = 0,
            GPIO_PULLDOWN_ENABLE = 1
        } gpio_pulldown_t;

        typedef struct {
            uint64_t pin_bit_mask;
            gpio_mode_t mode;
            gpio_pullup_t pull_up_en;
            gpio_pulldown_t pull_down_en;
            int intr_type;
        } gpio_config_t;

        inline esp_err_t gpio_config(const gpio_config_t *pGPIOConfig) { return ESP_OK; }
        inline esp_err_t gpio_reset_pin(gpio_num_t gpio_num) { return ESP_OK; }
        inline esp_err_t gpio_set_direction(gpio_num_t gpio_num, gpio_mode_t mode) { return ESP_OK; }
        inline esp_err_t gpio_set_level(gpio_num_t gpio_num, uint32_t level) { return ESP_OK; }
        inline int gpio_get_level(gpio_num_t gpio_num) { return 0; }

        #ifdef __cplusplus
        }
        #endif
        """
        try? gpioHeader.write(toFile: "\(driverDir)/gpio.h", atomically: true, encoding: .utf8)
        
        // 10. nvs_flash.h
        let nvsHeader = """
        #pragma once
        #include "esp_err.h"

        #ifdef __cplusplus
        extern "C" {
        #endif

        inline esp_err_t nvs_flash_init(void) { return ESP_OK; }
        inline esp_err_t nvs_flash_erase(void) { return ESP_OK; }

        #ifdef __cplusplus
        }
        #endif
        """
        try? nvsHeader.write(toFile: "\(dir)/nvs_flash.h", atomically: true, encoding: .utf8)
        
        // 11. Wire.h (I2C)
        let wireHeader = """
        #pragma once
        #include "Arduino.h"
        class TwoWire {
        public:
            void begin(int sda = -1, int scl = -1, uint32_t freq = 100000) {}
            void beginTransmission(uint8_t address) {}
            uint8_t endTransmission(bool sendStop = true) { return 0; }
            size_t write(uint8_t data) { return 1; }
            size_t write(const uint8_t *data, size_t quantity) { return quantity; }
            uint8_t requestFrom(uint8_t address, size_t size) { return size; }
            int read() { return 0; }
            int available() { return 0; }
        };
        inline TwoWire Wire;
        """
        try? wireHeader.write(toFile: "\(dir)/Wire.h", atomically: true, encoding: .utf8)
        
        // 12. SPI.h
        let spiHeader = """
        #pragma once
        #include "Arduino.h"
        class SPIClass {
        public:
            void begin(int8_t sck = -1, int8_t miso = -1, int8_t mosi = -1, int8_t ss = -1) {}
            void end() {}
            uint8_t transfer(uint8_t data) { return data; }
        };
        inline SPIClass SPI;
        """
        try? spiHeader.write(toFile: "\(dir)/SPI.h", atomically: true, encoding: .utf8)
        
        // 13. WiFi.h
        let wifiHeader = """
        #pragma once
        #include "Arduino.h"
        #define WL_CONNECTED 3
        #define WL_IDLE_STATUS 0
        #define WL_NO_SSID_AVAIL 1
        #define WL_CONNECT_FAILED 4
        #define WL_DISCONNECTED 6
        class WiFiClass {
        public:
            int begin(const char* ssid, const char *passphrase = nullptr) { return WL_CONNECTED; }
            int status() { return WL_CONNECTED; }
            void disconnect(bool wifioff = false) {}
            const char* localIP() { return "192.168.1.100"; }
        };
        inline WiFiClass WiFi;
        """
        try? wifiHeader.write(toFile: "\(dir)/WiFi.h", atomically: true, encoding: .utf8)
    }
    
    // MARK: - Instant Synthetic Library Header Generator (<2ms)
    
    public func deploySyntheticLibraryHeader(named name: String, into dir: String = "/tmp/microcode_sketch") {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let lower = name.lowercased()
        
        if lower.contains("dht") {
            let dhtHeader = """
            #pragma once
            #include "Arduino.h"
            #define DHT11 11
            #define DHT22 22
            #define DHT21 21
            class DHT {
            public:
                DHT(uint8_t pin, uint8_t type, uint8_t count = 6) {}
                void begin(uint8_t usec = 55) {}
                float readTemperature(bool S = false, bool force = false) { return 25.0f; }
                float readHumidity(bool force = false) { return 60.0f; }
                bool read(bool force = false) { return true; }
            };
            """
            try? dhtHeader.write(toFile: "\(dir)/DHT.h", atomically: true, encoding: .utf8)
            try? dhtHeader.write(toFile: "\(dir)/DHT_U.h", atomically: true, encoding: .utf8)
        } else if lower.contains("ssd1306") || lower.contains("adafruit ssd1306") {
            let oledHeader = """
            #pragma once
            #include "Arduino.h"
            #include "Wire.h"
            #define SSD1306_SWITCHCAPVCC 0x02
            #define WHITE 1
            #define BLACK 0
            #define INVERSE 2
            class Adafruit_SSD1306 {
            public:
                Adafruit_SSD1306(uint8_t w, uint8_t h, void *twi = nullptr, int8_t rst_pin = -1) {}
                bool begin(uint8_t switchvcc = SSD1306_SWITCHCAPVCC, uint8_t i2caddr = 0x3C, bool reset = true, bool periphBegin = true) { return true; }
                void clearDisplay() {}
                void display() {}
                void setTextSize(uint8_t s) {}
                void setTextColor(uint16_t c) {}
                void setTextColor(uint16_t c, uint16_t bg) {}
                void setCursor(int16_t x, int16_t y) {}
                void print(const char *s) {}
                void print(int n) {}
                void print(float f) {}
                void println(const char *s = "") {}
                void println(int n) {}
                void println(float f) {}
                void drawPixel(int16_t x, int16_t y, uint16_t color) {}
                void drawLine(int16_t x0, int16_t y0, int16_t x1, int16_t y1, uint16_t color) {}
                void drawRect(int16_t x, int16_t y, int16_t w, int16_t h, uint16_t color) {}
                void fillRect(int16_t x, int16_t y, int16_t w, int16_t h, uint16_t color) {}
            };
            """
            try? oledHeader.write(toFile: "\(dir)/Adafruit_SSD1306.h", atomically: true, encoding: .utf8)
        } else if lower.contains("gfx") {
            let gfxHeader = """
            #pragma once
            #include "Arduino.h"
            class Adafruit_GFX {
            public:
                Adafruit_GFX(int16_t w, int16_t h) {}
                virtual void drawPixel(int16_t x, int16_t y, uint16_t color) {}
            };
            """
            try? gfxHeader.write(toFile: "\(dir)/Adafruit_GFX.h", atomically: true, encoding: .utf8)
        } else if lower.contains("fastled") {
            let fastledHeader = """
            #pragma once
            #include "Arduino.h"
            struct CRGB {
                uint8_t r, g, b;
                CRGB() : r(0), g(0), b(0) {}
                CRGB(uint8_t r, uint8_t g, uint8_t b) : r(r), g(g), b(b) {}
                static const uint32_t Red = 0xFF0000;
                static const uint32_t Green = 0x00FF00;
                static const uint32_t Blue = 0x0000FF;
                static const uint32_t Black = 0x000000;
                static const uint32_t White = 0xFFFFFF;
            };
            #define WS2812B 1
            #define GRB 1
            class CFastLED {
            public:
                template<int CHIP, uint8_t DATA_PIN, int RGB_ORDER>
                void addLeds(CRGB *data, int nLeds) {}
                void show() {}
                void clear() {}
                void setBrightness(uint8_t scale) {}
            };
            inline CFastLED FastLED;
            """
            try? fastledHeader.write(toFile: "\(dir)/FastLED.h", atomically: true, encoding: .utf8)
        } else if lower.contains("neopixel") {
            let neoHeader = """
            #pragma once
            #include "Arduino.h"
            #define NEO_GRB 0x01
            #define NEO_KHZ800 0x02
            class Adafruit_NeoPixel {
            public:
                Adafruit_NeoPixel(uint16_t n = 0, int16_t p = -1, uint16_t t = NEO_GRB + NEO_KHZ800) {}
                void begin() {}
                void show() {}
                void setPixelColor(uint16_t n, uint8_t r, uint8_t g, uint8_t b) {}
                void setPixelColor(uint16_t n, uint32_t c) {}
                void setBrightness(uint8_t b) {}
                void clear() {}
                static uint32_t Color(uint8_t r, uint8_t g, uint8_t b) { return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b; }
            };
            """
            try? neoHeader.write(toFile: "\(dir)/Adafruit_NeoPixel.h", atomically: true, encoding: .utf8)
        } else if lower.contains("arduinojson") {
            let jsonHeader = """
            #pragma once
            #include "Arduino.h"
            template <size_t CAPACITY>
            class StaticJsonDocument {
            public:
                template <typename T> void operator[](const char *key) {}
            };
            class DynamicJsonDocument {
            public:
                DynamicJsonDocument(size_t cap) {}
                template <typename T> void operator[](const char *key) {}
            };
            """
            try? jsonHeader.write(toFile: "\(dir)/ArduinoJson.h", atomically: true, encoding: .utf8)
        } else if lower.contains("pubsubclient") {
            let mqttHeader = """
            #pragma once
            #include "Arduino.h"
            class PubSubClient {
            public:
                PubSubClient() {}
                PubSubClient& setServer(const char *domain, uint16_t port) { return *this; }
                PubSubClient& setCallback(void (*callback)(char*, uint8_t*, unsigned int)) { return *this; }
                bool connect(const char *id) { return true; }
                bool connect(const char *id, const char *user, const char *pass) { return true; }
                bool publish(const char *topic, const char *payload) { return true; }
                bool subscribe(const char *topic) { return true; }
                bool loop() { return true; }
                bool connected() { return true; }
            };
            """
            try? mqttHeader.write(toFile: "\(dir)/PubSubClient.h", atomically: true, encoding: .utf8)
        } else if lower.contains("liquidcrystal") {
            let lcdHeader = """
            #pragma once
            #include "Arduino.h"
            class LiquidCrystal_I2C {
            public:
                LiquidCrystal_I2C(uint8_t lcd_Addr, uint8_t lcd_cols, uint8_t lcd_rows) {}
                void init() {}
                void clear() {}
                void home() {}
                void backlight() {}
                void noBacklight() {}
                void setCursor(uint8_t col, uint8_t row) {}
                void print(const char *s) {}
                void print(int n) {}
            };
            """
            try? lcdHeader.write(toFile: "\(dir)/LiquidCrystal_I2C.h", atomically: true, encoding: .utf8)
        } else if lower.contains("servo") {
            let servoHeader = """
            #pragma once
            #include "Arduino.h"
            class Servo {
            public:
                uint8_t attach(int pin) { return 1; }
                void detach() {}
                void write(int value) {}
                int read() { return 90; }
                bool attached() { return true; }
            };
            typedef Servo ESP32Servo;
            """
            try? servoHeader.write(toFile: "\(dir)/Servo.h", atomically: true, encoding: .utf8)
            try? servoHeader.write(toFile: "\(dir)/ESP32Servo.h", atomically: true, encoding: .utf8)
        } else if lower.contains("tinygps") {
            let gpsHeader = """
            #pragma once
            #include "Arduino.h"
            struct RawDegrees { double deg; };
            struct TinyGPSLocation {
                bool isValid() const { return true; }
                double lat() { return 13.7563; }
                double lng() { return 100.5018; }
            };
            class TinyGPSPlus {
            public:
                TinyGPSLocation location;
                bool encode(char c) { return true; }
            };
            """
            try? gpsHeader.write(toFile: "\(dir)/TinyGPSPlus.h", atomically: true, encoding: .utf8)
            try? gpsHeader.write(toFile: "\(dir)/TinyGPS++.h", atomically: true, encoding: .utf8)
        } else {
            // Generic Auto-Synthesized C++ Header
            let safeName = name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ".h", with: "")
            let genericHeader = """
            #pragma once
            #include "Arduino.h"
            // MicroCode Auto-Synthesized Header: \(name)
            class \(safeName) {
            public:
                \(safeName)() {}
                bool begin() { return true; }
            };
            """
            try? genericHeader.write(toFile: "\(dir)/\(safeName).h", atomically: true, encoding: .utf8)
        }
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
                process.arguments = ["-c", "ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib list --format json 2>/dev/null || ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib list"]
                
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
        
        // 1. INSTANT SYNTHETIC RESOLUTION (< 2ms)
        // Synthesize headers into /tmp/microcode_sketch immediately so compiler / linting passes without waiting!
        for lib in detected {
            deploySyntheticLibraryHeader(named: lib, into: "/tmp/microcode_sketch")
        }
        
        let elapsedMs = max(1.2, (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0)
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
            self.autoDepStatus = "RESOLVED (\(String(format: "%.1f", elapsedMs))ms)"
        }
        
        // 2. BACKGROUND ASYNCHRONOUS AUTO-INSTALL (Non-blocking)
        if autoInstallLibraries {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                for lib in missing {
                    self.installLibraryFast(name: lib)
                }
            }
        }
        
        completion?("Auto-resolved \(missing.count) dependencies in \(String(format: "%.1f", elapsedMs))ms: \(resolvedSummary)")
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
        process.arguments = ["-c", "ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib install \"\(name)\""]
        
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
            let script = "ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib install \"\(name)\""
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
            let script = "ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib uninstall \"\(name)\""
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
            let script = "ARDUINO_DIRECTORIES_DATA=/tmp/arduino15 \(cliPath) lib search \"\(trimmed)\" --names"
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
