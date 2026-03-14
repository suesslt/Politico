import Fluent
import Vapor

final class Business: Model, Content, @unchecked Sendable {
    static let schema = "business"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "business_short_number")
    var businessShortNumber: String?

    @Field(key: "title")
    var title: String

    @Field(key: "business_status_text")
    var businessStatusText: String?

    @Field(key: "business_status_date")
    var businessStatusDate: Date?

    @Field(key: "submission_date")
    var submissionDate: Date?

    @Field(key: "submitted_by")
    var submittedBy: String?

    @Field(key: "description")
    var description: String?

    @Field(key: "submission_council_name")
    var submissionCouncilName: String?

    @Field(key: "responsible_department_name")
    var responsibleDepartmentName: String?

    @Field(key: "responsible_department_abbreviation")
    var responsibleDepartmentAbbreviation: String?

    @Field(key: "tag_names")
    var tagNames: String?

    @Field(key: "modified")
    var modified: Date?

    @Parent(key: "session_id")
    var session: Session

    @OptionalParent(key: "business_type_id")
    var businessType: BusinessType?

    init() {}

    init(id: Int, title: String, sessionID: Int) {
        self.id = id
        self.title = title
        self.$session.id = sessionID
    }
}
