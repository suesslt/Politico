import Fluent
import SQLKit

struct RenameSubjectMeetingId: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "subject" RENAME COLUMN "id_meeting" TO "meeting_id"
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "subject" RENAME COLUMN "meeting_id" TO "id_meeting"
            """).run()
    }
}
