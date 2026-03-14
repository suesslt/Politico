import Fluent
import SQLKit

struct RefactorMeetingCouncil: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Add council_id FK
        try await database.schema("meeting")
            .field("council_id", .int, .references("council", "id"))
            .update()

        // Backfill from council_name
        try await sql.raw("""
            UPDATE "meeting" m
            SET "council_id" = c."id"
            FROM "council" c
            WHERE m."council_name" = c."name"
            """).run()

        // Drop old columns
        try await database.schema("meeting")
            .deleteField("council")
            .deleteField("council_name")
            .deleteField("council_abbreviation")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("meeting")
            .field("council", .int)
            .field("council_name", .string)
            .field("council_abbreviation", .string)
            .update()

        try await sql.raw("""
            UPDATE "meeting" m
            SET "council_name" = c."name",
                "council_abbreviation" = c."abbreviation"
            FROM "council" c
            WHERE m."council_id" = c."id"
            """).run()

        try await database.schema("meeting")
            .deleteField("council_id")
            .update()
    }
}
