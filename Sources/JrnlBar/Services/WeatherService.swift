import Foundation

// MARK: - Weather Service (Open-Meteo, free, no API key)

actor WeatherService {
    static let shared = WeatherService()

    /// Fetch a simple weather summary (current temp and condition).
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> String {
        let tempUnit = UserDefaults.standard.string(forKey: "weatherTempUnit") ?? "fahrenheit"
        let windUnit = UserDefaults.standard.string(forKey: "weatherWindUnit") ?? "mph"
        let tempSymbol = tempUnit == "celsius" ? "°C" : "°F"
        
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: tempUnit),
            URLQueryItem(name: "windspeed_unit", value: windUnit)
        ]
            
        guard let url = components.url else { throw WeatherError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let decoder = JSONDecoder()
        let r = try decoder.decode(OMResponse.self, from: data)
        guard let current = r.current else { throw WeatherError.missingData }
        
        let desc = WeatherCode.description(for: current.weather_code)
        let temp = Int(current.temperature_2m.rounded())
        return "\(temp)\(tempSymbol), \(desc)"
    }
}

enum WeatherError: Error, LocalizedError {
    case invalidURL
    case missingData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Couldn't build weather request URL."
        case .missingData: return "Weather data was incomplete."
        }
    }
}

// MARK: - Open-Meteo Response Models

private struct OMResponse: Decodable {
    let current: OMCurrent?
}

private struct OMCurrent: Decodable {
    let temperature_2m: Double
    let weather_code: Int
}

// MARK: - WMO Weather Codes

enum WeatherCode {
    static func description(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
}
