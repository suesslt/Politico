import Fluent
import SQLKit

struct AddSubjectBusinessFKs: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Remove orphaned rows that would violate FK constraints
        try await sql.raw("""
            DELETE FROM "subject_business"
            WHERE "business_id" IS NOT NULL
            AND "business_id" NOT IN (SELECT "id" FROM "business")
            """).run()

        try await sql.raw("""
            DELETE FROM "subject_business"
            WHERE "subject_id" IS NOT NULL
            AND "subject_id" NOT IN (SELECT "id" FROM "subject")
            """).run()

        try await sql.raw("""
            ALTER TABLE "subject_business"
            ADD CONSTRAINT "fk_subject_business_business"
            FOREIGN KEY ("business_id") REFERENCES "business"("id")
            """).run()

        try await sql.raw("""
            ALTER TABLE "subject_business"
            ADD CONSTRAINT "fk_subject_business_subject"
            FOREIGN KEY ("subject_id") REFERENCES "subject"("id")
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "subject_business" DROP CONSTRAINT IF EXISTS "fk_subject_business_business"
            """).run()
        try await sql.raw("""
            ALTER TABLE "subject_business" DROP CONSTRAINT IF EXISTS "fk_subject_business_subject"
            """).run()
    }
}
