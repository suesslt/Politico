import Fluent
import Vapor

final class Meeting: Model, Content, @unchecked Sendable {
    static let schema = "meeting"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "meeting_number")
    var meetingNumber: Int?

    @Parent(key: "session_id")
    var session: Session

    @OptionalParent(key: "council_id")
    var council: Council?

    @Field(key: "date")
    var date: Date?

    @Field(key: "begin")
    var begin: String?

    @Field(key: "meeting_order_text")
    var meetingOrderText: String?

    @Field(key: "sort_order")
    var sortOrder: Int?

    @Field(key: "session_name")
    var sessionName: String?

    init() {}

    init(id: Int, sessionID: Int) {
        self.id = id
        self.$session.id = sessionID
    }
}
