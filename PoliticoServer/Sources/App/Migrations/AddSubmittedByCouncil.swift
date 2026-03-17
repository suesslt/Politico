import Fluent
import SQLKit

struct AddSubmittedByCouncil: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("business")
            .field("submitted_by_council_id", .int, .references("member_council", "id"))
            .update()

        try await sql.raw("""
            UPDATE "business" b
            SET "submitted_by_council_id" = mc."id"
            FROM "member_council" mc
            WHERE b."submitted_by" = mc."last_name" || ' ' || mc."first_name"
            AND b."submitted_by" IS NOT NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("business")
            .deleteField("submitted_by_council_id")
            .update()
    }
}
