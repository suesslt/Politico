import Fluent
import Vapor

final class MemberCouncil: Model, Content, @unchecked Sendable {
    static let schema = "member_council"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "person_number")
    var personNumber: Int

    @Field(key: "first_name")
    var firstName: String

    @Field(key: "last_name")
    var lastName: String

    @Field(key: "official_name")
    var officialName: String?

    @Field(key: "gender")
    var gender: String?

    @Field(key: "active")
    var active: Bool

    @Field(key: "date_of_birth")
    var dateOfBirth: Date?

    @Field(key: "date_joining")
    var dateJoining: Date?

    @Field(key: "date_leaving")
    var dateLeaving: Date?

    @Field(key: "date_election")
    var dateElection: Date?

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

    @Field(key: "mandates")
    var mandates: String?

    @Field(key: "additional_mandate")
    var additionalMandate: String?

    @Field(key: "additional_activity")
    var additionalActivity: String?

    @Field(key: "occupation_name")
    var occupationName: String?

    @Field(key: "employer")
    var employer: String?

    @Field(key: "job_title")
    var jobTitle: String?

    @Field(key: "modified")
    var modified: Date?

    @OptionalParent(key: "council_id")
    var council: Council?

    @OptionalParent(key: "party_id")
    var party: Party?

    @OptionalParent(key: "faction_id")
    var faction: Faction?

    @OptionalParent(key: "canton_id")
    var canton: Canton?

    init() {}

    init(id: Int, personNumber: Int, firstName: String, lastName: String, active: Bool) {
        self.id = id
        self.personNumber = personNumber
        self.firstName = firstName
        self.lastName = lastName
        self.active = active
    }
}
