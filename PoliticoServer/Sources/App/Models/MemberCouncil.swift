import Fluent
import Vapor

final class MemberCouncil: Model, Content, @unchecked Sendable {
    static let schema = "member_council"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Parent(key: "person_id")
    var person: Person

    @Field(key: "active")
    var active: Bool

    @Field(key: "date_joining")
    var dateJoining: Date?

    @Field(key: "date_leaving")
    var dateLeaving: Date?

    @Field(key: "date_election")
    var dateElection: Date?

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

    // Political positioning scores (-1.0 to 1.0)
    @Field(key: "score_left_right")
    var scoreLeftRight: Double?

    @Field(key: "score_conservative_liberal")
    var scoreConservativeLiberal: Double?

    @Field(key: "score_liberal_economy")
    var scoreLiberalEconomy: Double?

    @Field(key: "score_innovative_location")
    var scoreInnovativeLocation: Double?

    @Field(key: "score_independent_energy")
    var scoreIndependentEnergy: Double?

    @Field(key: "score_strength_resilience")
    var scoreStrengthResilience: Double?

    @Field(key: "score_lean_government")
    var scoreLeanGovernment: Double?

    init() {}

    init(id: Int, personID: Int, active: Bool) {
        self.id = id
        self.$person.id = personID
        self.active = active
    }
}
