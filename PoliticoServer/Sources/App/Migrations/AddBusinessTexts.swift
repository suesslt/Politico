import Fluent

struct AddBusinessTexts: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("business")
            .field("submitted_text", .sql(raw: "TEXT"))
            .field("reason_text", .sql(raw: "TEXT"))
            .field("federal_council_response", .sql(raw: "TEXT"))
            .field("federal_council_proposal", .sql(raw: "TEXT"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("business")
            .deleteField("submitted_text")
            .deleteField("reason_text")
            .deleteField("federal_council_response")
            .deleteField("federal_council_proposal")
            .update()
    }
}
