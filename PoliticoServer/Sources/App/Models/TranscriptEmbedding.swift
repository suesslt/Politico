import Fluent
import Vapor

final class TranscriptEmbedding: Model, @unchecked Sendable {
    static let schema = "transcript_embedding"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Parent(key: "transcript_id")
    var transcript: Transcript

    @Field(key: "chunk_index")
    var chunkIndex: Int

    @Field(key: "chunk_text")
    var chunkText: String

    // Note: embedding field is handled via raw SQL (Fluent doesn't support vector type)

    init() {}

    init(transcriptID: Int, chunkIndex: Int = 0, chunkText: String) {
        self.$transcript.id = transcriptID
        self.chunkIndex = chunkIndex
        self.chunkText = chunkText
    }
}
