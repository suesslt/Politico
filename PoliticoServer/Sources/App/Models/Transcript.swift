import Fluent
import Vapor

final class Transcript: Model, Content, @unchecked Sendable {
    static let schema = "transcript"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @OptionalParent(key: "member_council_id")
    var memberCouncil: MemberCouncil?

    @Field(key: "speaker_function")
    var speakerFunction: String?

    @Field(key: "text")
    var text: String?

    @Field(key: "meeting_date")
    var meetingDate: Date?

    @Field(key: "start_time")
    var startTime: Date?

    @Field(key: "end_time")
    var endTime: Date?

    @OptionalParent(key: "council_id")
    var council: Council?

    @Field(key: "sort_order")
    var sortOrder: Int?

    @Field(key: "type")
    var type: Int?

    @OptionalParent(key: "subject_id")
    var subject: Subject?

    init() {}

    init(id: Int) {
        self.id = id
    }
}
