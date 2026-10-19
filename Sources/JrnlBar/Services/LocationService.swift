import Foundation
import CoreLocation

enum LocationError: Error, LocalizedError {
    case unauthorized
    case failed
    
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Location access denied. Enable it in System Settings > Privacy & Security > Location Services."
        case .failed: return "Failed to determine current location. Ensure Location Services are enabled and the app has permission."
        }
    }
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationService()
    
    private var manager: CLLocationManager?
    private let geocoder: CLGeocoder
    
    private let lock = NSLock()
    private var pending: [CheckedContinuation<CLLocation, Error>] = []
    private var timeoutTask: Task<Void, Never>?
    
    override init() {
        self.geocoder = CLGeocoder()
        super.init()
    }
    
    private func getManager() -> CLLocationManager {
        if let manager = manager { return manager }
        let m = CLLocationManager()
        m.delegate = self
        self.manager = m
        return m
    }
    
    func fetchCurrentLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            pending.append(cont)
            let isFirst = pending.count == 1
            lock.unlock()
            
            if isFirst {
                Task {
                    let m = getManager()
                    let status = m.authorizationStatus
                    
                    if status == .denied || status == .restricted {
                        self.failWaiters(with: LocationError.unauthorized)
                        return
                    }
                    
                    if status == .notDetermined {
                        m.requestWhenInUseAuthorization()
                    } else if status == .authorizedAlways {
                        self.startTimeout()
                        m.startUpdatingLocation()
                    } else {
                        self.failWaiters(with: LocationError.unauthorized)
                    }
                }
            }
        }
    }
    
    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            
            failWaiters(with: LocationError.failed)
        }
    }
    
    private func failWaiters(with error: Error) {
        lock.lock()
        let waiters = pending
        pending.removeAll()
        lock.unlock()
        
        if !waiters.isEmpty {
            Task {
                self.manager?.stopUpdatingLocation()
                for w in waiters {
                    w.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchCurrentPlacemark() async throws -> CLPlacemark {
        let loc = try await fetchCurrentLocation()
        let placemarks = try await geocoder.reverseGeocodeLocation(loc)
        guard let first = placemarks.first else { throw LocationError.failed }
        return first
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        Task { @MainActor in
            manager.stopUpdatingLocation()
            self.timeoutTask?.cancel()
            
            self.lock.lock()
            let waiters = self.pending
            self.pending.removeAll()
            self.lock.unlock()
            
            for w in waiters {
                w.resume(returning: loc)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clErr = error as? CLError, clErr.code == .locationUnknown {
            return
        }
        
        Task { @MainActor in
            manager.stopUpdatingLocation()
            self.timeoutTask?.cancel()
            self.failWaiters(with: LocationError.failed)
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedAlways {
                self.startTimeout()
                manager.startUpdatingLocation()
            } else if status == .denied || status == .restricted {
                self.timeoutTask?.cancel()
                self.failWaiters(with: LocationError.unauthorized)
            }
        }
    }
}
