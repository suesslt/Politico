import Fluent
import SQLKit

struct CreatePropositions: AsyncMigration {
    func prepare(on database: Database) async throws {
        // 1. Create proposition_subject table
        try await database.schema("proposition_subject")
            .field("id", .int, .identifier(auto: true))
            .field("name", .string, .required)
            .unique(on: "name")
            .create()

        // 2. Seed subjects from propositions.py
        let subjects = [
            "Geopolitik - Russland",
            "Geopolitik - China",
            "Geopolitik - USA",
            "Künstliche Intelligenz",
            "Schweizer Wirtschaft",
            "Innovation und Disruption",
            "Schweizer Geschichte",
            "Cyber",
            "Militär und Rüstung",
            "Schweizer Politik",
            "Europa und EU",
            "Energieversorgung Schweiz",
            "Staatsfinanzen Schweiz",
            "Zeitenwende",
            "Demographie und Gesellschaft",
            "Klimawandel",
            "Leadership",
            "Sicherheit Schweiz"
        ]
        for name in subjects {
            let subject = PropositionSubject(name: name)
            try await subject.create(on: database)
        }

        // 3. Refactor proposition table: add new columns, drop old ones
        try await database.schema("proposition")
            .field("proposition_subject_id", .int, .references("proposition_subject", "id"))
            .field("source", .string)
            .field("date_text", .string)
            .update()

        // Drop old columns
        try await database.schema("proposition")
            .deleteField("category")
            .deleteField("confidence")
            .update()

        // Add FK for transcript_id (was plain field before)
        let sql = database as! SQLDatabase
        try await sql.raw("""
            ALTER TABLE "proposition"
            ADD CONSTRAINT "fk_proposition_transcript"
            FOREIGN KEY ("transcript_id") REFERENCES "transcript"("id")
        """).run()

        // 4. Add propositions_extracted flag to transcript
        try await database.schema("transcript")
            .field("propositions_extracted", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: Database) async throws {
        // Remove transcript flag
        try await database.schema("transcript")
            .deleteField("propositions_extracted")
            .update()

        // Drop FK
        let sql = database as! SQLDatabase
        try await sql.raw("""
            ALTER TABLE "proposition"
            DROP CONSTRAINT IF EXISTS "fk_proposition_transcript"
        """).run()

        // Restore old columns, drop new ones
        try await database.schema("proposition")
            .field("category", .string)
            .field("confidence", .double)
            .deleteField("proposition_subject_id")
            .deleteField("source")
            .deleteField("date_text")
            .update()

        // Drop proposition_subject table
        try await database.schema("proposition_subject").delete()
    }
}
