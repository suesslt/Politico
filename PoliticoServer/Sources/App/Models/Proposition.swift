import Fluent
import Vapor

final class Proposition: Model, Content, @unchecked Sendable {
    static let schema = "proposition"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Parent(key: "transcript_id")
    var transcript: Transcript

    @OptionalParent(key: "proposition_subject_id")
    var propositionSubject: PropositionSubject?

    @Field(key: "text")
    var text: String

    @Field(key: "source")
    var source: String?

    @Field(key: "date_text")
    var dateText: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(transcriptID: Int, text: String, subjectID: Int? = nil, source: String? = nil, dateText: String? = nil) {
        self.$transcript.id = transcriptID
        self.$propositionSubject.id = subjectID
        self.text = text
        self.source = source
        self.dateText = dateText
    }
}
