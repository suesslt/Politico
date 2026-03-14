import Foundation

struct SessionDTO: Decodable, Sendable {
    let ID: Int
    let SessionName: String?
    let Title: String?
    let Abbreviation: String?
    let StartDate: String?
    let EndDate: String?
    let Modified: String?

    var startDateParsed: Date? {
        StartDate.flatMap { ODataDateFormatter.parse($0) }
    }

    var endDateParsed: Date? {
        EndDate.flatMap { ODataDateFormatter.parse($0) }
    }

    var modifiedParsed: Date? {
        Modified.flatMap { ODataDateFormatter.parse($0) }
    }
}
