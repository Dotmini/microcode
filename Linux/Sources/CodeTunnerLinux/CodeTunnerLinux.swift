import MicroCodeCore

@main
struct MicroCodeLinux {
    static func main() {
        print("Starting MicroCode on Linux...")
        let bridge = BackendBridge()
        let result = bridge.startEngine()
        print(result)
        
        // Loop or hook up Linux UI (e.g. GTK+)
    }
}
