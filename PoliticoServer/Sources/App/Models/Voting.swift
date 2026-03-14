import Fluent
import Vapor

final class Voting: Model, Content, @unchecked Sendable {
    static let schema = "voting"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Parent(key: "vote_id")
    var vote: Vote

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "decision")
    var decision: Int

    @Field(key: "decision_text")
    var decisionText: String?

    init() {}

    init(id: Int, voteID: Int, personNumber: Int, decision: Int) {
        self.id = id
        self.$vote.id = voteID
        self.personNumber = personNumber
        self.decision = decision
    }
}
