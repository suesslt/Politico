import Foundation

struct TranscriptDTO: Decodable, Sendable {
    let ID: String
    let PersonNumber: Int?
    let SpeakerFullName: String?
    let SpeakerFunction: String?
    let Text: String?
    let MeetingDate: String?
    let Start: String?
    let End: String?
    let CouncilName: String?
    let ParlGroupAbbreviation: String?
    let CantonAbbreviation: String?
    let SortOrder: Int?
    let TranscriptType: Int?

    enum CodingKeys: String, CodingKey {
        case ID, PersonNumber, SpeakerFullName, SpeakerFunction, Text
        case MeetingDate, Start, End, CouncilName, ParlGroupAbbreviation
        case CantonAbbreviation, SortOrder
        case TranscriptType = "Type"
    }

    var idInt: Int? { Int(ID) }

    var meetingDateParsed: Date? {
        MeetingDate.flatMap { ODataDateFormatter.parse($0) }
    }

    var startParsed: Date? {
        Start.flatMap { ODataDateFormatter.parse($0) }
    }

    var endParsed: Date? {
        End.flatMap { ODataDateFormatter.parse($0) }
    }
}
