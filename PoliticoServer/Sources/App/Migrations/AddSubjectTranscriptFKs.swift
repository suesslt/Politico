import Fluent
import SQLKit

struct AddSubjectTranscriptFKs: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Clean orphans before adding constraints
        try await sql.raw("""
            UPDATE "subject" SET "meeting_id" = NULL
            WHERE "meeting_id" IS NOT NULL
            AND "meeting_id" NOT IN (SELECT "id" FROM "meeting")
            """).run()

        try await sql.raw("""
            UPDATE "transcript" SET "subject_id" = NULL
            WHERE "subject_id" IS NOT NULL
            AND "subject_id" NOT IN (SELECT "id" FROM "subject")
            """).run()

        try await sql.raw("""
            ALTER TABLE "subject"
            ADD CONSTRAINT "fk_subject_meeting"
            FOREIGN KEY ("meeting_id") REFERENCES "meeting"("id")
            """).run()

        try await sql.raw("""
            ALTER TABLE "transcript"
            ADD CONSTRAINT "fk_transcript_subject"
            FOREIGN KEY ("subject_id") REFERENCES "subject"("id")
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            ALTER TABLE "transcript" DROP CONSTRAINT IF EXISTS "fk_transcript_subject"
            """).run()
        try await sql.raw("""
            ALTER TABLE "subject" DROP CONSTRAINT IF EXISTS "fk_subject_meeting"
            """).run()
    }
}
