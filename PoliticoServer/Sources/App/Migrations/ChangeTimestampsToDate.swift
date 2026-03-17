import Fluent
import SQLKit

struct ChangeTimestampsToDate: AsyncMigration {
    private let columns: [(table: String, column: String)] = [
        ("business", "status_date"),
        ("business", "submission_date"),
        ("meeting", "date"),
        ("member_council", "date_of_birth"),
        ("member_council", "date_joining"),
        ("member_council", "date_election"),
        ("session", "start_date"),
        ("session", "end_date"),
        ("transcript", "meeting_date"),
    ]

    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        for col in columns {
            try await sql.raw("""
                ALTER TABLE "\(raw: col.table)"
                ALTER COLUMN "\(raw: col.column)" TYPE DATE
                USING "\(raw: col.column)"::DATE
                """).run()
        }
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        for col in columns {
            try await sql.raw("""
                ALTER TABLE "\(raw: col.table)"
                ALTER COLUMN "\(raw: col.column)" TYPE TIMESTAMP WITH TIME ZONE
                USING "\(raw: col.column)"::TIMESTAMP WITH TIME ZONE
                """).run()
        }
    }
}
