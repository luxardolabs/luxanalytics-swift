import Foundation
#if canImport(Network)
import Network
#endif

/// Monitors network connectivity status
actor NetworkMonitor {
    static let shared = NetworkMonitor()
    
    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.luxardolabs.LuxAnalytics.networkmonitor")
    #endif
    
    private var _isConnected = true
    private var _isExpensive = false
    
    var isConnected: Bool {
        return _isConnected
    }
    
    var isExpensive: Bool {
        return _isExpensive
    }
    
    private init() {
        #if canImport(Network)
        Task {
            await startMonitoring()
        }
        #endif
    }
    
    #if canImport(Network)
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.updateStatus(path: path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateStatus(path: NWPath) {
        _isConnected = path.status == .satisfied
        _isExpensive = path.isExpensive
    }
    #endif
    
    func waitForConnectivity() async {
        guard !_isConnected else { return }
        
        // Wait up to 30 seconds for connectivity
        for _ in 0..<30 {
            if _isConnected { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
    }
}