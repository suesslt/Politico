import Foundation

struct MeetingDTO: Decodable, Sendable {
    let ID: String
    let MeetingNumber: Int?
    let IdSession: Int?
    let Council: Int?
    let CouncilName: String?
    let CouncilAbbreviation: String?
    let Date: String?
    let Begin: String?
    let MeetingOrderText: String?
    let SortOrder: Int?
    let SessionName: String?

    var idInt: Int? { Int(ID) }

    var dateParsed: Foundation.Date? {
        Date.flatMap { ODataDateFormatter.parse($0) }
    }
}
