import Fluent
import Vapor

final class PropositionSubject: Model, Content, @unchecked Sendable {
    static let schema = "proposition_subject"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Children(for: \.$propositionSubject)
    var propositions: [Proposition]

    init() {}

    init(id: Int? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
