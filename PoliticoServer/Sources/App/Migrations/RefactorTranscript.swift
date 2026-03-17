import Fluent
import SQLKit

struct RefactorTranscript: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // 1. Add member_council_id FK and backfill from person_number
        try await database.schema("transcript")
            .field("member_council_id", .int, .references("member_council", "id"))
            .update()

        // person_number == member_council.id in our data
        try await sql.raw("""
            UPDATE "transcript"
            SET "member_council_id" = "person_number"
            WHERE "person_number" IS NOT NULL
            """).run()

        // 2. Add council_id FK and backfill from council_name
        try await database.schema("transcript")
            .field("council_id", .int, .references("council", "id"))
            .update()

        try await sql.raw("""
            UPDATE "transcript" t
            SET "council_id" = c."id"
            FROM "council" c
            WHERE t."council_name" = c."name"
            """).run()

        // 3. Rename id_subject to subject_id
        try await sql.raw("""
            ALTER TABLE "transcript"
            RENAME COLUMN "id_subject" TO "subject_id"
            """).run()

        // 4. Drop removed columns
        try await database.schema("transcript")
            .deleteField("person_number")
            .deleteField("speaker_full_name")
            .deleteField("council_name")
            .deleteField("parl_group_abbreviation")
            .deleteField("canton_abbreviation")
            .update()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await database.schema("transcript")
            .field("person_number", .int)
            .field("speaker_full_name", .string)
            .field("council_name", .string)
            .field("parl_group_abbreviation", .string)
            .field("canton_abbreviation", .string)
            .update()

        try await sql.raw("""
            UPDATE "transcript"
            SET "person_number" = "member_council_id"
            """).run()

        try await sql.raw("""
            UPDATE "transcript" t
            SET "council_name" = c."name"
            FROM "council" c
            WHERE t."council_id" = c."id"
            """).run()

        try await sql.raw("""
            ALTER TABLE "transcript"
            RENAME COLUMN "subject_id" TO "id_subject"
            """).run()

        try await database.schema("transcript")
            .deleteField("member_council_id")
            .deleteField("council_id")
            .update()
    }
}
