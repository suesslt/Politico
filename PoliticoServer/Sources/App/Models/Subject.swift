import Fluent
import Vapor

final class Subject: Model, Content, @unchecked Sendable {
    static let schema = "subject"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @OptionalParent(key: "meeting_id")
    var meeting: Meeting?

    @Field(key: "sort_order")
    var sortOrder: Int?

    init() {}

    init(id: Int, meetingID: Int?) {
        self.id = id
        self.$meeting.id = meetingID
    }
}
