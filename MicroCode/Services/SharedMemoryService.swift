import Foundation
import Combine

class SharedMemoryService: ObservableObject {
    static let shared = SharedMemoryService()
    
    @Published var sharedDataFrames: [String] = []
    private let baseURL = "http://127.0.0.1:3000/api/data"
    
    private init() {}
    
    func refreshList() async {
        guard let url = URL(string: "\(baseURL)/list") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
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

        class MicroCodeSHM:
            def __init__(self, base_url="http://127.0.0.1:3000/api/data"):
                self.base_url = base_url
                
            def get(self, name):
                # Try optimized SHM path first
                try:
                    r = requests.get(f"{self.base_url}/shm/get/{name}")
                    if r.status_code == 200:
                        path = r.json().get("path")
                        if path:
                            return pd.read_parquet(path)
                except:
                    pass
                    
                # Fallback to standard HTTP
                r = requests.get(f"{self.base_url}/get/{name}")
                if r.status_code == 200:
                    return pd.read_parquet(io.BytesIO(r.content))
                raise Exception(f"Failed to get {name}: {r.status_code} {r.text}")
                
            def set(self, name, df):
                # Try optimized SHM path first (Zero-Copy)
                try:
                    path = f"/tmp/{name}.shm"
                    df.to_parquet(path)
                    r = requests.post(f"{self.base_url}/shm/store/{name}")
                    if r.status_code == 200: return
                except:
                    pass # Fallback if SHM fails
                    
                # Fallback to standard HTTP
                buf = io.BytesIO()
                df.to_parquet(buf)
                r = requests.post(f"{self.base_url}/store/{name}", data=buf.getvalue())
                if r.status_code != 200:
                    raise Exception(f"Failed to store {name}: {r.status_code} {r.text}")
                    
            def list(self):
                return requests.get(f"{self.base_url}/list").json().get("names", [])

        shm = MicroCodeSHM()
        """
    }
}
