import CoreLocation

struct LocationState {
    let coordinate: CLLocationCoordinate2D
    let timeZone: TimeZone
}

final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var callback: ((LocationState) -> Void)?

    func start(onUpdate: @escaping (LocationState) -> Void) {
        callback = onUpdate
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1000

        if CLLocationManager.locationServicesEnabled() {
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            if status == .authorized || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorized || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if location.horizontalAccuracy < 0 { return }

        let coord = location.coordinate
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let tz = placemarks?.first?.timeZone ?? .current
            let state = LocationState(coordinate: coord, timeZone: tz)
            self.callback?(state)
        }
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
    }
}
