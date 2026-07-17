import SwiftUI
import CoreLocation

struct WeatherData: Equatable {
    let temperature: Double
    let conditionCode: Int
    let isCelsius: Bool

    var temperatureDisplay: String {
        let rounded = Int(temperature.rounded())
        return "\(rounded)°\(isCelsius ? "C" : "F")"
    }

    var conditionIcon: String {
        switch conditionCode {
        case 0: return "☀️"
        case 1: return "🌤️"
        case 2: return "⛅"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51, 53, 55: return "🌦️"
        case 61, 63, 65: return "🌧️"
        case 71, 73, 75: return "❄️"
        case 77: return "🌨️"
        case 80, 81, 82: return "🌦️"
        case 85, 86: return "🌨️"
        case 95, 96, 99: return "⛈️"
        default: return "☁️"
        }
    }
}

@MainActor
final class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var data: WeatherData?
    @Published private(set) var isAvailable = false

    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var refreshTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        checkAuthorization()
    }

    func start() {
        refresh()
    }

    func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        default:
            isAvailable = false
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        MainActor.assumeIsolated {
            lastLocation = loc
            fetchWeather(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            if let last = lastLocation {
                fetchWeather(lat: last.coordinate.latitude, lon: last.coordinate.longitude)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            checkAuthorization()
        }
    }

    private func checkAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAvailable = true
            locationManager.requestLocation()
        case .notDetermined:
            isAvailable = false
        default:
            isAvailable = false
            data = nil
        }
    }

    // MARK: Open-Meteo

    private func fetchWeather(lat: Double, lon: Double) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let isCelsius = Locale.current.measurementSystem == .metric
            let tempUnit = isCelsius ? "celsius" : "fahrenheit"
            let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=\(tempUnit)&timezone=auto")!
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let weather = WeatherData(
                    temperature: json.current.temperature_2m,
                    conditionCode: json.current.weather_code,
                    isCelsius: isCelsius
                )
                try? await Task.sleep(for: .seconds(0.1))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.data = weather
                    self?.isAvailable = true
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self?.isAvailable = false }
                }
            }
        }
    }
}

// MARK: - Open-Meteo JSON

private struct OpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
    }
}
