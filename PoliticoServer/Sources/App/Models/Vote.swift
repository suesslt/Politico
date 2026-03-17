import Fluent
import Vapor

final class Vote: Model, Content, @unchecked Sendable {
    static let schema = "vote"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @OptionalParent(key: "business_id")
    var business: Business?

    @Field(key: "bill_title")
    var billTitle: String?

    @Field(key: "subject")
    var subject: String?

    @Field(key: "meaning_yes")
    var meaningYes: String?

    @Field(key: "meaning_no")
    var meaningNo: String?

    @Field(key: "vote_end")
    var voteEnd: Date?

    @Parent(key: "session_id")
    var session: Session

    @Children(for: \.$vote)
    var votings: [Voting]

    init() {}

    init(id: Int, sessionID: Int) {
        self.id = id
        self.$session.id = sessionID
    }
}
