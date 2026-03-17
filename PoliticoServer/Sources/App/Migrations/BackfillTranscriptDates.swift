import Fluent
import SQLKit

struct BackfillTranscriptDates: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            UPDATE "transcript" t
            SET "meeting_date" = m."date"
            FROM "subject" s
            JOIN "meeting" m ON m."id" = s."meeting_id"
            WHERE t."id_subject" = s."id"
            AND t."meeting_date" IS NULL
            AND m."date" IS NOT NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        // No revert needed
    }
}
