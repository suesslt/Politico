import Foundation

struct MemberCommitteeDTO: Decodable, Sendable {
    let ID: String?
    let CommitteeNumber: Int?
    let PersonNumber: Int?
    let CommitteeFunctionName: String?
    let Modified: String?

    var modifiedParsed: Date? {
        Modified.flatMap { ODataDateFormatter.parse($0) }
    }
}
