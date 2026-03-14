import Fluent
import Vapor

final class Session: Model, Content, @unchecked Sendable {
    static let schema = "session"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "session_name")
    var sessionName: String?

    @Field(key: "title")
    var title: String

    @Field(key: "abbreviation")
    var abbreviation: String?

    @Field(key: "start_date")
    var startDate: Date?

    @Field(key: "end_date")
    var endDate: Date?

    @Field(key: "modified")
    var modified: Date?

    @Children(for: \.$session)
    var businesses: [Business]

    @Children(for: \.$session)
    var votes: [Vote]

    @Children(for: \.$session)
    var meetings: [Meeting]

    init() {}

    init(id: Int, title: String, sessionName: String? = nil, abbreviation: String? = nil, startDate: Date? = nil, endDate: Date? = nil, modified: Date? = nil) {
        self.id = id
        self.title = title
        self.sessionName = sessionName
        self.abbreviation = abbreviation
        self.startDate = startDate
        self.endDate = endDate
        self.modified = modified
    }
}
