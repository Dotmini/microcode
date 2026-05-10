import AppKit

extension NSColor {
    /// Create NSColor from hex string
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }
        
        let length = hexSanitized.count
        
        var r, g, b, a: CGFloat
        
        switch length {
        case 6: // RGB (without alpha)
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        case 8: // RGBA
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        default:
            return nil
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    
    /// Convert to hex string
    var hexString: String {
        // Try direct sRGB conversion first
        if let rgbColor = self.usingColorSpace(.sRGB) {
            let r = Int(max(0, min(1, rgbColor.redComponent)) * 255)
            let g = Int(max(0, min(1, rgbColor.greenComponent)) * 255)
            let b = Int(max(0, min(1, rgbColor.blueComponent)) * 255)
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        
        // Handle catalog/dynamic colors by converting through CGColor
        let cgColor = self.cgColor
        if let nsColor = NSColor(cgColor: cgColor), let rgbColor = nsColor.usingColorSpace(.sRGB) {
            let r = Int(max(0, min(1, rgbColor.redComponent)) * 255)
            let g = Int(max(0, min(1, rgbColor.greenComponent)) * 255)
            let b = Int(max(0, min(1, rgbColor.blueComponent)) * 255)
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        
        // Fallback for unresolvable colors (better than black)
        return "#D4D4D4"
    }
}
