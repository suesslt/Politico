import Fluent
import Vapor

final class Party: Model, Content, @unchecked Sendable {
    static let schema = "party"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String?

    @Field(key: "abbreviation")
    var abbreviation: String

    @Field(key: "color")
    var color: String?

    init() {}

    init(abbreviation: String, name: String? = nil, color: String? = nil) {
        self.abbreviation = abbreviation
        self.name = name
        self.color = color
    }
}
