import Foundation

struct CommitteeDTO: Decodable, Sendable {
    let ID: Int
    let CommitteeName: String?
    let Abbreviation1: String?
    let CommitteeTypeName: String?
    let CouncilName: String?
    let CouncilAbbreviation: String?
    let MainCommitteeNumber: Int?
    let Modified: String?

    var modifiedParsed: Date? {
        Modified.flatMap { ODataDateFormatter.parse($0) }
    }
}
