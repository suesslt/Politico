import Fluent
import Vapor

final class MemberCouncilHistory: Model, Content, @unchecked Sendable {
    static let schema = "member_council_history"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "person_id")
    var person: Person

    @OptionalParent(key: "council_id")
    var council: Council?

    @Field(key: "date_joining")
    var dateJoining: Date?

    @Field(key: "date_leaving")
    var dateLeaving: Date?

    init() {}

    init(id: String, personID: Int) {
        self.id = id
        self.$person.id = personID
    }
}
