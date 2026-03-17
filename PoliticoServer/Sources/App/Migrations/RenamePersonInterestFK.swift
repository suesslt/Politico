import Fluent
import SQLKit

struct RenamePersonInterestFK: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "person_interest" RENAME COLUMN "person_id" TO "member_council_id"
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "person_interest" RENAME COLUMN "member_council_id" TO "person_id"
            """).run()
    }
}
