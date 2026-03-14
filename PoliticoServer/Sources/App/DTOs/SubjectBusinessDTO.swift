import Foundation

struct SubjectBusinessDTO: Decodable, Sendable {
    let IdSubject: StringOrInt?
    let BusinessNumber: Int?
    let BusinessShortNumber: String?
    let Title: String?
    let SortOrder: Int?
}

/// Some OData fields come as String or Int depending on the endpoint
enum StringOrInt: Decodable, Sendable {
    case string(String)
    case int(Int)

    var intValue: Int? {
        switch self {
        case .string(let s): Int(s)
        case .int(let i): i
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.typeMismatch(StringOrInt.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Int"))
        }
    }
}
