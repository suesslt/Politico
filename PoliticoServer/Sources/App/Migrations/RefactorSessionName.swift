import Fluent
import SQLKit

struct RefactorSessionName: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Backfill session_name from title where session_name is null
        try await sql.raw("""
            UPDATE "session"
            SET "session_name" = "title"
            WHERE "session_name" IS NULL
            """).run()

        // Rename session_name to name
        try await sql.raw("""
            ALTER TABLE "session" RENAME COLUMN "session_name" TO "name"
            """).run()

        // Make name NOT NULL
        try await sql.raw("""
            ALTER TABLE "session" ALTER COLUMN "name" SET NOT NULL
            """).run()

        // Drop title
        try await database.schema("session")
            .deleteField("title")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("session")
            .field("title", .string, .required)
            .update()

        try await sql.raw("""
            UPDATE "session" SET "title" = "name"
            """).run()

        try await sql.raw("""
            ALTER TABLE "session" RENAME COLUMN "name" TO "session_name"
            """).run()
    }
}
