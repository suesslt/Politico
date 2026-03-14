import Fluent
import SQLKit

struct RenameTablesToSingular: AsyncMigration {
    private let renames: [(from: String, to: String)] = [
        ("sessions", "session"),
        ("businesses", "business"),
        ("member_councils", "member_council"),
        ("transcripts", "transcript"),
        ("votes", "vote"),
        ("votings", "voting"),
        ("meetings", "meeting"),
        ("subjects", "subject"),
        ("subject_businesses", "subject_business"),
        ("councils", "council"),
        ("parties", "party"),
        ("factions", "faction"),
        ("cantons", "canton"),
        ("propositions", "proposition"),
        ("person_interests", "person_interest"),
        ("users", "user"),
        ("sync_statuses", "sync_status"),
    ]

    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            fatalError("RenameTablesToSingular requires an SQL database")
        }
        for rename in renames {
            try await sql.raw("ALTER TABLE \"\(raw: rename.from)\" RENAME TO \"\(raw: rename.to)\"").run()
        }
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            fatalError("RenameTablesToSingular requires an SQL database")
        }
        for rename in renames.reversed() {
            try await sql.raw("ALTER TABLE \"\(raw: rename.to)\" RENAME TO \"\(raw: rename.from)\"").run()
        }
    }
}
