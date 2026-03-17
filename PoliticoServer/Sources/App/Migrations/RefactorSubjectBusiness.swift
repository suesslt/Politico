import Fluent
import SQLKit

struct RefactorSubjectBusiness: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Rename columns
        try await sql.raw("""
            ALTER TABLE "subject_business"
            RENAME COLUMN "id_subject" TO "subject_id"
            """).run()

        try await sql.raw("""
            ALTER TABLE "subject_business"
            RENAME COLUMN "business_number" TO "business_id"
            """).run()

        // Drop redundant columns
        try await database.schema("subject_business")
            .deleteField("business_short_number")
            .deleteField("title")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("subject_business")
            .field("business_short_number", .string)
            .field("title", .string)
            .update()

        try await sql.raw("""
            ALTER TABLE "subject_business"
            RENAME COLUMN "subject_id" TO "id_subject"
            """).run()

        try await sql.raw("""
            ALTER TABLE "subject_business"
            RENAME COLUMN "business_id" TO "business_number"
            """).run()
    }
}
