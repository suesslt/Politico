import Fluent
import SQLKit

struct RefactorVotingMemberCouncil: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Add member_council_id column
        try await database.schema("voting")
            .field("member_council_id", .int, .references("member_council", "id"))
            .update()

        // Backfill: person_number maps to member_council.id
        try await sql.raw("""
            UPDATE "voting" v
            SET "member_council_id" = mc."id"
            FROM "member_council" mc
            WHERE v."person_number" = mc."person_number"
            """).run()

        // Drop old column
        try await database.schema("voting")
            .deleteField("person_number")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("voting")
            .field("person_number", .int, .required)
            .update()

        try await sql.raw("""
            UPDATE "voting" v
            SET "person_number" = mc."person_number"
            FROM "member_council" mc
            WHERE v."member_council_id" = mc."id"
            """).run()

        try await database.schema("voting")
            .deleteField("member_council_id")
            .update()
    }
}
