import Fluent
import Vapor

final class PersonInterest: Model, Content, @unchecked Sendable {
    static let schema = "person_interest"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Parent(key: "person_id")
    var person: Person

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

    init(personID: Int) {
        self.$person.id = personID
    }
}
