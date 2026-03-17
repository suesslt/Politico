import Fluent
import SQLKit

struct RenameBusinessColumns: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "business_short_number" TO "number"
            """).run()
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "business_status_text" TO "status"
            """).run()
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "business_status_date" TO "status_date"
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "number" TO "business_short_number"
            """).run()
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "status" TO "business_status_text"
            """).run()
        try await sql.raw("""
            ALTER TABLE "business" RENAME COLUMN "status_date" TO "business_status_date"
            """).run()
    }
}
