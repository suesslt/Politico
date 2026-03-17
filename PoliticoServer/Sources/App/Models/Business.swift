import Fluent
import Vapor

final class Business: Model, Content, @unchecked Sendable {
    static let schema = "business"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "number")
    var number: String?

    @Field(key: "title")
    var title: String

    @Field(key: "status")
    var status: String?

    @Field(key: "status_date")
    var statusDate: Date?

    @Field(key: "submission_date")
    var submissionDate: Date?

    @Field(key: "submitted_by")
    var submittedBy: String?

    @Field(key: "description")
    var description: String?

    @Field(key: "submitted_text")
    var submittedText: String?

    @Field(key: "reason_text")
    var reasonText: String?

    @Field(key: "federal_council_response")
    var federalCouncilResponse: String?

    @Field(key: "federal_council_proposal")
    var federalCouncilProposal: String?

    @Field(key: "tag_names")
    var tagNames: String?

    @Field(key: "modified")
    var modified: Date?

    @Parent(key: "session_id")
    var session: Session

    @OptionalParent(key: "business_type_id")
    var businessType: BusinessType?

    @OptionalParent(key: "submission_council_id")
    var submissionCouncil: Council?

    @OptionalParent(key: "responsible_department_id")
    var responsibleDepartment: Department?

    @OptionalParent(key: "submitted_by_council_id")
    var submittedByCouncil: MemberCouncil?

    init() {}

    init(id: Int, title: String, sessionID: Int) {
        self.id = id
        self.title = title
        self.$session.id = sessionID
    }
}
