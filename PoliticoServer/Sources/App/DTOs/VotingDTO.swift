import Foundation

struct VotingDTO: Decodable, Sendable {
    let ID: Int
    let IdVote: Int?
    let PersonNumber: Int?
    let Decision: Int?
    let DecisionText: String?
}
