import Fluent
import Vapor

final class Transcript: Model, Content, @unchecked Sendable {
    static let schema = "transcript"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "person_number")
    var personNumber: Int?

    @Field(key: "speaker_full_name")
    var speakerFullName: String?

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

    @Field(key: "council_name")
    var councilName: String?

    @Field(key: "parl_group_abbreviation")
    var parlGroupAbbreviation: String?

    @Field(key: "canton_abbreviation")
    var cantonAbbreviation: String?

    @Field(key: "sort_order")
    var sortOrder: Int?

    @Field(key: "type")
    var type: Int?

    @Field(key: "id_subject")
    var idSubject: Int?

    init() {}

    init(id: Int) {
        self.id = id
    }
}
