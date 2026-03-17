import Fluent
import SQLKit

struct RefactorPersonInterest: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Add person_id column
        try await database.schema("person_interest")
            .field("person_id", .int, .references("member_council", "id"))
            .update()

        // Backfill from person_number via member_council.person_number
        try await sql.raw("""
            UPDATE "person_interest" pi
            SET "person_id" = mc."id"
            FROM "member_council" mc
            WHERE pi."person_number" = mc."person_number"
            """).run()

        // Delete orphaned rows
        try await sql.raw("""
            DELETE FROM "person_interest" WHERE "person_id" IS NULL
            """).run()

        // Drop old column
        try await database.schema("person_interest")
            .deleteField("person_number")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("person_interest")
            .field("person_number", .int, .required)
            .update()

        try await sql.raw("""
            UPDATE "person_interest" pi
            SET "person_number" = mc."person_number"
            FROM "member_council" mc
            WHERE pi."person_id" = mc."id"
            """).run()

        try await database.schema("person_interest")
            .deleteField("person_id")
            .update()
    }
}
