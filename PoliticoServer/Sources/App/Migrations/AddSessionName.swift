import Fluent

struct AddSessionName: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("sessions")
            .field("session_name", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("sessions")
            .deleteField("session_name")
            .update()
    }
}
