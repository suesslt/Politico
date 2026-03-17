import Fluent
import Vapor

final class SubjectBusiness: Model, Content, @unchecked Sendable {
    static let schema = "subject_business"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "subject_id")
    var subjectID: Int?

    @Field(key: "business_id")
    var businessID: Int?

    @Field(key: "sort_order")
    var sortOrder: Int?

    init() {}

    init(subjectID: Int?, businessID: Int?) {
        self.subjectID = subjectID
        self.businessID = businessID
    }
}
