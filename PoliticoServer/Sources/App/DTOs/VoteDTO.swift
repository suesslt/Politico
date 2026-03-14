import Foundation

struct VoteDTO: Decodable, Sendable {
    let ID: Int
    let BusinessNumber: Int?
    let BusinessShortNumber: String?
    let BillTitle: String?
    let IdSession: Int?
    let Subject: String?
    let MeaningYes: String?
    let MeaningNo: String?
    let VoteEnd: String?

    var voteEndParsed: Date? {
        VoteEnd.flatMap { ODataDateFormatter.parse($0) }
    }
}
