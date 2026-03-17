import Foundation

struct SubjectDTO: Decodable, Sendable {
    let ID: String
    let IdMeeting: String?
    let SortOrder: Int?

    var idInt: Int? { Int(ID) }
    var idMeetingInt: Int? { IdMeeting.flatMap { Int($0) } }
}
