import Fluent
import Vapor

final class Faction: Model, Content, @unchecked Sendable {
    static let schema = "faction"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String?

    @Field(key: "abbreviation")
    var abbreviation: String

    init() {}

    init(abbreviation: String, name: String? = nil) {
        self.abbreviation = abbreviation
        self.name = name
    }
}
