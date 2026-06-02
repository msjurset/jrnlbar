import Foundation
import CoreLocation

enum LocationError: Error, LocalizedError {
    case unauthorized
    case failed
    
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Location access denied. Enable it in System Settings."
        case .failed: return "Failed to determine current location."
        }
    }
}

final class LocationService: NSObject, CLLocationManagerDelegate, Sendable {
    static let shared = LocationService()
    
    private let manager: CLLocationManager
    private let geocoder: CLGeocoder
    
    // We use a continuations array to support concurrent requests resolving together
    private let continuations = NSLock()
    private var pending: [CheckedContinuation<CLLocation, Error>] = []
    
    override init() {
        self.manager = CLLocationManager()
        self.geocoder = CLGeocoder()
        super.init()
        self.manager.delegate = self
    }
    
    func fetchCurrentLocation() async throws -> CLLocation {
        let authStatus = manager.authorizationStatus
        if authStatus == .denied || authStatus == .restricted {
            throw LocationError.unauthorized
        }
        
        return try await withCheckedThrowingContinuation { cont in
            continuations.lock()
            pending.append(cont)
            let isFirst = pending.count == 1
            continuations.unlock()
            
            if isFirst {
                DispatchQueue.main.async {
                    self.manager.requestWhenInUseAuthorization()
                    self.manager.requestLocation()
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        continuations.lock()
        let waiters = pending
        pending.removeAll()
        continuations.unlock()
        
        for w in waiters {
            w.resume(returning: loc)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuations.lock()
        let waiters = pending
        pending.removeAll()
        continuations.unlock()
        
        for w in waiters {
            w.resume(throwing: LocationError.failed)
        }
    }
}

// Simple locking utility since NSLock isn't Sendable out of the box in older swift versions
private final class SafeLock: @unchecked Sendable {
    private let _lock = Foundation.NSLock()
    func lock() { _lock.lock() }
    func unlock() { _lock.unlock() }
}
