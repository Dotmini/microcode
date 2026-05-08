import CodeTunnerCore

@main
struct CodeTunnerLinux {
    static func main() {
        print("Starting CodeTunner on Linux...")
        let bridge = BackendBridge()
        let result = bridge.startEngine()
        print(result)
        
        // Loop or hook up Linux UI (e.g. GTK+)
    }
}
