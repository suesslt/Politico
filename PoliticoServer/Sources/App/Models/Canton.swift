import Fluent
import Vapor

final class Canton: Model, Content, @unchecked Sendable {
    static let schema = "canton"

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
