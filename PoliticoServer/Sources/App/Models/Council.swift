import Fluent
import Vapor

final class Council: Model, Content, @unchecked Sendable {
    static let schema = "council"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Field(key: "abbreviation")
    var abbreviation: String?

    init() {}

    init(name: String, abbreviation: String? = nil) {
        self.name = name
        self.abbreviation = abbreviation
    }
}
