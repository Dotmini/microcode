import Foundation
import CoreGraphics
import AppKit

/// Native macOS WindowServer & Kernel Process-Tree Probe for Controlled IDE Benchmarks
/// Queries CGWindowListCopyWindowInfo at 500 Hz (2ms interval) to detect exact time-to-first-window.

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: window_probe <wait-window|check-window> <owner_or_bundle_match> [timeout_ms]\n", stderr)
    exit(2)
}

let mode = args[1]
let targetMatch = args[2].lowercased()
let timeoutMs = args.count >= 4 ? (Double(args[3]) ?? 15000.0) : 15000.0

func findMatchingWindow(target: String) -> (windowID: Int, pid: Int32, ownerName: String, width: Int, height: Int)? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for win in windowList {
        guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        guard let pid = win[kCGWindowOwnerPID as String] as? Int32 else { continue }
        let ownerName = (win[kCGWindowOwnerName as String] as? String) ?? ""
        let bounds = win[kCGWindowBounds as String] as? [String: Any]
        let width = (bounds?["Width"] as? Int) ?? Int((bounds?["Width"] as? Double) ?? 0)
        let height = (bounds?["Height"] as? Int) ?? Int((bounds?["Height"] as? Double) ?? 0)
        guard width >= 280 && height >= 180 else { continue }

        if ownerName.lowercased().contains(target) {
            let winID = (win[kCGWindowNumber as String] as? Int) ?? 0
            return (winID, pid, ownerName, width, height)
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let bundleURL = app.bundleURL?.path.lowercased() ?? ""
            let execURL = app.executableURL?.path.lowercased() ?? ""
            let localName = (app.localizedName ?? "").lowercased()
            if bundleURL.contains(target) || execURL.contains(target) || localName.contains(target) {
                let winID = (win[kCGWindowNumber as String] as? Int) ?? 0
                return (winID, pid, ownerName, width, height)
            }
        }
    }
    return nil
}

if mode == "check-window" {
    if let found = findMatchingWindow(target: targetMatch) {
        print("{\"found\":true,\"window_id\":\(found.windowID),\"pid\":\(found.pid),\"owner\":\"\(found.ownerName)\",\"width\":\(found.width),\"height\":\(found.height)}")
        exit(0)
    } else {
        print("{\"found\":false}")
        exit(1)
    }
} else if mode == "wait-window" {
    let startNs = DispatchTime.now().uptimeNanoseconds
    let limitNs = UInt64(timeoutMs * 1_000_000.0)
    while true {
        if let found = findMatchingWindow(target: targetMatch) {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
            print(String(format: "{\"found\":true,\"elapsed_ms\":%.2f,\"window_id\":%d,\"pid\":%d,\"owner\":\"%@\",\"width\":%d,\"height\":%d}",
                         elapsedMs, found.windowID, found.pid, found.ownerName, found.width, found.height))
            exit(0)
        }
        if (DispatchTime.now().uptimeNanoseconds - startNs) >= limitNs {
            print("{\"found\":false,\"timeout\":true}")
            exit(1)
        }
        usleep(2000) // 2ms polling (500 Hz)
    }
}
