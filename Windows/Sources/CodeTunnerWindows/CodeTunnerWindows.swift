import CodeTunnerCore

@main
struct CodeTunnerWindows {
    static func main() {
        print("Starting CodeTunner on Windows...")
        let bridge = BackendBridge()
        let result = bridge.startEngine()
        print(result)
        
        // Loop or hook up Windows UI (e.g. WinUI)
    }
}
