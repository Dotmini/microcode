import MicroCodeCore

@main
struct MicroCodeWindows {
    static func main() {
        print("Starting MicroCode on Windows...")
        let bridge = BackendBridge()
        let result = bridge.startEngine()
        print(result)
        
        // Loop or hook up Windows UI (e.g. WinUI)
    }
}
