import Fluent
import Vapor

final class Voting: Model, Content, @unchecked Sendable {
    static let schema = "voting"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Parent(key: "vote_id")
    var vote: Vote

    @OptionalParent(key: "member_council_id")
    var memberCouncil: MemberCouncil?

    @Field(key: "decision")
    var decision: Int

    @Field(key: "decision_text")
    var decisionText: String?

    init() {}

    init(id: Int, voteID: Int, memberCouncilID: Int?, decision: Int) {
        self.id = id
        self.$vote.id = voteID
        self.$memberCouncil.id = memberCouncilID
        self.decision = decision
    }
}
