import Fluent
import Vapor

final class Committee: Model, Content, @unchecked Sendable {
    static let schema = "committee"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Field(key: "abbreviation")
    var abbreviation: String?

    @Field(key: "committee_type")
    var committeeType: String?

    @OptionalParent(key: "council_id")
    var council: Council?

    @OptionalParent(key: "main_committee_id")
    var mainCommittee: Committee?

    @Field(key: "modified")
    var modified: Date?

    init() {}

    init(id: Int, name: String, abbreviation: String? = nil) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
    }
}
