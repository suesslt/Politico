import Foundation

struct GeschaeftDTO: Decodable, Sendable {
    let ID: Int
    let BusinessShortNumber: String?
    let Title: String?
    let BusinessTypeName: String?
    let BusinessTypeAbbreviation: String?
    let BusinessStatusText: String?
    let BusinessStatusDate: String?
    let SubmissionDate: String?
    let SubmittedBy: String?
    let Description: String?
    let SubmissionCouncilName: String?
    let ResponsibleDepartmentName: String?
    let ResponsibleDepartmentAbbreviation: String?
    let TagNames: String?
    let Modified: String?

    var businessStatusDateParsed: Date? {
        BusinessStatusDate.flatMap { ODataDateFormatter.parse($0) }
    }

    var submissionDateParsed: Date? {
        SubmissionDate.flatMap { ODataDateFormatter.parse($0) }
    }

    var modifiedParsed: Date? {
        Modified.flatMap { ODataDateFormatter.parse($0) }
    }
}
