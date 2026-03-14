import Fluent
import Vapor

final class PersonInterest: Model, Content, @unchecked Sendable {
    static let schema = "person_interest"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "interest_name")
    var interestName: String?

    @Field(key: "interest_type_text")
    var interestTypeText: String?

    @Field(key: "function_in_agency_text")
    var functionInAgencyText: String?

    @Field(key: "paid")
    var paid: Bool?

    @Field(key: "organization_type_text")
    var organizationTypeText: String?

    init() {}

    init(personNumber: Int) {
        self.personNumber = personNumber
    }
}
