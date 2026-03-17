import Fluent
import SQLKit

struct RefactorVoteBusiness: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Rename business_number to business_id
        try await sql.raw("""
            ALTER TABLE "vote" RENAME COLUMN "business_number" TO "business_id"
            """).run()

        // Nullify business_id values that don't exist in business table
        try await sql.raw("""
            UPDATE "vote"
            SET "business_id" = NULL
            WHERE "business_id" IS NOT NULL
            AND "business_id" NOT IN (SELECT "id" FROM "business")
            """).run()

        // Add FK constraint
        try await sql.raw("""
            ALTER TABLE "vote"
            ADD CONSTRAINT "fk_vote_business"
            FOREIGN KEY ("business_id") REFERENCES "business"("id")
            """).run()

        // Drop business_short_number
        try await database.schema("vote")
            .deleteField("business_short_number")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("vote")
            .field("business_short_number", .string)
            .update()

        try await sql.raw("""
            ALTER TABLE "vote" DROP CONSTRAINT IF EXISTS "fk_vote_business"
            """).run()

        try await sql.raw("""
            ALTER TABLE "vote" RENAME COLUMN "business_id" TO "business_number"
            """).run()
    }
}
