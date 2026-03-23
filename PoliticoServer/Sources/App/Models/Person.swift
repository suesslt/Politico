import Fluent
import Vapor

final class Person: Model, Content, @unchecked Sendable {
    static let schema = "person"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "first_name")
    var firstName: String

    @Field(key: "last_name")
    var lastName: String

    @Field(key: "official_name")
    var officialName: String?

    @Field(key: "gender")
    var gender: String?

    @Field(key: "date_of_birth")
    var dateOfBirth: Date?

    @Field(key: "date_of_death")
    var dateOfDeath: Date?

    @Field(key: "marital_status")
    var maritalStatus: String?

    @Field(key: "number_of_children")
    var numberOfChildren: Int?

    @Field(key: "birth_place_city")
    var birthPlaceCity: String?

    @Field(key: "birth_place_canton")
    var birthPlaceCanton: String?

    @Field(key: "citizenship")
    var citizenship: String?

    @Field(key: "military_rank")
    var militaryRank: String?

    @Field(key: "nationality")
    var nationality: String?

    @Field(key: "native_language")
    var nativeLanguage: String?

    @Field(key: "modified")
    var modified: Date?

    @Children(for: \.$person)
    var memberCouncils: [MemberCouncil]

    @Children(for: \.$person)
    var memberCouncilHistories: [MemberCouncilHistory]

    init() {}

    init(id: Int, firstName: String, lastName: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
    }
}
