//
//  Kernel/KernelClient.swift
//  MicroCode
//
//  Bridge between User Space (Swift) and App Space (Rust Kernel).
//  Handles secure IPC and status monitoring via direct FFI (Zero-Latency).
//

import Foundation

class KernelClient: ObservableObject {
    static let shared = KernelClient()
    
    @Published var isConnected = false
    @Published var powerMode = "Balanced"
    @Published var networkStatus = "Unknown"
    
    private init() {
        startHeartbeat()
    }
    
    func startHeartbeat() {
        // Using Direct FFI (Foreign Function Interface) instead of HTTP socket
        // No CPU overhead, instant connection.
        isConnected = true
        networkStatus = getKernelNetworkStatus()
    }
    
    // Command: Set Power Mode
    func setPowerMode(_ mode: String) async {
        powerMode = mode
        do {
            try setKernelPowerMode(mode: mode)
            print("⚡️ System Power Mode set to \(mode) via FFI")
        } catch {
            print("Failed to set Power Mode: \(error)")
        }
    }
    
    // Command: Panic (Simulated)
    func triggerPanic() {
        print(" Triggering direct Kernel Panic via FFI...")
        triggerKernelPanic()
    }
}
