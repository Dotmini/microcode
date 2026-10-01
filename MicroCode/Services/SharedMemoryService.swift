import Foundation
import Combine

class SharedMemoryService: ObservableObject {
    static let shared = SharedMemoryService()
    
    @Published var sharedDataFrames: [String] = []
    @Published var sharedArtifacts: [URL] = []
    private let baseURL = "http://127.0.0.1:3000/api/data"
    
    private init() {}

    func shareArtifact(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard !sharedArtifacts.contains(where: { $0.path == normalized.path }) else { return }
        sharedArtifacts.append(normalized)
    }

    func removeArtifact(_ url: URL) {
        sharedArtifacts.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }
    
    func refreshList() async {
        guard let url = URL(string: "\(baseURL)/list") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: LocalBackendAuth.request(url: url))
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
               let names = json["names"] {
                DispatchQueue.main.async {
                    self.sharedDataFrames = names
                }
            }
        } catch {
            print("Failed to list shared dataframes: \(error)")
        }
    }
    
    func getPythonBridgeCode() -> String {
        return """
        import pandas as pd
        import io
        import requests
        import os
        from urllib.parse import urlparse

        class MicroCodeSHM:
            def __init__(self, base_url="http://127.0.0.1:3000/api/data"):
                self.base_url = base_url.rstrip("/")

            def _request(self, method, path, **kwargs):
                endpoint = urlparse(self.base_url)
                headers = {}
                if endpoint.scheme == "http" and endpoint.hostname in ("127.0.0.1", "localhost", "::1") and endpoint.port == 3000:
                    token = os.environ.get("MICROCODE_LOCAL_API_TOKEN", "")
                    if not token:
                        raise RuntimeError("Run this bridge in a MicroCode local kernel or provide MICROCODE_LOCAL_API_TOKEN to the local process")
                    headers["X-MicroCode-Token"] = token
                return requests.request(method, f"{self.base_url}{path}", headers=headers, timeout=20, allow_redirects=False, **kwargs)

            def get(self, name):
                # Try optimized SHM path first
                try:
                    r = self._request("GET", f"/shm/get/{name}")
                    if r.status_code == 200:
                        path = r.json().get("path")
                        if path:
                            return pd.read_parquet(path)
                except:
                    pass
                    
                # Fallback to standard HTTP
                r = self._request("GET", f"/get/{name}")
                if r.status_code == 200:
                    return pd.read_parquet(io.BytesIO(r.content))
                raise Exception(f"Failed to get {name}: {r.status_code} {r.text}")
                
            def set(self, name, df):
                # Try optimized SHM path first (Zero-Copy)
                try:
                    path = f"/tmp/{name}.shm"
                    df.to_parquet(path)
                    r = self._request("POST", f"/shm/store/{name}")
                    if r.status_code == 200: return
                except:
                    pass # Fallback if SHM fails
                    
                # Fallback to standard HTTP
                buf = io.BytesIO()
                df.to_parquet(buf)
                r = self._request("POST", f"/store/{name}", data=buf.getvalue())
                if r.status_code != 200:
                    raise Exception(f"Failed to store {name}: {r.status_code} {r.text}")
                    
            def list(self):
                return self._request("GET", "/list").json().get("names", [])

        shm = MicroCodeSHM()
        """
    }
}
