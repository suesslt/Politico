import Foundation

struct ODataResponse<T: Decodable>: Decodable {
    let items: [T]
    let next: String?

    enum CodingKeys: String, CodingKey {
        case d
    }

    enum DKeys: String, CodingKey {
        case results
        case next = "__next"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Some endpoints return {"d": {"results": [...], "__next": "..."}}
        // Others return {"d": [...]}
        if let d = try? container.nestedContainer(keyedBy: DKeys.self, forKey: .d) {
            self.items = try d.decode([T].self, forKey: .results)
            self.next = try d.decodeIfPresent(String.self, forKey: .next)
        } else {
            self.items = try container.decode([T].self, forKey: .d)
            self.next = nil
        }
    }
}

struct ODataSingleResponse<T: Decodable>: Decodable {
    let d: T?
}

enum ODataDateFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// Parse OData date format: /Date(1234567890000)/
    static func parse(_ string: String) -> Date? {
        guard string.hasPrefix("/Date(") && string.hasSuffix(")/") else {
            return nil
        }
        let start = string.index(string.startIndex, offsetBy: 6)
        let end = string.index(string.endIndex, offsetBy: -2)
        let numberString = String(string[start..<end])
            .components(separatedBy: "+").first ?? String(string[start..<end])
        guard let milliseconds = Double(numberString) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
