import Fluent
import Vapor

final class Proposition: Model, Content, @unchecked Sendable {
    static let schema = "proposition"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "transcript_id")
    var transcriptID: Int?

    @Field(key: "text")
    var text: String

    @Field(key: "category")
    var category: String?

    @Field(key: "confidence")
    var confidence: Double?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(transcriptID: Int?, text: String, category: String? = nil, confidence: Double? = nil) {
        self.transcriptID = transcriptID
        self.text = text
        self.category = category
        self.confidence = confidence
    }
}
