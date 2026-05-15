import Foundation

extension URL {
    func replacingScheme(from: String, to: String) -> URL? {
        guard self.scheme == from else { return self }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        components?.scheme = to
        return components?.url
    }
}
