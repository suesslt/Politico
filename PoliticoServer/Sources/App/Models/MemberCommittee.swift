import Fluent
import Vapor

final class MemberCommittee: Model, Content, @unchecked Sendable {
    static let schema = "member_committee"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Parent(key: "member_council_id")
    var memberCouncil: MemberCouncil

    @Parent(key: "committee_id")
    var committee: Committee

    @Field(key: "function")
    var function: String?

    @Field(key: "modified")
    var modified: Date?

    init() {}

    init(memberCouncilID: Int, committeeID: Int, function: String? = nil) {
        self.$memberCouncil.id = memberCouncilID
        self.$committee.id = committeeID
        self.function = function
    }
}
