import Fluent
import SQLKit

struct RefactorMeetingColumns: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("""
            ALTER TABLE "meeting" RENAME COLUMN "meeting_order_text" TO "sort_order_text"
            """).run()

        try await database.schema("meeting")
            .deleteField("meeting_number")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("meeting")
            .field("meeting_number", .int)
            .update()

        try await sql.raw("""
            ALTER TABLE "meeting" RENAME COLUMN "sort_order_text" TO "meeting_order_text"
            """).run()
    }
}
