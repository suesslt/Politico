import Fluent

struct FixPersonInterestPaid: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("person_interests")
            .deleteField("paid")
            .update()
        try await database.schema("person_interests")
            .field("paid", .bool)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("person_interests")
            .deleteField("paid")
            .update()
        try await database.schema("person_interests")
            .field("paid", .string)
            .update()
    }
}
