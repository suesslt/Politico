import Fluent
import Vapor

final class SubjectBusiness: Model, Content, @unchecked Sendable {
    static let schema = "subject_business"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "id_subject")
    var idSubject: Int?

    @Field(key: "business_number")
    var businessNumber: Int?

    @Field(key: "business_short_number")
    var businessShortNumber: String?

    @Field(key: "title")
    var title: String?

    @Field(key: "sort_order")
    var sortOrder: Int?

    init() {}

    init(idSubject: Int?, businessNumber: Int?) {
        self.idSubject = idSubject
        self.businessNumber = businessNumber
    }
}
